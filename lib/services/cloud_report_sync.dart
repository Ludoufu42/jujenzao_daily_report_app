import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../db/report_repository.dart';
import '../models/daily_report.dart';
import '../models/project.dart';
import '../models/trade_category.dart';
import '../models/trade_type.dart';
import '../models/weather.dart';
import 'cloud_service.dart';

/// 前一份日報(本機或雲端)。今日要徑不能早於它的今日要徑。
class PreviousReport {
  final DateTime date;
  final String? todayWorkCode;
  final String? tomorrowWorkCode;

  /// 來自雲端(別支手機送的):本機沒有它的查驗紀錄,不能拿來判斷查驗有沒有做。
  final bool fromCloud;
  const PreviousReport({
    required this.date,
    required this.todayWorkCode,
    required this.tomorrowWorkCode,
    required this.fromCloud,
  });
}

class PullOutcome {
  /// 是否把雲端的日報載進本機了。
  final bool imported;

  /// 要顯示給使用者的說明(例如「已載入王小明 17:40 送出的第 2 次日報」)。
  final String? note;

  /// 連不上雲端等錯誤;本機照常往下走。
  final String? error;
  const PullOutcome({this.imported = false, this.note, this.error});
}

/// 一天會填兩次(中午前、下班前),可能用不同支手機。開日報前先看雲端有沒有
/// 當天已送出的最新一份,比本機新就載進來再接著改,避免把先前填的蓋掉。
///
/// 「本機新不新」用修訂號判斷:每次上傳成功就記下雲端回的修訂號;
/// 雲端的修訂號比本機記的大,就以雲端為準。
class CloudReportSync {
  CloudReportSync({CloudService? cloud, ReportRepository? repo})
    : _cloud = cloud ?? CloudService.instance,
      _repo = repo ?? ReportRepository.instance;

  final CloudService _cloud;
  final ReportRepository _repo;

  static String _revKey(int pid, String date) => 'cloud_rev_${pid}_$date';
  static String dateKey(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  Future<int> localRev(int platformProjectId, String date) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_revKey(platformProjectId, date)) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<void> recordRev(int platformProjectId, String date, int rev) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_revKey(platformProjectId, date), rev);
    } catch (_) {}
  }

  /// 早於 [date] 的最新一份日報:本機和雲端各找一份,取日期較新的
  /// (同一天以本機為準,因為本機有查驗紀錄)。連不上雲端就只用本機的。
  Future<PreviousReport?> previousReport(Project project, DateTime date) async {
    final local = project.id == null
        ? null
        : await _repo.getMostRecentReportBefore(project.id!, date);
    PreviousReport? fromLocal;
    if (local != null) {
      fromLocal = PreviousReport(
        date: local.reportDate,
        todayWorkCode: local.todayWorkCode,
        tomorrowWorkCode: local.tomorrowWorkCode,
        fromCloud: false,
      );
    }
    final pid = project.platformProjectId;
    if (pid == null) return fromLocal;
    try {
      final j = await _cloud.fetchPreviousReport(pid, dateKey(date));
      if (j == null) return fromLocal;
      final d = DateTime.tryParse(j['report_date'] as String? ?? '');
      if (d == null) return fromLocal;
      if (fromLocal != null && !d.isAfter(fromLocal.date)) return fromLocal;
      Map<String, dynamic> work(String k) =>
          (j[k] as Map?)?.cast<String, dynamic>() ?? const {};
      return PreviousReport(
        date: d,
        todayWorkCode: work('today_work')['code'] as String?,
        tomorrowWorkCode: work('tomorrow_work')['code'] as String?,
        fromCloud: true,
      );
    } catch (_) {
      return fromLocal;
    }
  }

  Future<PullOutcome> pullIfNewer(Project project, DateTime date) async {
    final pid = project.platformProjectId;
    if (pid == null || project.id == null) return const PullOutcome();
    final key = dateKey(date);
    final Map<String, dynamic>? cloud;
    try {
      cloud = await _cloud.fetchReport(pid, key);
    } on CloudException catch (e) {
      return PullOutcome(error: e.message);
    } catch (e) {
      return PullOutcome(error: '連不到雲端($e)');
    }
    if (cloud == null) return const PullOutcome();
    final cloudRev = (cloud['rev'] as num?)?.toInt() ?? 0;
    if (cloudRev <= await localRev(pid, key)) return const PullOutcome();

    await _import(project, date, cloud);
    await recordRev(pid, key, cloudRev);
    final by = (cloud['filled_by'] as Map?)?['name'] as String?;
    final at = cloud['submitted_at'] as String? ?? '';
    return PullOutcome(
      imported: true,
      note: '已載入雲端上${by != null && by.isNotEmpty ? ' $by ' : ''}$at 送出的第 $cloudRev 次日報，可接著修改',
    );
  }

  Future<void> _import(
    Project project,
    DateTime date,
    Map<String, dynamic> j,
  ) async {
    final pid = project.id!;
    Weather weather(Object? v) => Weather.values.firstWhere(
      (w) => w.name == v,
      orElse: () => Weather.sunny,
    );
    Map<String, dynamic> work(String k) =>
        (j[k] as Map?)?.cast<String, dynamic>() ?? const {};
    final existing = await _repo.getReportByDate(pid, date);

    final report = DailyReport(
      id: existing?.id,
      projectId: pid,
      reportDate: DateTime(date.year, date.month, date.day),
      weatherAm: weather(j['weather_am']),
      weatherPm: weather(j['weather_pm']),
      isRainOrHoliday: j['is_rain_or_holiday'] == true,
      todayWorkCode: work('today_work')['code'] as String?,
      todayWorkVer: (work('today_work')['ver'] as num?)?.toInt(),
      tomorrowWorkCode: work('tomorrow_work')['code'] as String?,
      tomorrowWorkVer: (work('tomorrow_work')['ver'] as num?)?.toInt(),
      todayProgressText: j['today_progress'] as String? ?? '',
      tomorrowProgressText: j['tomorrow_progress'] as String? ?? '',
      notesText: j['notes'] as String? ?? '',
      isBackfilled: existing?.isBackfilled ?? j['is_backfill'] == true,
      createdAt: existing?.createdAt ?? DateTime.now(),
    );

    final labor = <LaborEntryInput>[];
    for (final r in (j['labor'] as List? ?? const [])) {
      final m = (r as Map).cast<String, dynamic>();
      final t = await _tradeType(pid, m, TradeCategoryType.labor);
      labor.add(
        LaborEntryInput(
          tradeTypeId: t.id!,
          morningCount: (m['morning'] as num?)?.toDouble() ?? 0,
          afternoonCount: (m['afternoon'] as num?)?.toDouble() ?? 0,
          isSubcontracted: m['is_subcontracted'] == true,
          vendor: m['vendor'] as String? ?? '',
          todayContent: m['today_content'] as String? ?? '',
          tomorrowContent: m['tomorrow_content'] as String? ?? '',
        ),
      );
    }
    final materials = <MaterialEntryInput>[];
    for (final r in (j['materials'] as List? ?? const [])) {
      final m = (r as Map).cast<String, dynamic>();
      final t = await _tradeType(pid, m, TradeCategoryType.material);
      materials.add(
        MaterialEntryInput(
          tradeTypeId: t.id!,
          quantity: (m['quantity'] as num?)?.toDouble() ?? 0,
          usageLocation: m['usage_location'] as String? ?? '',
        ),
      );
    }
    final equipment = <EquipmentEntryInput>[];
    for (final r in (j['equipment'] as List? ?? const [])) {
      final m = (r as Map).cast<String, dynamic>();
      final t = await _tradeType(pid, m, TradeCategoryType.equipment);
      equipment.add(
        EquipmentEntryInput(
          tradeTypeId: t.id!,
          quantity: (m['quantity'] as num?)?.toDouble() ?? 0,
          isSubcontracted: m['is_subcontracted'] == true,
          vendor: m['vendor'] as String? ?? '',
          todayContent: m['today_content'] as String? ?? '',
          tomorrowContent: m['tomorrow_content'] as String? ?? '',
        ),
      );
    }

    if (existing == null) {
      await _repo.createDailyReportWithEntries(
        report: report,
        laborInputs: labor,
        materialInputs: materials,
        equipmentInputs: equipment,
        photoPaths: const [],
      );
    } else {
      // 照片只在本機(雲端日報只記張數),載入雲端內容時保留這支手機原有的照片。
      final photos = await _repo.getReportPhotos(existing.id!);
      await _repo.updateDailyReportWithEntries(
        report: report,
        laborInputs: labor,
        materialInputs: materials,
        equipmentInputs: equipment,
        photoPaths: photos.map((p) => p.filePath).toList(),
      );
    }
  }

  /// 依「類別 + 名稱」找本機的工種/材料/機具;別支手機自己新增的項目這裡沒有就補建。
  Future<TradeType> _tradeType(
    int projectId,
    Map<String, dynamic> m,
    TradeCategoryType type,
  ) async {
    final category = m['category'] as String? ?? '';
    final name = m['name'] as String? ?? '';
    final all = await _repo.getTradeTypes(
      projectId,
      category,
      includeDisabledAndDeleted: true,
    );
    for (final t in all) {
      if (t.name == name) return t;
    }
    return _repo.addTradeType(
      projectId: projectId,
      category: category,
      type: type,
      name: name,
      unit: m['unit'] as String? ?? '',
    );
  }
}
