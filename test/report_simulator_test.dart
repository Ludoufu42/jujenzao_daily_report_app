import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jujenzao_daily_report_app/db/database_helper.dart';
import 'package:jujenzao_daily_report_app/db/report_repository.dart';
import 'package:jujenzao_daily_report_app/models/project.dart';
import 'package:jujenzao_daily_report_app/models/project_bundle.dart';
import 'package:jujenzao_daily_report_app/services/app_clock.dart';
import 'package:jujenzao_daily_report_app/services/cloud_report_sync.dart';
import 'package:jujenzao_daily_report_app/services/cloud_service.dart';
import 'package:jujenzao_daily_report_app/services/report_simulator.dart';
import 'package:jujenzao_daily_report_app/services/simulation_plan.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

ProjectBundle _bundle() => ProjectBundle.fromJson({
  'schema': 'project-bundle/1',
  'ver': 2,
  'pushed_at': 'x',
  'project': {
    'project_id': 2,
    'short': '測試',
    'name': '測試',
    'planned_start': '2026-11-02',
  },
  'items': [
    for (var i = 1; i <= 12; i++)
      {
        'seq': i,
        'code': 'T${100 + i}',
        'name': i % 4 == 0 ? '樓層灌漿 $i' : '工項 $i',
        'grp': '階段',
        'path': '主要徑',
      },
  ],
});

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late ReportRepository repo;
  late Project project;
  final cloud = CloudService.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    cloud.tokenProvider = () async => 'tok';
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await DatabaseHelper.createSchema(db);
    repo = SqliteReportRepository.withDatabase(db);
    project = await repo.createProject(
      Project(
        name: '測試',
        companyName: 'x',
        startDate: DateTime(2026, 11, 2),
        plannedCompletionDate: DateTime(2027, 5, 10),
        platformProjectId: 2,
      ),
    );
  });

  tearDown(() async {
    AppClock.simulate(null);
    await db.close();
  });

  test('一鍵跑完整個專案:每天都存本機、上傳雲端(送出兩次),雲端內容對得上', () async {
    // 假的雲端:記每一天最新的日報與修訂號。
    final store = <String, Map<String, dynamic>>{};
    var puts = 0;
    cloud.client = MockClient((req) async {
      final m = RegExp(
        r'/reports/(\d{4}-\d{2}-\d{2})$',
      ).firstMatch(req.url.path);
      if (m == null) return http.Response('nf', 404);
      final date = m.group(1)!;
      if (req.method == 'PUT') {
        puts++;
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        final rev = ((store[date]?['rev'] as num?)?.toInt() ?? 0) + 1;
        store[date] = {...body, 'rev': rev};
        return http.Response(jsonEncode({'ok': true, 'rev': rev}), 200);
      }
      final j = store[date];
      return j == null
          ? http.Response('nf', 404)
          : http.Response.bytes(utf8.encode(jsonEncode(j)), 200);
    });

    final bundle = _bundle();
    final plan = SimulationPlan.generate(
      sequence: bundle.sequence,
      start: bundle.plannedStart!,
    );
    final sim = ReportSimulator(project: project, bundle: bundle, repo: repo);
    await sim.run(
      const SimulationOptions(twoSubmits: true, withPdf: false, forgetRate: 0),
    );
    final s = sim.state;

    expect(s.finished, isTrue);
    expect(s.errors, 0, reason: s.log.join('\n'));
    expect(s.done, plan.length);
    expect(s.jsonFailed, 0);
    expect(s.jsonOk, plan.length * 2); // 每天兩次
    expect(puts, plan.length * 2);
    expect(store.length, plan.length);
    expect(store.values.every((j) => j['rev'] == 2), isTrue);

    // 本機:每天一份、要徑只往前
    final local = await repo.getReports(project.id!)
      ..sort((a, b) => a.reportDate.compareTo(b.reportDate));
    expect(local, hasLength(plan.length));
    final codes = bundle.sequence.items.map((i) => i.code).toList();
    for (var i = 0; i < local.length; i++) {
      expect(local[i].todayWorkCode, plan[i].today.code);
      expect(local[i].todayWorkVer, 2);
      if (i > 0) {
        expect(
          codes.indexOf(local[i].todayWorkCode!),
          greaterThanOrEqualTo(codes.indexOf(local[i - 1].todayWorkCode!)),
        );
      }
    }
    expect(local.last.todayWorkCode, codes.last);

    // 雲端的日報內容與計畫一致
    for (final d in plan) {
      final j = store[CloudReportSync.dateKey(d.date)]!;
      expect((j['today_work'] as Map)['code'], d.today.code);
      expect((j['tomorrow_work'] as Map)['code'], d.tomorrow.code);
      expect(j['project_id'], 2);
      expect(j['bundle_ver'], 2);
    }

    // 累計:出工累計只會增加(跨天累積正確)
    final labors = <String, double>{};
    for (final r in local) {
      for (final e in await repo.getLaborEntries(r.id!)) {
        final key = '${e.tradeTypeId}';
        expect(e.cumulative, greaterThanOrEqualTo(labors[key] ?? 0));
        labors[key] = e.cumulative;
      }
    }

    expect(s.summary, contains('全部正確'));
    // 模擬時鐘停在最後一天
    expect(AppClock.simulatedDate, plan.last.date);
  });

  test('只跑前幾天、可以停止;重跑同一段不會多出日報(覆蓋同一天)', () async {
    var puts = 0;
    cloud.client = MockClient((req) async {
      if (req.method == 'PUT') {
        puts++;
        return http.Response(jsonEncode({'ok': true, 'rev': 1}), 200);
      }
      return http.Response('nf', 404);
    });
    final sim = ReportSimulator(
      project: project,
      bundle: _bundle(),
      repo: repo,
    );
    await sim.run(
      const SimulationOptions(
        twoSubmits: false,
        withPdf: false,
        maxDays: 5,
        forgetRate: 0,
      ),
    );
    expect(sim.state.done, 5);
    expect(puts, 5);
    expect((await repo.getReports(project.id!)), hasLength(5));

    await sim.run(
      const SimulationOptions(
        twoSubmits: false,
        withPdf: false,
        maxDays: 5,
        forgetRate: 0,
      ),
    );
    expect((await repo.getReports(project.id!)), hasLength(5));
  });

  test('雲端一直失敗:中止、不丟例外、錯誤有記下', () async {
    cloud.client = MockClient((req) async => http.Response('boom', 500));
    final sim = ReportSimulator(
      project: project,
      bundle: _bundle(),
      repo: repo,
    );
    await sim.run(
      const SimulationOptions(
        twoSubmits: false,
        withPdf: false,
        maxDays: 10,
        forgetRate: 0,
      ),
    );
    // 上傳失敗只記成「上傳失敗」,本機照存;不會把整個模擬打斷。
    expect(sim.state.finished, isTrue);
    expect(sim.state.jsonFailed, 10);
    expect((await repo.getReports(project.id!)), hasLength(10));
  });

  test('員工偶爾忘記填:那天沒有日報、工期照跑;有補登的標成補登,要徑與累計仍然正確', () async {
    final store = <String, Map<String, dynamic>>{};
    cloud.client = MockClient((req) async {
      final m = RegExp(
        r'/reports/(\d{4}-\d{2}-\d{2})$',
      ).firstMatch(req.url.path);
      if (m == null) return http.Response('nf', 404);
      final date = m.group(1)!;
      if (req.method == 'PUT') {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        final rev = ((store[date]?['rev'] as num?)?.toInt() ?? 0) + 1;
        store[date] = {...body, 'rev': rev};
        return http.Response(jsonEncode({'ok': true, 'rev': rev}), 200);
      }
      final j = store[date];
      return j == null
          ? http.Response('nf', 404)
          : http.Response.bytes(utf8.encode(jsonEncode(j)), 200);
    });

    final bundle = _bundle();
    const rate = 0.2;
    final plan = SimulationPlan.generate(
      sequence: bundle.sequence,
      start: bundle.plannedStart!,
      forgetRate: rate,
    );
    final forgot = plan.where((d) => d.forgot).toList();
    final backfilled = forgot.where((d) => d.backfillAfter > 0).toList();
    expect(forgot, isNotEmpty);
    expect(backfilled, isNotEmpty);
    expect(forgot.length, greaterThan(backfilled.length)); // 也有一直沒補的

    final sim = ReportSimulator(project: project, bundle: bundle, repo: repo);
    await sim.run(
      const SimulationOptions(
        twoSubmits: true,
        withPdf: false,
        forgetRate: rate,
      ),
    );
    final s = sim.state;
    expect(s.errors, 0, reason: s.log.join('\n'));
    expect(s.forgot, forgot.length);
    expect(s.backfilled, backfilled.length);

    // 本機日報 = 計畫天數 - 一直沒補的天數
    final neverFilled = forgot.where((d) => d.backfillAfter == 0).length;
    final local = await repo.getReports(project.id!)
      ..sort((a, b) => a.reportDate.compareTo(b.reportDate));
    expect(local.length, plan.length - neverFilled);
    // 補登的日報標成補登,數量與模擬一致
    expect(await repo.countBackfilledReports(project.id!), backfilled.length);
    // 完全沒補的那幾天,本機與雲端都沒有日報
    for (final d in forgot.where((d) => d.backfillAfter == 0)) {
      final key = CloudReportSync.dateKey(d.date);
      expect(store.containsKey(key), isFalse);
      expect(await repo.getReportByDate(project.id!, d.date), isNull);
    }
    // 補登的日報送一次(rev 1),正常日是兩次(rev 2)
    for (final d in backfilled) {
      expect(store[CloudReportSync.dateKey(d.date)]!['rev'], 1);
    }
    expect(
      plan
          .where((d) => !d.forgot)
          .every((d) => store[CloudReportSync.dateKey(d.date)]!['rev'] == 2),
      isTrue,
    );

    // 要徑只往前(依順序),即使中間有漏填的日子
    final codes = bundle.sequence.items.map((i) => i.code).toList();
    for (var i = 1; i < local.length; i++) {
      expect(
        codes.indexOf(local[i].todayWorkCode!),
        greaterThanOrEqualTo(codes.indexOf(local[i - 1].todayWorkCode!)),
      );
    }
    // 補登插進中間後,出工累計仍然只增不減(補登會重算後面每一天的累計)
    final cum = <int, double>{};
    for (final r in local) {
      for (final e in await repo.getLaborEntries(r.id!)) {
        expect(e.cumulative, greaterThanOrEqualTo(cum[e.tradeTypeId] ?? 0));
        cum[e.tradeTypeId] = e.cumulative;
      }
    }
    expect(s.summary, contains('工期照跑'));
    expect(s.summary, contains('不明原因缺 0 天'));
    expect(s.summary, contains('一致'));
  });
}
