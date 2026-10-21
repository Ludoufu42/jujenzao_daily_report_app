import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:jujenzao_daily_report_app/db/database_helper.dart';
import 'package:jujenzao_daily_report_app/db/report_repository.dart';
import 'package:jujenzao_daily_report_app/models/daily_report.dart';
import 'package:jujenzao_daily_report_app/models/inspection.dart';
import 'package:jujenzao_daily_report_app/models/project.dart';
import 'package:jujenzao_daily_report_app/models/trade_category.dart';
import 'package:jujenzao_daily_report_app/models/trade_type.dart';
import 'package:jujenzao_daily_report_app/models/weather.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late ReportRepository repo;
  late Project project;

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await DatabaseHelper.createSchema(db);
    repo = SqliteReportRepository.withDatabase(db);
    project = await repo.createProject(Project(
      name: 'Test',
      companyName: 'Test',
      startDate: DateTime(2026, 7, 9),
      plannedCompletionDate: DateTime(2028, 2, 26),
    ));
  });

  tearDown(() async => db.close());

  test('project creation seeds all 7 category preset trade types', () async {
    final assumption = await repo.getTradeTypes(project.id!, '假設工程');
    expect(assumption.map((t) => t.name), containsAll(['臨時工', '施工架', '安全圍籬', '點井工程', '吊料工程']));

    final materials = await repo.getTradeTypes(project.id!, '營建材料');
    expect(materials, isNotEmpty);
    expect(materials.every((t) => t.type == TradeCategoryType.material), isTrue);

    final equipment = await repo.getTradeTypes(project.id!, '機具設備');
    expect(equipment.every((t) => t.type == TradeCategoryType.equipment), isTrue);
  });

  test('labor today_total is the AM/PM average, not the sum', () async {
    final tradeTypes = await repo.getTradeTypes(project.id!, '假設工程');
    final tempWorker = tradeTypes.firstWhere((t) => t.name == '臨時工');

    await repo.createDailyReportWithEntries(
      report: DailyReport(
        projectId: project.id!,
        reportDate: DateTime(2026, 7, 11),
        weatherAm: Weather.sunny,
        weatherPm: Weather.sunny,
        createdAt: DateTime.now(),
      ),
      laborInputs: [
        LaborEntryInput(
          tradeTypeId: tempWorker.id!,
          morningCount: 1,
          afternoonCount: 0,
        ),
      ],
      materialInputs: const [],
      equipmentInputs: const [],
      photoPaths: const [],
    );

    final reports = await repo.getReports(project.id!);
    final entries = await repo.getLaborEntries(reports.single.id!);
    expect(entries.single.todayTotal, 0.5);
    expect(entries.single.cumulative, 0.5);
  });

  test('cumulative carries forward across a gap where the item was skipped',
      () async {
    final tradeTypes = await repo.getTradeTypes(project.id!, '假設工程');
    final tempWorker = tradeTypes.firstWhere((t) => t.name == '臨時工');

    // Day 1: 2 + 2 -> today_total 2, cumulative 2
    await repo.createDailyReportWithEntries(
      report: DailyReport(
        projectId: project.id!,
        reportDate: DateTime(2026, 7, 11),
        weatherAm: Weather.sunny,
        weatherPm: Weather.sunny,
        createdAt: DateTime.now(),
      ),
      laborInputs: [
        LaborEntryInput(
            tradeTypeId: tempWorker.id!, morningCount: 2, afternoonCount: 2),
      ],
      materialInputs: const [],
      equipmentInputs: const [],
      photoPaths: const [],
    );

    // Day 2: 臨時工 not entered at all (left blank) -> should be omitted entirely
    await repo.createDailyReportWithEntries(
      report: DailyReport(
        projectId: project.id!,
        reportDate: DateTime(2026, 7, 12),
        weatherAm: Weather.cloudy,
        weatherPm: Weather.cloudy,
        createdAt: DateTime.now(),
      ),
      laborInputs: [
        LaborEntryInput(
            tradeTypeId: tempWorker.id!, morningCount: 0, afternoonCount: 0),
      ],
      materialInputs: const [],
      equipmentInputs: const [],
      photoPaths: const [],
    );

    // Day 3: 臨時工 3 + 3 -> today_total 3, cumulative should be 2 (day1) + 3 = 5,
    // *not* reset to 0 just because day 2 had no entry.
    await repo.createDailyReportWithEntries(
      report: DailyReport(
        projectId: project.id!,
        reportDate: DateTime(2026, 7, 13),
        weatherAm: Weather.sunny,
        weatherPm: Weather.sunny,
        createdAt: DateTime.now(),
      ),
      laborInputs: [
        LaborEntryInput(
            tradeTypeId: tempWorker.id!, morningCount: 3, afternoonCount: 3),
      ],
      materialInputs: const [],
      equipmentInputs: const [],
      photoPaths: const [],
    );

    final reports = await repo.getReports(project.id!);
    final day2 = reports.firstWhere((r) => r.reportDate == DateTime(2026, 7, 12));
    final day2Entries = await repo.getLaborEntries(day2.id!);
    expect(day2Entries, isEmpty,
        reason: 'items left blank must not appear in the report at all');

    final day3 = reports.firstWhere((r) => r.reportDate == DateTime(2026, 7, 13));
    final day3Entries = await repo.getLaborEntries(day3.id!);
    expect(day3Entries.single.cumulative, 5);
  });

  test('material entries use raw quantity (no AM/PM split) and their own cumulative',
      () async {
    final materials = await repo.getTradeTypes(project.id!, '營建材料');
    final steel = materials.firstWhere((t) => t.name == '280鋼筋');

    await repo.createDailyReportWithEntries(
      report: DailyReport(
        projectId: project.id!,
        reportDate: DateTime(2026, 7, 11),
        weatherAm: Weather.sunny,
        weatherPm: Weather.sunny,
        createdAt: DateTime.now(),
      ),
      laborInputs: const [],
      materialInputs: [
        MaterialEntryInput(tradeTypeId: steel.id!, quantity: 10, usageLocation: '3F'),
      ],
      equipmentInputs: const [],
      photoPaths: const [],
    );

    await repo.createDailyReportWithEntries(
      report: DailyReport(
        projectId: project.id!,
        reportDate: DateTime(2026, 7, 12),
        weatherAm: Weather.sunny,
        weatherPm: Weather.sunny,
        createdAt: DateTime.now(),
      ),
      laborInputs: const [],
      materialInputs: [
        MaterialEntryInput(tradeTypeId: steel.id!, quantity: 5, usageLocation: '4F'),
      ],
      equipmentInputs: const [],
      photoPaths: const [],
    );

    final reports = await repo.getReports(project.id!);
    final day2 = reports.firstWhere((r) => r.reportDate == DateTime(2026, 7, 12));
    final entries = await repo.getMaterialEntries(day2.id!);
    expect(entries.single.quantity, 5);
    expect(entries.single.cumulative, 15);
  });

  test('force-deleting a trade type removes it and all its historical entries',
      () async {
    final tradeTypes = await repo.getTradeTypes(project.id!, '假設工程');
    final tempWorker = tradeTypes.firstWhere((t) => t.name == '臨時工');

    await repo.createDailyReportWithEntries(
      report: DailyReport(
        projectId: project.id!,
        reportDate: DateTime(2026, 7, 11),
        weatherAm: Weather.sunny,
        weatherPm: Weather.sunny,
        createdAt: DateTime.now(),
      ),
      laborInputs: [
        LaborEntryInput(
            tradeTypeId: tempWorker.id!, morningCount: 2, afternoonCount: 2),
      ],
      materialInputs: const [],
      equipmentInputs: const [],
      photoPaths: const [],
    );

    await repo.forceDeleteTradeType(tempWorker.id!);

    final remaining = await repo.getTradeTypes(project.id!, '假設工程');
    expect(remaining.any((t) => t.id == tempWorker.id), isFalse);

    final reports = await repo.getReports(project.id!);
    final entries = await repo.getLaborEntries(reports.single.id!);
    expect(entries, isEmpty,
        reason: 'force delete must purge historical entries too');
  });

  test('regular delete keeps historical entries but hides item from active list',
      () async {
    final tradeTypes = await repo.getTradeTypes(project.id!, '假設工程');
    final tempWorker = tradeTypes.firstWhere((t) => t.name == '臨時工');

    await repo.createDailyReportWithEntries(
      report: DailyReport(
        projectId: project.id!,
        reportDate: DateTime(2026, 7, 11),
        weatherAm: Weather.sunny,
        weatherPm: Weather.sunny,
        createdAt: DateTime.now(),
      ),
      laborInputs: [
        LaborEntryInput(
            tradeTypeId: tempWorker.id!, morningCount: 2, afternoonCount: 2),
      ],
      materialInputs: const [],
      equipmentInputs: const [],
      photoPaths: const [],
    );

    await repo.setTradeTypeStatus(tempWorker.id!, TradeStatus.deleted);

    final active = await repo.getTradeTypes(project.id!, '假設工程');
    expect(active.any((t) => t.id == tempWorker.id), isFalse);

    final reports = await repo.getReports(project.id!);
    final entries = await repo.getLaborEntries(reports.single.id!);
    expect(entries, isNotEmpty,
        reason: 'soft delete must preserve historical entries');
  });

  group('工作天 (working days) calculation', () {
    test('excludes weekends when the project opts in', () async {
      // 2026-07-09 is a Thursday; 2026-07-13 is the following Monday.
      final p = await repo.createProject(Project(
        name: 'Weekend test',
        companyName: 'Test',
        startDate: DateTime(2026, 7, 9),
        plannedCompletionDate: DateTime(2026, 12, 31),
        tracksWorkingDays: true,
        excludeWeekends: true,
      ));

      final workingDays = await repo.countWorkingDays(
        project: p,
        uptoDate: DateTime(2026, 7, 13),
      );

      // Thu, Fri, Sat, Sun, Mon = 5 calendar days, minus the Sat/Sun pair.
      expect(workingDays, 3);
    });

    test('excludes official national holidays when the project opts in',
        () async {
      final p = await repo.createProject(Project(
        name: 'Holiday test',
        companyName: 'Test',
        startDate: DateTime(2026, 1, 1),
        plannedCompletionDate: DateTime(2026, 12, 31),
        tracksWorkingDays: true,
        excludeNationalHolidays: true,
      ));

      // 2026-01-01 through 01-04 are all part of the official 元旦 holiday
      // block in the seeded calendar.
      final workingDays = await repo.countWorkingDays(
        project: p,
        uptoDate: DateTime(2026, 1, 4),
      );

      expect(workingDays, 0);
    });

    test(
        'bad-weather exclusion only removes days with an actual rainy report, '
        'not unreported gaps', () async {
      final p = await repo.createProject(Project(
        name: 'Weather test',
        companyName: 'Test',
        startDate: DateTime(2026, 7, 9),
        plannedCompletionDate: DateTime(2026, 12, 31),
        tracksWorkingDays: true,
        excludeBadWeather: true,
      ));

      // Day 1 (7/9): rainy report filed -> excluded.
      await repo.createDailyReportWithEntries(
        report: DailyReport(
          projectId: p.id!,
          reportDate: DateTime(2026, 7, 9),
          weatherAm: Weather.rainy,
          weatherPm: Weather.rainy,
          createdAt: DateTime.now(),
        ),
        laborInputs: const [],
        materialInputs: const [],
        equipmentInputs: const [],
        photoPaths: const [],
      );
      // Day 2 (7/10): no report filed at all -> must NOT be assumed rainy.

      final workingDays = await repo.countWorkingDays(
        project: p,
        uptoDate: DateTime(2026, 7, 10),
      );

      // 2 calendar days minus only the one with a filed rainy report.
      expect(workingDays, 1);
    });
  });

  group('補登 (backfill) and editing existing reports', () {
    test('getReportByDate finds an existing report and null when there is none',
        () async {
      expect(
        await repo.getReportByDate(project.id!, DateTime(2026, 7, 11)),
        isNull,
      );

      await repo.createDailyReportWithEntries(
        report: DailyReport(
          projectId: project.id!,
          reportDate: DateTime(2026, 7, 11),
          weatherAm: Weather.sunny,
          weatherPm: Weather.sunny,
          createdAt: DateTime.now(),
        ),
        laborInputs: const [],
        materialInputs: const [],
        equipmentInputs: const [],
        photoPaths: const [],
      );

      final found = await repo.getReportByDate(
        project.id!,
        DateTime(2026, 7, 11),
      );
      expect(found, isNotNull);
      expect(found!.reportDate.day, 11);
    });

    test('countBackfilledReports only counts reports flagged as backfilled',
        () async {
      await repo.createDailyReportWithEntries(
        report: DailyReport(
          projectId: project.id!,
          reportDate: DateTime(2026, 7, 10),
          weatherAm: Weather.sunny,
          weatherPm: Weather.sunny,
          isBackfilled: true,
          createdAt: DateTime.now(),
        ),
        laborInputs: const [],
        materialInputs: const [],
        equipmentInputs: const [],
        photoPaths: const [],
      );
      await repo.createDailyReportWithEntries(
        report: DailyReport(
          projectId: project.id!,
          reportDate: DateTime(2026, 7, 11),
          weatherAm: Weather.sunny,
          weatherPm: Weather.sunny,
          createdAt: DateTime.now(),
        ),
        laborInputs: const [],
        materialInputs: const [],
        equipmentInputs: const [],
        photoPaths: const [],
      );

      expect(await repo.countBackfilledReports(project.id!), 1);
    });

    test(
        'editing an earlier report cascades cumulative recalculation to every '
        'later report', () async {
      final tradeTypes = await repo.getTradeTypes(project.id!, '假設工程');
      final tempWorker = tradeTypes.firstWhere((t) => t.name == '臨時工');

      Future<int> save(DateTime date, double count) => repo
          .createDailyReportWithEntries(
            report: DailyReport(
              projectId: project.id!,
              reportDate: date,
              weatherAm: Weather.sunny,
              weatherPm: Weather.sunny,
              createdAt: DateTime.now(),
            ),
            laborInputs: [
              LaborEntryInput(
                tradeTypeId: tempWorker.id!,
                morningCount: count,
                afternoonCount: count,
              ),
            ],
            materialInputs: const [],
            equipmentInputs: const [],
            photoPaths: const [],
          );

      final day1Id = await save(DateTime(2026, 7, 9), 2); // cumulative 2
      await save(DateTime(2026, 7, 10), 3); // cumulative 2+3=5
      await save(DateTime(2026, 7, 11), 1); // cumulative 5+1=6

      // Now edit day 1 from 2 workers to 4 workers.
      final day1 = await repo.getReportByDate(
        project.id!,
        DateTime(2026, 7, 9),
      );
      await repo.updateDailyReportWithEntries(
        report: day1!.copyWith(id: day1Id),
        laborInputs: [
          LaborEntryInput(
            tradeTypeId: tempWorker.id!,
            morningCount: 4,
            afternoonCount: 4,
          ),
        ],
        materialInputs: const [],
        equipmentInputs: const [],
        photoPaths: const [],
      );

      final day1Entries = await repo.getLaborEntries(day1Id);
      expect(day1Entries.single.cumulative, 4);

      final day2 = await repo.getReportByDate(
        project.id!,
        DateTime(2026, 7, 10),
      );
      final day2Entries = await repo.getLaborEntries(day2!.id!);
      expect(day2Entries.single.cumulative, 7,
          reason: '4 (updated day1) + 3 (day2 own total)');

      final day3 = await repo.getReportByDate(
        project.id!,
        DateTime(2026, 7, 11),
      );
      final day3Entries = await repo.getLaborEntries(day3!.id!);
      expect(day3Entries.single.cumulative, 8,
          reason: '7 (updated day2) + 1 (day3 own total)');
    });

    test('editing a report never changes its original isBackfilled flag',
        () async {
      final reportId = await repo.createDailyReportWithEntries(
        report: DailyReport(
          projectId: project.id!,
          reportDate: DateTime(2026, 7, 9),
          weatherAm: Weather.sunny,
          weatherPm: Weather.sunny,
          isBackfilled: true,
          createdAt: DateTime.now(),
        ),
        laborInputs: const [],
        materialInputs: const [],
        equipmentInputs: const [],
        photoPaths: const [],
      );

      final existing = await repo.getReportByDate(
        project.id!,
        DateTime(2026, 7, 9),
      );
      await repo.updateDailyReportWithEntries(
        report: existing!.copyWith(id: reportId),
        laborInputs: const [],
        materialInputs: const [],
        equipmentInputs: const [],
        photoPaths: const [],
      );

      final reports = await repo.getReports(project.id!);
      expect(reports.single.isBackfilled, isTrue);
    });
  });

  group('getMostRecentReportBefore (backs the 要徑 sequential lock rule)', () {
    test('returns null when there is no earlier report (project\'s first)',
        () async {
      final result = await repo.getMostRecentReportBefore(
        project.id!,
        DateTime(2026, 7, 9),
      );
      expect(result, isNull);
    });

    test('returns the closest earlier report, skipping gaps', () async {
      await repo.createDailyReportWithEntries(
        report: DailyReport(
          projectId: project.id!,
          reportDate: DateTime(2026, 7, 9),
          weatherAm: Weather.sunny,
          weatherPm: Weather.sunny,
          tomorrowWorkCode: 'T002',
          createdAt: DateTime.now(),
        ),
        laborInputs: const [],
        materialInputs: const [],
        equipmentInputs: const [],
        photoPaths: const [],
      );
      // Note: no report filed for 7/10 (a gap).
      await repo.createDailyReportWithEntries(
        report: DailyReport(
          projectId: project.id!,
          reportDate: DateTime(2026, 7, 11),
          weatherAm: Weather.sunny,
          weatherPm: Weather.sunny,
          createdAt: DateTime.now(),
        ),
        laborInputs: const [],
        materialInputs: const [],
        equipmentInputs: const [],
        photoPaths: const [],
      );

      final result = await repo.getMostRecentReportBefore(
        project.id!,
        DateTime(2026, 7, 12),
      );
      expect(result!.reportDate, DateTime(2026, 7, 11));

      final resultForGapDay = await repo.getMostRecentReportBefore(
        project.id!,
        DateTime(2026, 7, 10),
      );
      expect(resultForGapDay!.reportDate, DateTime(2026, 7, 9));
      expect(resultForGapDay.tomorrowWorkCode, 'T002');
    });
  });

  group('inspections (要徑查驗)', () {
    test('createInspection persists items and photos together', () async {
      final inspectionId = await repo.createInspection(
        inspection: Inspection(
          projectId: project.id!,
          workCode: 'T101',
          templateName: '放樣工程',
          inspectorSignaturePath: '/tmp/sig.png',
          createdAt: DateTime.now(),
        ),
        items: [
          const InspectionItemRecord(
            inspectionId: 0,
            itemName: '1. 構件尺寸核對',
            description: '核對結構圖之梁柱尺寸。',
            result: InspectionResult.pass,
          ),
          const InspectionItemRecord(
            inspectionId: 0,
            itemName: '2. 開口尺寸核對',
            description: '確認各門窗之MO開口、台度尺寸。',
            result: InspectionResult.defect,
          ),
        ],
        photoPaths: ['/tmp/photo1.jpg', '/tmp/photo2.jpg'],
      );

      final items = await repo.getInspectionItems(inspectionId);
      expect(items, hasLength(2));
      expect(
        items.firstWhere((i) => i.itemName.startsWith('2.')).result,
        InspectionResult.defect,
      );

      final photos = await repo.getInspectionPhotos(inspectionId);
      expect(photos, hasLength(2));

      final inspections = await repo.getInspections(project.id!);
      expect(inspections.single.workCode, 'T101');
    });

    test('getLatestInspectionFor finds the most recent inspection for a step',
        () async {
      await repo.createInspection(
        inspection: Inspection(
          projectId: project.id!,
          workCode: 'T101',
          templateName: '放樣工程',
          createdAt: DateTime(2026, 7, 1),
        ),
        items: const [],
        photoPaths: const [],
      );

      expect(
        await repo.getLatestInspectionFor(project.id!, '地上一樓柱鋼筋組立'),
        isNull,
      );
      expect(
        await repo.getLatestInspectionFor(project.id!, 'T101'),
        isNotNull,
      );
    });

    test('updateInspectionPdfPath sets the generated PDF path', () async {
      final inspectionId = await repo.createInspection(
        inspection: Inspection(
          projectId: project.id!,
          workCode: 'T101',
          templateName: '放樣工程',
          createdAt: DateTime.now(),
        ),
        items: const [],
        photoPaths: const [],
      );

      await repo.updateInspectionPdfPath(inspectionId, '/tmp/report.pdf');

      final inspections = await repo.getInspections(project.id!);
      expect(inspections.single.pdfPath, '/tmp/report.pdf');
    });
  });

  group('upsertCloudProject (專案來自工程管理推播)', () {
    Project cloudProject({String name = '白平衡II館', int above = 2}) => Project(
      name: name,
      companyName: '振愷營造',
      startDate: DateTime(2026, 11, 2),
      plannedCompletionDate: DateTime(2026, 11, 2),
      aboveGroundFloors: above,
      platformProjectId: 42,
    );

    test('第一次建立(含預設工種),再次同步只更新、不重複建立', () async {
      final first = await repo.upsertCloudProject(cloudProject());
      expect(first.id, isNotNull);
      expect(
        (await repo.getTradeTypes(first.id!, '假設工程')).isNotEmpty,
        isTrue,
      );

      final second = await repo.upsertCloudProject(
        cloudProject(name: '白平衡II館(改名)', above: 3),
      );
      expect(second.id, first.id);
      final matches = (await repo.getProjects())
          .where((p) => p.platformProjectId == 42)
          .toList();
      expect(matches, hasLength(1));
      expect(matches.single.name, '白平衡II館(改名)');
      expect(matches.single.aboveGroundFloors, 3);
    });
  });
}
