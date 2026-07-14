import 'package:sqflite/sqflite.dart';

import '../models/daily_report.dart';
import '../models/equipment_entry.dart';
import '../models/holiday_calendar.dart';
import '../models/inspection.dart';
import '../models/labor_entry.dart';
import '../models/material_entry.dart';
import '../models/project.dart';
import '../models/report_photo.dart';
import '../models/trade_category.dart';
import '../models/trade_type.dart';
import 'database_helper.dart';

class LaborEntryInput {
  final int tradeTypeId;
  final double morningCount;
  final double afternoonCount;
  final bool isSubcontracted;
  final String vendor;
  final String todayContent;
  final String tomorrowContent;

  const LaborEntryInput({
    required this.tradeTypeId,
    required this.morningCount,
    required this.afternoonCount,
    this.isSubcontracted = false,
    this.vendor = '',
    this.todayContent = '',
    this.tomorrowContent = '',
  });

  bool get hasValue => morningCount > 0 || afternoonCount > 0;
}

class MaterialEntryInput {
  final int tradeTypeId;
  final double quantity;
  final String usageLocation;

  const MaterialEntryInput({
    required this.tradeTypeId,
    required this.quantity,
    this.usageLocation = '',
  });

  bool get hasValue => quantity > 0;
}

class EquipmentEntryInput {
  final int tradeTypeId;
  final double quantity;
  final bool isSubcontracted;
  final String vendor;
  final String todayContent;
  final String tomorrowContent;

  const EquipmentEntryInput({
    required this.tradeTypeId,
    required this.quantity,
    this.isSubcontracted = false,
    this.vendor = '',
    this.todayContent = '',
    this.tomorrowContent = '',
  });

  bool get hasValue => quantity > 0;
}

class ReportRepository {
  ReportRepository._internal(this._injectedDb);
  static final ReportRepository instance = ReportRepository._internal(null);

  /// Allows tests to point this repository at an in-memory database
  /// instead of the app's real on-device singleton.
  factory ReportRepository.withDatabase(Database db) =>
      ReportRepository._internal(db);

  final Database? _injectedDb;

  Future<Database> get _db async =>
      _injectedDb ?? await DatabaseHelper.instance.database;

  // ---------------- Projects ----------------

  Future<Project> createProject(Project project) async {
    final db = await _db;
    final id = await db.insert('projects', project.toMap());
    final created = project.copyWith(id: id);
    await _seedTradeTypes(db, id);
    return created;
  }

  Future<void> _seedTradeTypes(Database db, int projectId) async {
    final batch = db.batch();
    for (final category in kTradeCategories) {
      var order = 0;
      for (final (name, unit) in category.presetItems) {
        batch.insert(
          'trade_types',
          TradeType(
            projectId: projectId,
            category: category.name,
            type: category.type,
            name: name,
            unit: unit,
            sortOrder: order,
          ).toMap(),
        );
        order++;
      }
    }
    await batch.commit(noResult: true);
  }

  Future<List<Project>> getProjects() async {
    final db = await _db;
    final rows = await db.query('projects', orderBy: 'id DESC');
    return rows.map(Project.fromMap).toList();
  }

  Future<void> deleteProject(int projectId) async {
    final db = await _db;
    await db.delete('projects', where: 'id = ?', whereArgs: [projectId]);
  }

  // ---------------- Trade types ----------------

  Future<List<TradeType>> getTradeTypes(
    int projectId,
    String category, {
    bool includeDisabledAndDeleted = false,
  }) async {
    final db = await _db;
    final where = includeDisabledAndDeleted
        ? 'project_id = ? AND category = ? AND status != ?'
        : 'project_id = ? AND category = ? AND status = ?';
    final args = includeDisabledAndDeleted
        ? [projectId, category, TradeStatus.deleted.name]
        : [projectId, category, TradeStatus.active.name];
    final rows = await db.query(
      'trade_types',
      where: where,
      whereArgs: args,
      orderBy: 'sort_order ASC, id ASC',
    );
    return rows.map(TradeType.fromMap).toList();
  }

  Future<TradeType> addTradeType({
    required int projectId,
    required String category,
    required TradeCategoryType type,
    required String name,
    required String unit,
  }) async {
    final db = await _db;
    final maxOrderRows = await db.rawQuery(
      'SELECT MAX(sort_order) as m FROM trade_types WHERE project_id = ? AND category = ?',
      [projectId, category],
    );
    final maxOrder = (maxOrderRows.first['m'] as int?) ?? -1;
    final tradeType = TradeType(
      projectId: projectId,
      category: category,
      type: type,
      name: name,
      unit: unit,
      sortOrder: maxOrder + 1,
    );
    final id = await db.insert('trade_types', tradeType.toMap());
    return tradeType.copyWith(id: id);
  }

  Future<void> setTradeTypeStatus(int tradeTypeId, TradeStatus status) async {
    final db = await _db;
    await db.update(
      'trade_types',
      {'status': status.name},
      where: 'id = ?',
      whereArgs: [tradeTypeId],
    );
  }

  /// Permanently deletes a trade type AND every historical entry referencing it.
  Future<void> forceDeleteTradeType(int tradeTypeId) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete(
        'labor_entries',
        where: 'trade_type_id = ?',
        whereArgs: [tradeTypeId],
      );
      await txn.delete(
        'material_entries',
        where: 'trade_type_id = ?',
        whereArgs: [tradeTypeId],
      );
      await txn.delete(
        'equipment_entries',
        where: 'trade_type_id = ?',
        whereArgs: [tradeTypeId],
      );
      await txn.delete(
        'trade_types',
        where: 'id = ?',
        whereArgs: [tradeTypeId],
      );
    });
  }

  // ---------------- Cumulative lookups ----------------

  Future<double> _previousCumulative(
    DatabaseExecutor db,
    String entryTable,
    int projectId,
    int tradeTypeId,
    DateTime beforeDate,
  ) async {
    final rows = await db.rawQuery(
      '''
      SELECT e.cumulative as cumulative FROM $entryTable e
      JOIN daily_reports dr ON e.report_id = dr.id
      WHERE dr.project_id = ? AND e.trade_type_id = ? AND dr.report_date < ?
      ORDER BY dr.report_date DESC LIMIT 1
    ''',
      [projectId, tradeTypeId, beforeDate.toIso8601String()],
    );
    if (rows.isEmpty) return 0.0;
    return (rows.first['cumulative'] as num).toDouble();
  }

  /// Public entry point so the preview screen can show what a trade type's
  /// cumulative total *would* become, before the report is actually saved.
  Future<double> previousCumulative(
    String entryTable,
    int projectId,
    int tradeTypeId,
    DateTime beforeDate,
  ) async {
    final db = await _db;
    return _previousCumulative(
      db,
      entryTable,
      projectId,
      tradeTypeId,
      beforeDate,
    );
  }

  /// Counts 工作天 (actual working days) from [project]'s start date through
  /// [uptoDate] inclusive, per whichever exclusion rules the project turned
  /// on at creation time (weekends / national holidays / bad weather).
  ///
  /// Bad-weather exclusion only ever removes a day that has *positive
  /// evidence* of rain (a filed report with rainy/heavyRain/typhoon
  /// weather) — a calendar day with no report at all is not assumed to be
  /// a rained-out day, since there is no record either way. [uptoDateIsBadWeather]
  /// lets the preview screen factor in the *current, not-yet-saved* report's
  /// weather selection for uptoDate itself.
  Future<int> countWorkingDays({
    required Project project,
    required DateTime uptoDate,
    bool uptoDateIsBadWeather = false,
  }) async {
    var rainyDates = <String>{};
    if (project.excludeBadWeather) {
      final db = await _db;
      final rows = await db.query(
        'daily_reports',
        columns: ['report_date', 'weather_am', 'weather_pm'],
        where: 'project_id = ? AND report_date <= ?',
        whereArgs: [project.id, uptoDate.toIso8601String()],
      );
      const rainy = {'rainy', 'heavyRain', 'typhoon'};
      rainyDates = {
        for (final r in rows)
          if (rainy.contains(r['weather_am']) ||
              rainy.contains(r['weather_pm']))
            (r['report_date'] as String).substring(0, 10),
      };
    }

    int workingDays = 0;
    var d = DateTime(
      project.startDate.year,
      project.startDate.month,
      project.startDate.day,
    );
    final end = DateTime(uptoDate.year, uptoDate.month, uptoDate.day);
    while (!d.isAfter(end)) {
      var excluded = false;
      if (project.excludeWeekends &&
          (d.weekday == DateTime.saturday || d.weekday == DateTime.sunday)) {
        excluded = true;
      }
      if (!excluded &&
          project.excludeNationalHolidays &&
          isTaiwanNationalHoliday(d)) {
        excluded = true;
      }
      if (!excluded && project.excludeBadWeather) {
        final isSameDayAsUpto = d.year == end.year &&
            d.month == end.month &&
            d.day == end.day;
        final key =
            '${d.year.toString().padLeft(4, '0')}-'
            '${d.month.toString().padLeft(2, '0')}-'
            '${d.day.toString().padLeft(2, '0')}';
        final isRainy = rainyDates.contains(key) ||
            (isSameDayAsUpto && uptoDateIsBadWeather);
        if (isRainy) excluded = true;
      }
      if (!excluded) workingDays++;
      d = d.add(const Duration(days: 1));
    }
    return workingDays;
  }

  // ---------------- Daily reports ----------------

  /// A project may have at most one report per calendar date. Callers use
  /// this to decide whether a picked date should start a brand-new (possibly
  /// 補登/backfilled) report or load the existing one for editing.
  Future<DailyReport?> getReportByDate(int projectId, DateTime date) async {
    final db = await _db;
    final dayStart = DateTime(date.year, date.month, date.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    final rows = await db.query(
      'daily_reports',
      where: 'project_id = ? AND report_date >= ? AND report_date < ?',
      whereArgs: [
        projectId,
        dayStart.toIso8601String(),
        dayEnd.toIso8601String(),
      ],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return DailyReport.fromMap(rows.first);
  }

  /// Most recent report strictly before [date] — used to lock today's 要徑
  /// choice to whatever the previous report planned as its
  /// tomorrowCriticalPath (rule: only the project's very first report ever
  /// gets a free choice of 要徑).
  Future<DailyReport?> getMostRecentReportBefore(
    int projectId,
    DateTime date,
  ) async {
    final db = await _db;
    final dayStart = DateTime(date.year, date.month, date.day);
    final rows = await db.query(
      'daily_reports',
      where: 'project_id = ? AND report_date < ?',
      whereArgs: [projectId, dayStart.toIso8601String()],
      orderBy: 'report_date DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return DailyReport.fromMap(rows.first);
  }

  /// Count of 補登 (backfilled) reports for a project — surfaced next to the
  /// project on the home screen since it feeds into staff performance review.
  Future<int> countBackfilledReports(int projectId) async {
    final db = await _db;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) as c FROM daily_reports WHERE project_id = ? AND is_backfilled = 1',
      [projectId],
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  Future<int> createDailyReportWithEntries({
    required DailyReport report,
    required List<LaborEntryInput> laborInputs,
    required List<MaterialEntryInput> materialInputs,
    required List<EquipmentEntryInput> equipmentInputs,
    required List<String> photoPaths,
  }) async {
    final db = await _db;
    return db.transaction((txn) async {
      final reportId = await txn.insert('daily_reports', report.toMap());
      await _saveEntries(
        txn: txn,
        reportId: reportId,
        projectId: report.projectId,
        reportDate: report.reportDate,
        laborInputs: laborInputs,
        materialInputs: materialInputs,
        equipmentInputs: equipmentInputs,
        photoPaths: photoPaths,
      );
      return reportId;
    });
  }

  /// Overwrites an existing day's report in place (same row id, and its
  /// original [DailyReport.isBackfilled] flag is left untouched — editing a
  /// day never turns it into, or out of, a 補登 entry). Because earlier
  /// entries' cumulative totals feed forward into every later day, changing
  /// this day's quantities requires recomputing cumulative for every report
  /// after it too.
  Future<void> updateDailyReportWithEntries({
    required DailyReport report,
    required List<LaborEntryInput> laborInputs,
    required List<MaterialEntryInput> materialInputs,
    required List<EquipmentEntryInput> equipmentInputs,
    required List<String> photoPaths,
  }) async {
    final reportId = report.id;
    if (reportId == null) {
      throw ArgumentError('report.id is required to update an existing report');
    }
    final db = await _db;
    await db.transaction((txn) async {
      await txn.update(
        'daily_reports',
        report.toMap()..remove('id'),
        where: 'id = ?',
        whereArgs: [reportId],
      );
      await txn.delete(
        'labor_entries',
        where: 'report_id = ?',
        whereArgs: [reportId],
      );
      await txn.delete(
        'material_entries',
        where: 'report_id = ?',
        whereArgs: [reportId],
      );
      await txn.delete(
        'equipment_entries',
        where: 'report_id = ?',
        whereArgs: [reportId],
      );
      await txn.delete(
        'report_photos',
        where: 'report_id = ?',
        whereArgs: [reportId],
      );

      await _saveEntries(
        txn: txn,
        reportId: reportId,
        projectId: report.projectId,
        reportDate: report.reportDate,
        laborInputs: laborInputs,
        materialInputs: materialInputs,
        equipmentInputs: equipmentInputs,
        photoPaths: photoPaths,
      );

      await _recalculateCumulativeAfter(
        txn: txn,
        projectId: report.projectId,
        afterDate: report.reportDate,
      );
    });
  }

  Future<void> _saveEntries({
    required DatabaseExecutor txn,
    required int reportId,
    required int projectId,
    required DateTime reportDate,
    required List<LaborEntryInput> laborInputs,
    required List<MaterialEntryInput> materialInputs,
    required List<EquipmentEntryInput> equipmentInputs,
    required List<String> photoPaths,
  }) async {
    for (final input in laborInputs.where((e) => e.hasValue)) {
      final prevCumulative = await _previousCumulative(
        txn,
        'labor_entries',
        projectId,
        input.tradeTypeId,
        reportDate,
      );
      final todayTotal = (input.morningCount + input.afternoonCount) / 2;
      final entry = LaborEntry(
        reportId: reportId,
        tradeTypeId: input.tradeTypeId,
        morningCount: input.morningCount,
        afternoonCount: input.afternoonCount,
        todayTotal: todayTotal,
        cumulative: prevCumulative + todayTotal,
        isSubcontracted: input.isSubcontracted,
        vendor: input.vendor,
        todayContent: input.todayContent,
        tomorrowContent: input.tomorrowContent,
      );
      await txn.insert('labor_entries', entry.toMap());
    }

    for (final input in materialInputs.where((e) => e.hasValue)) {
      final prevCumulative = await _previousCumulative(
        txn,
        'material_entries',
        projectId,
        input.tradeTypeId,
        reportDate,
      );
      final entry = MaterialEntry(
        reportId: reportId,
        tradeTypeId: input.tradeTypeId,
        quantity: input.quantity,
        cumulative: prevCumulative + input.quantity,
        usageLocation: input.usageLocation,
      );
      await txn.insert('material_entries', entry.toMap());
    }

    for (final input in equipmentInputs.where((e) => e.hasValue)) {
      final prevCumulative = await _previousCumulative(
        txn,
        'equipment_entries',
        projectId,
        input.tradeTypeId,
        reportDate,
      );
      final entry = EquipmentEntry(
        reportId: reportId,
        tradeTypeId: input.tradeTypeId,
        quantity: input.quantity,
        cumulative: prevCumulative + input.quantity,
        isSubcontracted: input.isSubcontracted,
        vendor: input.vendor,
        todayContent: input.todayContent,
        tomorrowContent: input.tomorrowContent,
      );
      await txn.insert('equipment_entries', entry.toMap());
    }

    for (var i = 0; i < photoPaths.length; i++) {
      await txn.insert(
        'report_photos',
        ReportPhoto(
          reportId: reportId,
          filePath: photoPaths[i],
          sortOrder: i,
        ).toMap(),
      );
    }
  }

  /// Recomputes cumulative for every report strictly after [afterDate] in
  /// date order, since each one's cumulative is only correct if the report
  /// before it is. Walking forward re-derives each cumulative from the
  /// entries table directly (which the previous iteration just updated), so
  /// the chain stays consistent all the way to the most recent report.
  Future<void> _recalculateCumulativeAfter({
    required DatabaseExecutor txn,
    required int projectId,
    required DateTime afterDate,
  }) async {
    final laterReports = await txn.query(
      'daily_reports',
      columns: ['id', 'report_date'],
      where: 'project_id = ? AND report_date > ?',
      whereArgs: [projectId, afterDate.toIso8601String()],
      orderBy: 'report_date ASC',
    );

    for (final reportRow in laterReports) {
      final reportId = reportRow['id'] as int;
      final reportDate = DateTime.parse(reportRow['report_date'] as String);

      for (final table in ['labor_entries', 'equipment_entries']) {
        final entries = await txn.query(
          table,
          where: 'report_id = ?',
          whereArgs: [reportId],
        );
        for (final e in entries) {
          final prevCumulative = await _previousCumulative(
            txn,
            table,
            projectId,
            e['trade_type_id'] as int,
            reportDate,
          );
          final todayValue = table == 'labor_entries'
              ? (e['today_total'] as num).toDouble()
              : (e['quantity'] as num).toDouble();
          await txn.update(
            table,
            {'cumulative': prevCumulative + todayValue},
            where: 'id = ?',
            whereArgs: [e['id']],
          );
        }
      }

      final materialEntries = await txn.query(
        'material_entries',
        where: 'report_id = ?',
        whereArgs: [reportId],
      );
      for (final e in materialEntries) {
        final prevCumulative = await _previousCumulative(
          txn,
          'material_entries',
          projectId,
          e['trade_type_id'] as int,
          reportDate,
        );
        final quantity = (e['quantity'] as num).toDouble();
        await txn.update(
          'material_entries',
          {'cumulative': prevCumulative + quantity},
          where: 'id = ?',
          whereArgs: [e['id']],
        );
      }
    }
  }

  Future<List<DailyReport>> getReports(int projectId) async {
    final db = await _db;
    final rows = await db.query(
      'daily_reports',
      where: 'project_id = ?',
      whereArgs: [projectId],
      orderBy: 'report_date DESC',
    );
    return rows.map(DailyReport.fromMap).toList();
  }

  Future<List<LaborEntry>> getLaborEntries(int reportId) async {
    final db = await _db;
    final rows = await db.query(
      'labor_entries',
      where: 'report_id = ?',
      whereArgs: [reportId],
    );
    return rows.map(LaborEntry.fromMap).toList();
  }

  Future<List<MaterialEntry>> getMaterialEntries(int reportId) async {
    final db = await _db;
    final rows = await db.query(
      'material_entries',
      where: 'report_id = ?',
      whereArgs: [reportId],
    );
    return rows.map(MaterialEntry.fromMap).toList();
  }

  Future<List<EquipmentEntry>> getEquipmentEntries(int reportId) async {
    final db = await _db;
    final rows = await db.query(
      'equipment_entries',
      where: 'report_id = ?',
      whereArgs: [reportId],
    );
    return rows.map(EquipmentEntry.fromMap).toList();
  }

  Future<List<ReportPhoto>> getReportPhotos(int reportId) async {
    final db = await _db;
    final rows = await db.query(
      'report_photos',
      where: 'report_id = ?',
      whereArgs: [reportId],
      orderBy: 'sort_order ASC',
    );
    return rows.map(ReportPhoto.fromMap).toList();
  }

  // ---------------- Inspections (要徑查驗) ----------------

  Future<int> createInspection({
    required Inspection inspection,
    required List<InspectionItemRecord> items,
    required List<String> photoPaths,
  }) async {
    final db = await _db;
    return db.transaction((txn) async {
      final inspectionId = await txn.insert('inspections', inspection.toMap());
      for (final item in items) {
        await txn.insert(
          'inspection_items',
          InspectionItemRecord(
            inspectionId: inspectionId,
            itemName: item.itemName,
            description: item.description,
            result: item.result,
          ).toMap(),
        );
      }
      for (var i = 0; i < photoPaths.length; i++) {
        await txn.insert(
          'inspection_photos',
          InspectionPhotoRecord(
            inspectionId: inspectionId,
            filePath: photoPaths[i],
            sortOrder: i,
          ).toMap(),
        );
      }
      return inspectionId;
    });
  }

  Future<void> updateInspectionPdfPath(int inspectionId, String pdfPath) async {
    final db = await _db;
    await db.update(
      'inspections',
      {'pdf_path': pdfPath},
      where: 'id = ?',
      whereArgs: [inspectionId],
    );
  }

  Future<List<Inspection>> getInspections(int projectId) async {
    final db = await _db;
    final rows = await db.query(
      'inspections',
      where: 'project_id = ?',
      whereArgs: [projectId],
      orderBy: 'created_at DESC',
    );
    return rows.map(Inspection.fromMap).toList();
  }

  /// Most recent inspection for a specific 要徑 step — used to check whether
  /// that step's inspection was already completed before allowing the
  /// project to advance to the next one.
  Future<Inspection?> getLatestInspectionFor(
    int projectId,
    String criticalPathLabel,
  ) async {
    final db = await _db;
    final rows = await db.query(
      'inspections',
      where: 'project_id = ? AND critical_path_label = ?',
      whereArgs: [projectId, criticalPathLabel],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Inspection.fromMap(rows.first);
  }

  Future<List<InspectionItemRecord>> getInspectionItems(
    int inspectionId,
  ) async {
    final db = await _db;
    final rows = await db.query(
      'inspection_items',
      where: 'inspection_id = ?',
      whereArgs: [inspectionId],
    );
    return rows.map(InspectionItemRecord.fromMap).toList();
  }

  Future<List<InspectionPhotoRecord>> getInspectionPhotos(
    int inspectionId,
  ) async {
    final db = await _db;
    final rows = await db.query(
      'inspection_photos',
      where: 'inspection_id = ?',
      whereArgs: [inspectionId],
      orderBy: 'sort_order ASC',
    );
    return rows.map(InspectionPhotoRecord.fromMap).toList();
  }
}
