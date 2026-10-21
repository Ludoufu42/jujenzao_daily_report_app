import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jujenzao_daily_report_app/db/database_helper.dart';
import 'package:jujenzao_daily_report_app/db/report_repository.dart';
import 'package:jujenzao_daily_report_app/models/daily_report.dart';
import 'package:jujenzao_daily_report_app/models/project.dart';
import 'package:jujenzao_daily_report_app/models/weather.dart';
import 'package:jujenzao_daily_report_app/services/cloud_report_sync.dart';
import 'package:jujenzao_daily_report_app/services/cloud_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Map<String, Object?> _cloudReport({
  int rev = 2,
  String progress = '下班前補填',
  String laborName = '臨時工',
  double morning = 3,
}) => {
  'schema': 'daily-report/2',
  'project_id': 2,
  'report_date': '2026-10-21',
  'rev': rev,
  'filled_by': {'email': 'a@gmail.com', 'name': '王小明'},
  'submitted_at': '2026-10-21 17:40',
  'is_backfill': false,
  'weather_am': 'sunny',
  'weather_pm': 'rainy',
  'is_rain_or_holiday': true,
  'today_work': {'code': 'T102', 'ver': 3},
  'tomorrow_work': {'code': 'T103', 'ver': 3},
  'today_progress': progress,
  'tomorrow_progress': '明天',
  'notes': '備註',
  'labor': [
    {
      'category': '假設工程',
      'name': laborName,
      'morning': morning,
      'afternoon': 1.0,
      'is_subcontracted': true,
      'vendor': '某某工程行',
      'today_content': '今',
      'tomorrow_content': '明',
    },
  ],
  'materials': [],
  'equipment': [],
};

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late ReportRepository repo;
  late Project project;
  final cloud = CloudService.instance;
  final date = DateTime(2026, 10, 21);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    cloud.tokenProvider = () async => 'tok';
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await DatabaseHelper.createSchema(db);
    repo = SqliteReportRepository.withDatabase(db);
    project = await repo.createProject(
      Project(
        name: 'Test',
        companyName: 'Test',
        startDate: DateTime(2026, 10, 1),
        plannedCompletionDate: DateTime(2027, 10, 1),
        platformProjectId: 2,
      ),
    );
  });

  tearDown(() async => db.close());

  CloudReportSync sync() => CloudReportSync(cloud: cloud, repo: repo);

  void serve(Map<String, Object?>? Function() body) {
    cloud.client = MockClient((req) async {
      expect(req.url.path, '/app/projects/2/reports/2026-10-21');
      final b = body();
      return b == null
          ? http.Response('nf', 404)
          : http.Response.bytes(utf8.encode(jsonEncode(b)), 200);
    });
  }

  test('雲端沒有當天日報:什麼都不做', () async {
    serve(() => null);
    final r = await sync().pullIfNewer(project, date);
    expect(r.imported, isFalse);
    expect(r.error, isNull);
    expect(await repo.getReportByDate(project.id!, date), isNull);
  });

  test('本機沒有、雲端有:載進本機,內容與工種對得上,並記下修訂號', () async {
    serve(() => _cloudReport());
    final r = await sync().pullIfNewer(project, date);
    expect(r.imported, isTrue);
    expect(r.note, contains('王小明'));
    expect(r.note, contains('第 2 次'));

    final report = (await repo.getReportByDate(project.id!, date))!;
    expect(report.weatherPm, Weather.rainy);
    expect(report.todayWorkCode, 'T102');
    expect(report.todayWorkVer, 3);
    expect(report.tomorrowWorkCode, 'T103');
    expect(report.todayProgressText, '下班前補填');
    final labor = await repo.getLaborEntries(report.id!);
    expect(labor, hasLength(1));
    expect(labor.single.morningCount, 3);
    expect(labor.single.isSubcontracted, isTrue);
    expect(labor.single.vendor, '某某工程行');
    expect(await sync().localRev(2, '2026-10-21'), 2);
  });

  test('已載入過同一個修訂號:不重複載入,保留本機後來的修改', () async {
    serve(() => _cloudReport());
    await sync().pullIfNewer(project, date);
    final first = (await repo.getReportByDate(project.id!, date))!;
    // 本機自己又改了(還沒上傳)
    await repo.updateDailyReportWithEntries(
      report: first.copyWith(),
      laborInputs: const [],
      materialInputs: const [],
      equipmentInputs: const [],
      photoPaths: const [],
    );
    final again = await sync().pullIfNewer(project, date);
    expect(again.imported, isFalse);
  });

  test('雲端有更新的修訂:覆蓋本機同一天,不會多出第二份', () async {
    serve(() => _cloudReport(rev: 1, progress: '中午', morning: 2));
    await sync().pullIfNewer(project, date);
    serve(() => _cloudReport(rev: 2, progress: '下班前', morning: 5));
    final r = await sync().pullIfNewer(project, date);
    expect(r.imported, isTrue);

    final reports = await repo.getReports(project.id!);
    expect(reports, hasLength(1));
    expect(reports.single.todayProgressText, '下班前');
    final labor = await repo.getLaborEntries(reports.single.id!);
    expect(labor.single.morningCount, 5);
  });

  test('別支手機自己新增的工種:本機沒有就補建', () async {
    serve(() => _cloudReport(laborName: '特殊工種X'));
    await sync().pullIfNewer(project, date);
    final all = await repo.getTradeTypes(
      project.id!,
      '假設工程',
      includeDisabledAndDeleted: true,
    );
    expect(all.map((t) => t.name), contains('特殊工種X'));
  });

  test('連不上雲端:回報錯誤但不丟例外,本機不動', () async {
    cloud.client = MockClient((req) async => throw http.ClientException('offline'));
    final r = await sync().pullIfNewer(project, date);
    expect(r.imported, isFalse);
    expect(r.error, isNotNull);
  });

  test('沒有工程管理編號的專案:略過', () async {
    cloud.client = MockClient((req) async => fail('不該連線'));
    final local = await repo.createProject(
      Project(
        name: 'Local',
        companyName: 'x',
        startDate: DateTime(2026, 10, 1),
        plannedCompletionDate: DateTime(2026, 10, 2),
      ),
    );
    final r = await sync().pullIfNewer(local, date);
    expect(r.imported, isFalse);
  });

  group('previousReport(今日要徑的下限)', () {
    Future<void> localReport(DateTime d, String code) =>
        repo.createDailyReportWithEntries(
          report: DailyReport(
            projectId: project.id!,
            reportDate: d,
            weatherAm: Weather.sunny,
            weatherPm: Weather.sunny,
            todayWorkCode: code,
            createdAt: DateTime.now(),
          ),
          laborInputs: const [],
          materialInputs: const [],
          equipmentInputs: const [],
          photoPaths: const [],
        );

    void serveBefore(Map<String, Object?>? json) {
      cloud.client = MockClient((req) async {
        expect(req.url.path, '/app/projects/2/reports');
        expect(req.url.queryParameters['before'], '2026-10-22');
        return json == null
            ? http.Response('nf', 404)
            : http.Response.bytes(utf8.encode(jsonEncode(json)), 200);
      });
    }

    final today = DateTime(2026, 10, 22);

    test('本機沒有、雲端有(別支手機填的):用雲端的,標示來自雲端', () async {
      serveBefore({
        'report_date': '2026-10-21',
        'today_work': {'code': 'T201', 'ver': 3},
        'tomorrow_work': {'code': 'T202', 'ver': 3},
      });
      final r = (await sync().previousReport(project, today))!;
      expect(r.todayWorkCode, 'T201');
      expect(r.fromCloud, isTrue);
    });

    test('雲端比較新:用雲端;同一天:用本機(有查驗紀錄)', () async {
      await localReport(DateTime(2026, 10, 20), 'T102');
      serveBefore({
        'report_date': '2026-10-21',
        'today_work': {'code': 'T201'},
        'tomorrow_work': {},
      });
      expect((await sync().previousReport(project, today))!.todayWorkCode, 'T201');

      await localReport(DateTime(2026, 10, 21), 'T202');
      final same = (await sync().previousReport(project, today))!;
      expect(same.todayWorkCode, 'T202');
      expect(same.fromCloud, isFalse);
    });

    test('連不上雲端:只用本機的;都沒有就是 null(第一份日報)', () async {
      cloud.client = MockClient((req) async => throw http.ClientException('offline'));
      expect(await sync().previousReport(project, today), isNull);
      await localReport(DateTime(2026, 10, 21), 'T201');
      expect((await sync().previousReport(project, today))!.todayWorkCode, 'T201');
    });
  });
}
