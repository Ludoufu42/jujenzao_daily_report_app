import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../db/report_repository.dart';
import '../models/project.dart';
import '../models/project_bundle.dart';
import '../models/trade_category.dart';
import '../models/trade_type.dart';
import '../wizard/report_draft.dart';
import '../wizard/report_preview_data.dart';
import '../wizard/report_saver.dart';
import 'app_clock.dart';
import 'cloud_report_sync.dart';
import 'cloud_service.dart';
import 'pdf_service.dart';
import 'report_upload.dart';
import 'simulation_plan.dart';

class SimulationOptions {
  /// 每天先送出一次(上午)再送出一次(下午),模擬中午前、下班前各填一次。
  final bool twoSubmits;

  /// 每天都產生 PDF 並上傳。
  final bool withPdf;
  final int seed;

  /// 只跑前幾天(null = 跑完整個專案)。
  final int? maxDays;

  /// 目標完工日:模擬的工期依它推算(例如合約工期的最後一天)。
  /// null = 用工程管理的預定完工日。
  final DateTime? targetEnd;

  /// 每天員工忘記填日報的機率。忘記的日子工期照跑,約六成過 1~3 天補登。
  final double forgetRate;

  const SimulationOptions({
    this.twoSubmits = true,
    this.withPdf = true,
    this.seed = 1,
    this.maxDays,
    this.targetEnd,
    this.forgetRate = 0.04,
  });
}

/// 模擬執行的進度(畫面監聽它)。
class SimulationState extends ChangeNotifier {
  int total = 0;
  int done = 0;
  int jsonOk = 0;
  int jsonFailed = 0;
  int pdfOk = 0;
  int pdfFailed = 0;
  int errors = 0;
  int forgot = 0;
  int backfilled = 0;
  bool running = false;
  bool finished = false;
  bool cancelled = false;
  String current = '';
  String? summary;
  final List<String> log = [];
  final Stopwatch clock = Stopwatch();

  void add(String line) {
    log.add(line);
    if (log.length > 300) log.removeRange(0, log.length - 300);
  }

  void changed() => notifyListeners();
}

/// 貝塔版:不管真實時間,把整個專案從開工到完工一天一天的日報「填」出來。
///
/// 每一天都走和手動填日報同一套邏輯:草稿 → [persistDraft] 存本機資料庫 →
/// 上傳雲端 → (選擇)產生 PDF 上傳。畫面上的下拉選單與步驟不在這裡測,
/// 那些用「模擬日期」搭配手動操作測。
class ReportSimulator {
  ReportSimulator({
    required this.project,
    required this.bundle,
    ReportRepository? repo,
    CloudService? cloud,
  }) : _repo = repo ?? ReportRepository.instance,
       _cloud = cloud ?? CloudService.instance;

  final Project project;
  final ProjectBundle bundle;
  final ReportRepository _repo;
  final CloudService _cloud;
  final SimulationState state = SimulationState();

  void cancel() {
    state.cancelled = true;
    state.changed();
  }

  Future<void> run(SimulationOptions options) async {
    state
      ..running = true
      ..finished = false
      ..cancelled = false
      ..done = 0
      ..jsonOk = 0
      ..jsonFailed = 0
      ..pdfOk = 0
      ..pdfFailed = 0
      ..errors = 0
      ..forgot = 0
      ..backfilled = 0
      ..summary = null
      ..log.clear();
    state.clock
      ..reset()
      ..start();

    var plan = SimulationPlan.generate(
      sequence: bundle.sequence,
      start: bundle.plannedStart ?? project.startDate,
      targetEnd: options.targetEnd ?? bundle.plannedEnd,
      seed: options.seed,
      forgetRate: options.forgetRate,
    );
    if (options.maxDays != null && options.maxDays! < plan.length) {
      plan = plan.sublist(0, options.maxDays!);
    }
    state.total = plan.length;
    state.add(
      '計畫:${plan.length} 天(${_d(plan.first.date)} ~ ${_d(plan.last.date)}),'
      '${bundle.sequence.items.length} 個要徑項目,'
      '${options.twoSubmits ? "每天送出 2 次" : "每天送出 1 次"},'
      '${options.withPdf ? "每天產 PDF" : "不產 PDF"}',
    );
    state.changed();

    final rng = Random(options.seed + 1000);
    final types = await _loadTradeTypes();
    final signature = options.withPdf ? await _makeSignature() : null;

    var consecutiveErrors = 0;
    // 忘記填、之後要補登的日子:(到期是第幾天, 那一天)
    final pending = <(int, SimDay)>[];
    for (var i = 0; i < plan.length; i++) {
      if (state.cancelled) {
        state.add('已停止(做到第 $i 天)');
        break;
      }
      final day = plan[i];
      state.current = '第 ${i + 1}/${plan.length} 天 ${_d(day.date)}';
      state.changed();
      try {
        if (day.forgot) {
          // 員工忘了填:這天沒有日報,工期照跑(不影響工作天的計算)。
          state.forgot++;
          state.add(
            '○ ${_d(day.date)} 員工忘了填日報(工期照跑)'
            '${day.backfillAfter > 0 ? ",${day.backfillAfter} 天後補登" : ",一直沒補"}',
          );
          if (day.backfillAfter > 0) {
            pending.add((i + day.backfillAfter, day));
          }
        } else {
          await _simulateDay(day, i, rng, types, options, signature);
        }
        // 補登到期的日子:今天(模擬時鐘)補填之前忘記的那天。
        for (final p in pending.where((p) => p.$1 <= i).toList()) {
          pending.remove(p);
          await _simulateDay(
            p.$2,
            plan.indexOf(p.$2),
            rng,
            types,
            options,
            signature,
            backfill: true,
            clockDate: day.date,
          );
          state.backfilled++;
        }
        consecutiveErrors = 0;
      } catch (e) {
        state.errors++;
        consecutiveErrors++;
        state.add('✗ ${_d(day.date)} 失敗:$e');
        if (consecutiveErrors >= 8) {
          state.add('連續失敗 8 天,中止');
          break;
        }
      }
      state.done = i + 1;
      state.changed();
      // 讓畫面有機會重繪、不卡住。
      await Future<void>.delayed(Duration.zero);
    }

    await _verify(plan, options);
    state.clock.stop();
    state
      ..running = false
      ..finished = true;
    state.changed();
  }

  // ---------------- 一天 ----------------

  Future<void> _simulateDay(
    SimDay day,
    int index,
    Random rng,
    Map<TradeCategoryType, List<TradeType>> types,
    SimulationOptions options,
    Uint8List? signature, {
    bool backfill = false,
    DateTime? clockDate,
  }) async {
    // 補登:模擬時鐘是「今天」,日報的日期是之前忘記的那天(App 會標成補登)。
    AppClock.simulate(clockDate ?? day.date);
    final draft = ReportDraft(project)
      ..reportDate = DateTime(day.date.year, day.date.month, day.date.day)
      ..isBackfillEntry = backfill
      ..setSequence(bundle.sequence);
    final existing = await _repo.getReportByDate(project.id!, day.date);
    if (existing != null) draft.existingReportId = existing.id;

    draft
      ..weatherAm = day.weatherAm
      ..weatherPm = day.weatherPm
      ..todayWorkCode = day.today.code
      ..todayWorkVer = bundle.ver
      ..tomorrowWorkCode = day.tomorrow.code
      ..tomorrowWorkVer = bundle.ver
      ..notes = index % 10 == 0 ? '模擬備註:第 ${index + 1} 天,材料進場' : '';

    _fillEntries(draft, day, rng, types);

    if (options.twoSubmits && !backfill) {
      // 中午前:只有上午的出工
      draft.todayProgress =
          '上午:${day.today.name}${day.stopped ? '(${day.offReason})' : ''}';
      draft.tomorrowProgress = '';
      for (final e in draft.laborEntries.values) {
        e.afternoon = null;
      }
      await _saveAndUpload(draft, day, pdf: false, signature: null);
      _fillEntries(draft, day, rng, types, keepCrew: true);
    }

    // 下班前:完整的一份
    draft.todayProgress =
        '模擬第 ${index + 1} 天:${day.today.name}'
        '${day.finished > 0 ? '(完成 ${day.finished} 項)' : ''}'
        '${day.stopped ? '(${day.offReason})' : ''}';
    draft.tomorrowProgress = '預計:${day.tomorrow.name}';
    await _saveAndUpload(
      draft,
      day,
      pdf: options.withPdf,
      signature: signature,
    );
    state.add(
      '${backfill ? "↺ 補登" : "✓"} ${_d(day.date)} ${day.today.code}→${day.tomorrow.code}'
      '${day.stopped ? " ${day.offReason}(不計工期)" : ""}${day.finished == 2 ? " 一天做完兩項" : ""}',
    );
  }

  Future<void> _saveAndUpload(
    ReportDraft draft,
    SimDay day, {
    required bool pdf,
    required Uint8List? signature,
  }) async {
    await persistDraft(draft, _repo);
    final data = await ReportPreviewData.build(draft, _repo);
    final msg = await uploadReportToCloud(draft, data);
    if (msg.contains('並上傳雲端')) {
      state.jsonOk++;
    } else {
      state.jsonFailed++;
      state.add('! ${_d(day.date)} $msg');
    }
    if (pdf) {
      final bytes = await PdfService.generate(
        draft: draft,
        data: data,
        photoPaths: const [],
        supervisorSignature: signature,
      );
      final pmsg = await uploadReportPdfToCloud(draft, data, bytes);
      if (pmsg.contains('已上傳雲端')) {
        state.pdfOk++;
      } else {
        state.pdfFailed++;
        state.add('! ${_d(day.date)} $pmsg');
      }
    }
  }

  // ---------------- 內容 ----------------

  static const _vendors = ['大成工程行', '永固鋼筋', '宏達模板', '眾安水電', '鼎立砌磚'];

  void _fillEntries(
    ReportDraft draft,
    SimDay day,
    Random rng,
    Map<TradeCategoryType, List<TradeType>> types, {
    bool keepCrew = false,
  }) {
    if (!keepCrew) {
      draft.laborEntries.clear();
      draft.materialEntries.clear();
      draft.equipmentEntries.clear();
      final labor = List<TradeType>.of(
        types[TradeCategoryType.labor] ?? const [],
      )..shuffle(rng);
      // 不計工期的日子(週末、國定假日、颱風)工地多半沒人,偶爾有人留守。
      final crew = day.stopped ? rng.nextInt(2) : 3 + rng.nextInt(5);
      for (final t in labor.take(crew)) {
        final sub = rng.nextDouble() < 0.3;
        draft.laborFor(t.id!)
          ..morning = (1 + rng.nextInt(8)).toDouble()
          ..afternoon = rng.nextInt(9).toDouble()
          ..isSubcontracted = sub
          ..vendor = sub ? _vendors[rng.nextInt(_vendors.length)] : ''
          ..todayContent = '${day.today.name} 配合'
          ..tomorrowContent = '${day.tomorrow.name} 準備';
      }
      final mats = List<TradeType>.of(
        types[TradeCategoryType.material] ?? const [],
      )..shuffle(rng);
      for (final t in mats.take(day.stopped ? 0 : 1 + rng.nextInt(3))) {
        draft.materialFor(t.id!)
          ..quantity = (1 + rng.nextInt(50)).toDouble()
          ..usageLocation = day.today.grp.isNotEmpty ? day.today.grp : '現場';
      }
      final eq = List<TradeType>.of(
        types[TradeCategoryType.equipment] ?? const [],
      )..shuffle(rng);
      for (final t in eq.take(day.stopped ? 0 : rng.nextInt(3))) {
        draft.equipmentFor(t.id!)
          ..quantity = (1 + rng.nextInt(3)).toDouble()
          ..isSubcontracted = false
          ..todayContent = day.today.name;
      }
    } else {
      // 下午:補上下午的出工(上午已經有的人)。
      for (final e in draft.laborEntries.values) {
        e.afternoon = rng.nextInt(9).toDouble();
      }
    }
  }

  Future<Map<TradeCategoryType, List<TradeType>>> _loadTradeTypes() async {
    final out = <TradeCategoryType, List<TradeType>>{};
    for (final c in kTradeCategories) {
      final list = await _repo.getTradeTypes(project.id!, c.name);
      out.putIfAbsent(c.type, () => []).addAll(list);
    }
    return out;
  }

  /// 假的簽名圖(幾筆線),讓 PDF 裡有簽名欄位的圖。
  Future<Uint8List> _makeSignature() async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      const ui.Rect.fromLTWH(0, 0, 240, 90),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );
    final paint = ui.Paint()
      ..color = const ui.Color(0xFF111111)
      ..strokeWidth = 3
      ..style = ui.PaintingStyle.stroke;
    final path = ui.Path()
      ..moveTo(15, 60)
      ..quadraticBezierTo(45, 5, 75, 55)
      ..quadraticBezierTo(105, 90, 140, 30)
      ..quadraticBezierTo(175, 0, 225, 50);
    canvas.drawPath(path, paint);
    final image = await recorder.endRecording().toImage(240, 90);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  }

  // ---------------- 驗證 ----------------

  Future<void> _verify(List<SimDay> plan, SimulationOptions options) async {
    final lines = <String>[];
    final local = await _repo.getReports(project.id!);
    final planned = plan.length;
    final localDays = {
      for (final r in local) CloudReportSync.dateKey(r.reportDate),
    };
    // 沒有日報的日子:忘記填又沒補登的(預期的),以及其他(不預期的,代表有問題)。
    final absent = plan
        .where((d) => !localDays.contains(CloudReportSync.dateKey(d.date)))
        .toList();
    final expectedAbsent = absent.where((d) => d.forgot).length;
    final unexpected = absent.length - expectedAbsent;
    lines.add(
      '本機日報 ${local.length} 天(計畫 $planned 天;員工忘記填 ${state.forgot} 天,'
      '其中補登 ${state.backfilled} 天、仍缺 $expectedAbsent 天;'
      '不明原因缺 $unexpected 天)',
    );
    lines.add('工期照跑:缺日報的 $expectedAbsent 天,工作天仍照日曆計算(不因漏填而少算)');
    final backfilledInDb = await _repo.countBackfilledReports(project.id!);
    lines.add(
      '補登紀錄 $backfilledInDb 筆(模擬補登 ${state.backfilled} 筆:'
      '${backfilledInDb == state.backfilled ? "一致" : "不一致"})',
    );

    // 雲端抽查:第一天、最後一天、加三個隨機的日子。
    final pid = project.platformProjectId;
    if (pid != null && plan.isNotEmpty) {
      final rng = Random(options.seed + 7);
      final picks = <SimDay>{
        plan.first,
        plan.last,
        for (var i = 0; i < 3; i++) plan[rng.nextInt(plan.length)],
      }..removeWhere((d) => d.forgot);
      var bad = 0;
      for (final d in picks) {
        try {
          final j = await _cloud.fetchReport(
            pid,
            CloudReportSync.dateKey(d.date),
          );
          final rev = (j?['rev'] as num?)?.toInt() ?? 0;
          final code = (j?['today_work'] as Map?)?['code'];
          final want = options.twoSubmits ? 2 : 1;
          if (j == null || code != d.today.code || rev < want) {
            bad++;
            lines.add(
              '  ✗ 雲端 ${_d(d.date)}:今日要徑 $code、第 $rev 次(應為 ${d.today.code}、至少第 $want 次)',
            );
          }
        } catch (e) {
          bad++;
          lines.add('  ✗ 雲端 ${_d(d.date)}:$e');
        }
      }
      lines.add('雲端抽查 ${picks.length} 天:${bad == 0 ? "全部正確" : "$bad 天有問題"}');
    }

    lines.add(
      '日報上傳 成功 ${state.jsonOk} / 失敗 ${state.jsonFailed};'
      'PDF 成功 ${state.pdfOk} / 失敗 ${state.pdfFailed};'
      '執行失敗 ${state.errors} 天;花了 ${state.clock.elapsed.inSeconds} 秒',
    );
    state.summary = lines.join('\n');
    for (final l in lines) {
      state.add(l);
    }
  }

  static String _d(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
