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
import 'project_file_store.dart';
import 'report_repository.dart';

/// Dropbox-backed implementation of [ReportRepository] — see the
/// "改版為網頁版正式系統" plan for the full design. Each project is one
/// Dropbox folder (`/sanitized-name_id/`), containing:
///   project.json, trade_types.json, reports/YYYY-MM-DD.json,
///   inspections/id.json, photos/*, tasks.json (管理者指派查驗任務).
///
/// Report ids are deterministic (`projectId * 100000000 + yyyymmdd`) so
/// entry lookups (`getLaborEntries(reportId)` etc., which don't take a
/// projectId) can resolve back to the right file without a persisted
/// counter. Trade-type and inspection ids use wall-clock microseconds,
/// matching the timestamp-based ids the app already uses for photo/PDF
/// filenames elsewhere.
class DropboxReportRepository implements ReportRepository {
  DropboxReportRepository({ProjectFileStore? fileStore})
    : _store = fileStore ?? DropboxProjectFileStore();

  final ProjectFileStore _store;

  static const _indexPath = '/index.json';

  // ---------------- Project index / folder naming ----------------

  Future<Map<String, dynamic>> _readIndex() async {
    return await _store.readJson(_indexPath) ??
        {'nextId': 1, 'projects': <dynamic>[]};
  }

  String _sanitize(String s) => s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

  String _folderFor(int projectId, String name) =>
      '/${_sanitize(name)}_$projectId';

  Future<String?> _folderForId(int projectId) async {
    final index = await _readIndex();
    final projects = List<Map<String, dynamic>>.from(
      index['projects'] as List,
    );
    for (final p in projects) {
      if (p['id'] == projectId) return p['folder'] as String;
    }
    return null;
  }

  // ---------------- Projects ----------------

  @override
  Future<Project> createProject(Project project) async {
    final index = await _readIndex();
    final id = index['nextId'] as int;
    final folder = _folderFor(id, project.name);

    final created = project.copyWith(id: id);
    await _store.createFolder(folder);
    await _store.createFolder('$folder/reports');
    await _store.createFolder('$folder/photos');
    await _store.createFolder('$folder/inspections');
    await _store.writeJson('$folder/project.json', created.toMap());
    await _seedTradeTypes(folder, id);

    final projects = List<Map<String, dynamic>>.from(index['projects'] as List)
      ..add({'id': id, 'folder': folder});
    await _store.writeJson(_indexPath, {
      'nextId': id + 1,
      'projects': projects,
    });

    return created;
  }

  Future<void> _seedTradeTypes(String folder, int projectId) async {
    final items = <Map<String, Object?>>[];
    for (final category in kTradeCategories) {
      var order = 0;
      for (final (name, unit) in category.presetItems) {
        items.add(
          TradeType(
            id: _newId(),
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
    await _store.writeJson('$folder/trade_types.json', {'items': items});
  }

  // A tight seeding loop (creating ~70 preset trade types back-to-back) can
  // call this many times within the same microsecond, so a plain
  // `DateTime.now().microsecondsSinceEpoch` isn't reliably unique. A
  // monotonic counter seeded from that timestamp is: still large and
  // timestamp-like, but strictly increasing within this process's lifetime.
  static int _idSeed = DateTime.now().microsecondsSinceEpoch;
  int _newId() => _idSeed++;

  @override
  Future<List<Project>> getProjects() async {
    final index = await _readIndex();
    final entries = List<Map<String, dynamic>>.from(
      index['projects'] as List,
    );
    final projects = <Project>[];
    for (final e in entries) {
      final map = await _store.readJson('${e['folder']}/project.json');
      if (map != null) projects.add(Project.fromMap(map));
    }
    projects.sort((a, b) => (b.id ?? 0).compareTo(a.id ?? 0));
    return projects;
  }

  @override
  Future<void> deleteProject(int projectId) async {
    final index = await _readIndex();
    final projects = List<Map<String, dynamic>>.from(index['projects'] as List)
      ..removeWhere((p) => p['id'] == projectId);
    await _store.writeJson(_indexPath, {
      'nextId': index['nextId'],
      'projects': projects,
    });
    // Note: this only un-lists the project — it deliberately does not
    // delete the underlying Dropbox folder, since that folder may already
    // be shared with the company/admin account as the durable record.
  }

  // ---------------- Trade types ----------------

  Future<Map<String, dynamic>> _readTradeTypesFile(String folder) async {
    return await _store.readJson('$folder/trade_types.json') ??
        {'items': <dynamic>[]};
  }

  @override
  Future<List<TradeType>> getTradeTypes(
    int projectId,
    String category, {
    bool includeDisabledAndDeleted = false,
  }) async {
    final folder = await _folderForId(projectId);
    if (folder == null) return [];
    final file = await _readTradeTypesFile(folder);
    final items = List<Map<String, dynamic>>.from(file['items'] as List)
        .map(TradeType.fromMap)
        .where((t) => t.category == category)
        .where(
          (t) => includeDisabledAndDeleted
              ? t.status != TradeStatus.deleted
              : t.status == TradeStatus.active,
        )
        .toList();
    items.sort((a, b) {
      final order = a.sortOrder.compareTo(b.sortOrder);
      return order != 0 ? order : (a.id ?? 0).compareTo(b.id ?? 0);
    });
    return items;
  }

  @override
  Future<TradeType> addTradeType({
    required int projectId,
    required String category,
    required TradeCategoryType type,
    required String name,
    required String unit,
  }) async {
    final folder = await _folderForId(projectId);
    if (folder == null) {
      throw StateError('找不到專案 $projectId 對應的資料夾');
    }
    final file = await _readTradeTypesFile(folder);
    final items = List<Map<String, dynamic>>.from(file['items'] as List);
    final sameCategory = items
        .map(TradeType.fromMap)
        .where((t) => t.category == category);
    final maxOrder = sameCategory.isEmpty
        ? -1
        : sameCategory.map((t) => t.sortOrder).reduce((a, b) => a > b ? a : b);

    final tradeType = TradeType(
      id: _newId(),
      projectId: projectId,
      category: category,
      type: type,
      name: name,
      unit: unit,
      sortOrder: maxOrder + 1,
    );
    items.add(tradeType.toMap());
    await _store.writeJson('$folder/trade_types.json', {'items': items});
    return tradeType;
  }

  @override
  Future<void> setTradeTypeStatus(int tradeTypeId, TradeStatus status) async {
    final located = await _findTradeType(tradeTypeId);
    if (located == null) return;
    final (folder, file, items) = located;
    final index = items.indexWhere((t) => t['id'] == tradeTypeId);
    items[index] = {...items[index], 'status': status.name};
    await _store.writeJson('$folder/trade_types.json', {'items': items});
  }

  @override
  Future<void> forceDeleteTradeType(int tradeTypeId) async {
    final located = await _findTradeType(tradeTypeId);
    if (located == null) return;
    final (folder, _, items) = located;
    items.removeWhere((t) => t['id'] == tradeTypeId);
    await _store.writeJson('$folder/trade_types.json', {'items': items});

    // Historical entries for this trade type live embedded inside each
    // day's report file, so "force delete" also has to strip them from
    // every report this project has ever filed.
    final reportFiles = await _store.listFileNames('$folder/reports');
    for (final fileName in reportFiles) {
      final path = '$folder/reports/$fileName';
      final report = await _store.readJson(path);
      if (report == null) continue;
      var changed = false;
      for (final key in ['labor', 'material', 'equipment']) {
        final list = List<Map<String, dynamic>>.from(
          (report[key] as List?) ?? [],
        );
        final before = list.length;
        list.removeWhere((e) => e['trade_type_id'] == tradeTypeId);
        if (list.length != before) {
          report[key] = list;
          changed = true;
        }
      }
      if (changed) await _store.writeJson(path, report);
    }
  }

  /// Scans every known project for a trade type with this id, since the
  /// interface (matching the original sqlite one) only takes the id.
  Future<(String, Map<String, dynamic>, List<Map<String, dynamic>>)?>
  _findTradeType(int tradeTypeId) async {
    final index = await _readIndex();
    for (final p in List<Map<String, dynamic>>.from(
      index['projects'] as List,
    )) {
      final folder = p['folder'] as String;
      final file = await _readTradeTypesFile(folder);
      final items = List<Map<String, dynamic>>.from(file['items'] as List);
      if (items.any((t) => t['id'] == tradeTypeId)) {
        return (folder, file, items);
      }
    }
    return null;
  }

  // ---------------- Cumulative lookups ----------------

  static const _entryKeyByTable = {
    'labor_entries': 'labor',
    'material_entries': 'material',
    'equipment_entries': 'equipment',
  };

  Future<List<Map<String, dynamic>>> _loadAllReports(String folder) async {
    final names = await _store.listFileNames('$folder/reports');
    final reports = <Map<String, dynamic>>[];
    for (final name in names) {
      if (!name.endsWith('.json')) continue;
      final map = await _store.readJson('$folder/reports/$name');
      if (map != null) reports.add(map);
    }
    reports.sort(
      (a, b) => (a['report']['report_date'] as String).compareTo(
        b['report']['report_date'] as String,
      ),
    );
    return reports;
  }

  Future<double> _previousCumulativeIn(
    List<Map<String, dynamic>> sortedReports,
    String entryKey,
    int tradeTypeId,
    DateTime beforeDate,
  ) async {
    final beforeIso = beforeDate.toIso8601String();
    double result = 0.0;
    for (final r in sortedReports) {
      final reportDate = r['report']['report_date'] as String;
      if (!(reportDate.compareTo(beforeIso) < 0)) break;
      final entries = List<Map<String, dynamic>>.from(
        (r[entryKey] as List?) ?? [],
      );
      for (final e in entries) {
        if (e['trade_type_id'] == tradeTypeId) {
          result = (e['cumulative'] as num).toDouble();
        }
      }
    }
    return result;
  }

  @override
  Future<double> previousCumulative(
    String entryTable,
    int projectId,
    int tradeTypeId,
    DateTime beforeDate,
  ) async {
    final folder = await _folderForId(projectId);
    if (folder == null) return 0.0;
    final reports = await _loadAllReports(folder);
    return _previousCumulativeIn(
      reports,
      _entryKeyByTable[entryTable]!,
      tradeTypeId,
      beforeDate,
    );
  }

  @override
  Future<int> countWorkingDays({
    required Project project,
    required DateTime uptoDate,
    bool uptoDateIsBadWeather = false,
  }) async {
    var rainyDates = <String>{};
    if (project.excludeBadWeather) {
      final folder = await _folderForId(project.id!);
      if (folder != null) {
        final reports = await _loadAllReports(folder);
        const rainy = {'rainy', 'heavyRain', 'typhoon'};
        for (final r in reports) {
          final report = r['report'] as Map<String, dynamic>;
          final date = report['report_date'] as String;
          if (date.compareTo(uptoDate.toIso8601String()) > 0) continue;
          if (rainy.contains(report['weather_am']) ||
              rainy.contains(report['weather_pm'])) {
            rainyDates.add(date.substring(0, 10));
          }
        }
      }
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

  int _reportId(int projectId, DateTime date) =>
      projectId * 100000000 +
      date.year * 10000 +
      date.month * 100 +
      date.day;

  String _reportFileName(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}.json';

  @override
  Future<DailyReport?> getReportByDate(int projectId, DateTime date) async {
    final folder = await _folderForId(projectId);
    if (folder == null) return null;
    final map = await _store.readJson(
      '$folder/reports/${_reportFileName(date)}',
    );
    if (map == null) return null;
    return DailyReport.fromMap(map['report'] as Map<String, dynamic>);
  }

  @override
  Future<DailyReport?> getMostRecentReportBefore(
    int projectId,
    DateTime date,
  ) async {
    final folder = await _folderForId(projectId);
    if (folder == null) return null;
    final reports = await _loadAllReports(folder);
    final dayStartIso = DateTime(
      date.year,
      date.month,
      date.day,
    ).toIso8601String();
    DailyReport? best;
    for (final r in reports) {
      final reportMap = r['report'] as Map<String, dynamic>;
      if ((reportMap['report_date'] as String).compareTo(dayStartIso) < 0) {
        best = DailyReport.fromMap(reportMap);
      }
    }
    return best;
  }

  @override
  Future<int> countBackfilledReports(int projectId) async {
    final folder = await _folderForId(projectId);
    if (folder == null) return 0;
    final reports = await _loadAllReports(folder);
    return reports
        .where((r) => (r['report']['is_backfilled'] as int? ?? 0) == 1)
        .length;
  }

  @override
  Future<int> createDailyReportWithEntries({
    required DailyReport report,
    required List<LaborEntryInput> laborInputs,
    required List<MaterialEntryInput> materialInputs,
    required List<EquipmentEntryInput> equipmentInputs,
    required List<String> photoPaths,
  }) async {
    final folder = await _folderForId(report.projectId);
    if (folder == null) {
      throw StateError('找不到專案 ${report.projectId} 對應的資料夾');
    }
    final reportId = _reportId(report.projectId, report.reportDate);
    final reports = await _loadAllReports(folder);

    final fileMap = await _buildReportFile(
      report: report.copyWith(id: reportId),
      folder: folder,
      priorReports: reports,
      laborInputs: laborInputs,
      materialInputs: materialInputs,
      equipmentInputs: equipmentInputs,
      photoPaths: photoPaths,
    );

    await _store.writeJson(
      '$folder/reports/${_reportFileName(report.reportDate)}',
      fileMap,
    );
    return reportId;
  }

  @override
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
    final folder = await _folderForId(report.projectId);
    if (folder == null) {
      throw StateError('找不到專案 ${report.projectId} 對應的資料夾');
    }

    final allReports = await _loadAllReports(folder);
    // Exclude this date's own (pre-edit) file from the "priorReports"
    // lookback so its own old cumulative doesn't leak into the recompute.
    final priorOnly = allReports
        .where(
          (r) =>
              (r['report']['report_date'] as String) !=
              report.reportDate.toIso8601String(),
        )
        .toList();

    final fileMap = await _buildReportFile(
      report: report,
      folder: folder,
      priorReports: priorOnly,
      laborInputs: laborInputs,
      materialInputs: materialInputs,
      equipmentInputs: equipmentInputs,
      photoPaths: photoPaths,
    );
    await _store.writeJson(
      '$folder/reports/${_reportFileName(report.reportDate)}',
      fileMap,
    );

    await _recalculateCumulativeAfter(
      folder: folder,
      afterDate: report.reportDate,
    );
  }

  Future<Map<String, dynamic>> _buildReportFile({
    required DailyReport report,
    required String folder,
    required List<Map<String, dynamic>> priorReports,
    required List<LaborEntryInput> laborInputs,
    required List<MaterialEntryInput> materialInputs,
    required List<EquipmentEntryInput> equipmentInputs,
    required List<String> photoPaths,
  }) async {
    final labor = <Map<String, dynamic>>[];
    for (final input in laborInputs.where((e) => e.hasValue)) {
      final prevCumulative = await _previousCumulativeIn(
        priorReports,
        'labor',
        input.tradeTypeId,
        report.reportDate,
      );
      final todayTotal = (input.morningCount + input.afternoonCount) / 2;
      labor.add(
        LaborEntry(
          reportId: report.id!,
          tradeTypeId: input.tradeTypeId,
          morningCount: input.morningCount,
          afternoonCount: input.afternoonCount,
          todayTotal: todayTotal,
          cumulative: prevCumulative + todayTotal,
          isSubcontracted: input.isSubcontracted,
          vendor: input.vendor,
          todayContent: input.todayContent,
          tomorrowContent: input.tomorrowContent,
        ).toMap(),
      );
    }

    final material = <Map<String, dynamic>>[];
    for (final input in materialInputs.where((e) => e.hasValue)) {
      final prevCumulative = await _previousCumulativeIn(
        priorReports,
        'material',
        input.tradeTypeId,
        report.reportDate,
      );
      material.add(
        MaterialEntry(
          reportId: report.id!,
          tradeTypeId: input.tradeTypeId,
          quantity: input.quantity,
          cumulative: prevCumulative + input.quantity,
          usageLocation: input.usageLocation,
        ).toMap(),
      );
    }

    final equipment = <Map<String, dynamic>>[];
    for (final input in equipmentInputs.where((e) => e.hasValue)) {
      final prevCumulative = await _previousCumulativeIn(
        priorReports,
        'equipment',
        input.tradeTypeId,
        report.reportDate,
      );
      equipment.add(
        EquipmentEntry(
          reportId: report.id!,
          tradeTypeId: input.tradeTypeId,
          quantity: input.quantity,
          cumulative: prevCumulative + input.quantity,
          isSubcontracted: input.isSubcontracted,
          vendor: input.vendor,
          todayContent: input.todayContent,
          tomorrowContent: input.tomorrowContent,
        ).toMap(),
      );
    }

    final photos = [
      for (var i = 0; i < photoPaths.length; i++)
        ReportPhoto(
          reportId: report.id!,
          filePath: photoPaths[i],
          sortOrder: i,
        ).toMap(),
    ];

    return {
      'report': report.toMap(),
      'labor': labor,
      'material': material,
      'equipment': equipment,
      'photos': photos,
    };
  }

  /// Recomputes cumulative for every report strictly after [afterDate], in
  /// date order — the JSON-file equivalent of the sqlite version's cascade.
  Future<void> _recalculateCumulativeAfter({
    required String folder,
    required DateTime afterDate,
  }) async {
    final reports = await _loadAllReports(folder);
    final afterIso = afterDate.toIso8601String();

    for (var i = 0; i < reports.length; i++) {
      final reportMap = reports[i]['report'] as Map<String, dynamic>;
      final reportDateStr = reportMap['report_date'] as String;
      if (!(reportDateStr.compareTo(afterIso) > 0)) continue;

      final reportDate = DateTime.parse(reportDateStr);
      final priorReports = reports.sublist(0, i);
      var changed = false;

      for (final key in ['labor', 'equipment']) {
        final entries = List<Map<String, dynamic>>.from(
          (reports[i][key] as List?) ?? [],
        );
        for (var j = 0; j < entries.length; j++) {
          final e = entries[j];
          final prevCumulative = await _previousCumulativeIn(
            priorReports,
            key,
            e['trade_type_id'] as int,
            reportDate,
          );
          final todayValue = key == 'labor'
              ? (e['today_total'] as num).toDouble()
              : (e['quantity'] as num).toDouble();
          entries[j] = {...e, 'cumulative': prevCumulative + todayValue};
        }
        reports[i][key] = entries;
        changed = true;
      }

      final materialEntries = List<Map<String, dynamic>>.from(
        (reports[i]['material'] as List?) ?? [],
      );
      for (var j = 0; j < materialEntries.length; j++) {
        final e = materialEntries[j];
        final prevCumulative = await _previousCumulativeIn(
          priorReports,
          'material',
          e['trade_type_id'] as int,
          reportDate,
        );
        final quantity = (e['quantity'] as num).toDouble();
        materialEntries[j] = {
          ...e,
          'cumulative': prevCumulative + quantity,
        };
      }
      reports[i]['material'] = materialEntries;

      if (changed) {
        await _store.writeJson(
          '$folder/reports/${_reportFileName(reportDate)}',
          reports[i],
        );
      }
    }
  }

  @override
  Future<List<DailyReport>> getReports(int projectId) async {
    final folder = await _folderForId(projectId);
    if (folder == null) return [];
    final reports = await _loadAllReports(folder);
    final result = reports
        .map((r) => DailyReport.fromMap(r['report'] as Map<String, dynamic>))
        .toList();
    result.sort((a, b) => b.reportDate.compareTo(a.reportDate));
    return result;
  }

  Future<Map<String, dynamic>?> _reportFileById(int reportId) async {
    final index = await _readIndex();
    for (final p in List<Map<String, dynamic>>.from(
      index['projects'] as List,
    )) {
      final folder = p['folder'] as String;
      final reports = await _loadAllReports(folder);
      for (final r in reports) {
        if (r['report']['id'] == reportId) return r;
      }
    }
    return null;
  }

  @override
  Future<List<LaborEntry>> getLaborEntries(int reportId) async {
    final file = await _reportFileById(reportId);
    if (file == null) return [];
    return List<Map<String, dynamic>>.from(
      (file['labor'] as List?) ?? [],
    ).map(LaborEntry.fromMap).toList();
  }

  @override
  Future<List<MaterialEntry>> getMaterialEntries(int reportId) async {
    final file = await _reportFileById(reportId);
    if (file == null) return [];
    return List<Map<String, dynamic>>.from(
      (file['material'] as List?) ?? [],
    ).map(MaterialEntry.fromMap).toList();
  }

  @override
  Future<List<EquipmentEntry>> getEquipmentEntries(int reportId) async {
    final file = await _reportFileById(reportId);
    if (file == null) return [];
    return List<Map<String, dynamic>>.from(
      (file['equipment'] as List?) ?? [],
    ).map(EquipmentEntry.fromMap).toList();
  }

  @override
  Future<List<ReportPhoto>> getReportPhotos(int reportId) async {
    final file = await _reportFileById(reportId);
    if (file == null) return [];
    final photos = List<Map<String, dynamic>>.from(
      (file['photos'] as List?) ?? [],
    ).map(ReportPhoto.fromMap).toList();
    photos.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return photos;
  }

  // ---------------- Inspections (要徑查驗) ----------------

  @override
  Future<int> createInspection({
    required Inspection inspection,
    required List<InspectionItemRecord> items,
    required List<String> photoPaths,
  }) async {
    final folder = await _folderForId(inspection.projectId);
    if (folder == null) {
      throw StateError('找不到專案 ${inspection.projectId} 對應的資料夾');
    }
    final id = _newId();
    final created = inspection.copyWith(id: id);
    final itemMaps = [
      for (final item in items)
        InspectionItemRecord(
          inspectionId: id,
          itemName: item.itemName,
          description: item.description,
          result: item.result,
        ).toMap(),
    ];
    final photoMaps = [
      for (var i = 0; i < photoPaths.length; i++)
        InspectionPhotoRecord(
          inspectionId: id,
          filePath: photoPaths[i],
          sortOrder: i,
        ).toMap(),
    ];
    await _store.writeJson('$folder/inspections/$id.json', {
      'inspection': created.toMap(),
      'items': itemMaps,
      'photos': photoMaps,
    });
    return id;
  }

  Future<(String folder, Map<String, dynamic> file)?> _findInspectionFile(
    int inspectionId,
  ) async {
    final index = await _readIndex();
    for (final p in List<Map<String, dynamic>>.from(
      index['projects'] as List,
    )) {
      final folder = p['folder'] as String;
      final map = await _store.readJson(
        '$folder/inspections/$inspectionId.json',
      );
      if (map != null) return (folder, map);
    }
    return null;
  }

  @override
  Future<void> updateInspectionPdfPath(int inspectionId, String pdfPath) async {
    final located = await _findInspectionFile(inspectionId);
    if (located == null) return;
    final (folder, file) = located;
    final inspection = Inspection.fromMap(
      file['inspection'] as Map<String, dynamic>,
    ).copyWith(pdfPath: pdfPath);
    file['inspection'] = inspection.toMap();
    await _store.writeJson('$folder/inspections/$inspectionId.json', file);
  }

  @override
  Future<List<Inspection>> getInspections(int projectId) async {
    final folder = await _folderForId(projectId);
    if (folder == null) return [];
    final names = await _store.listFileNames('$folder/inspections');
    final inspections = <Inspection>[];
    for (final name in names) {
      if (!name.endsWith('.json')) continue;
      final map = await _store.readJson('$folder/inspections/$name');
      if (map != null) {
        inspections.add(
          Inspection.fromMap(map['inspection'] as Map<String, dynamic>),
        );
      }
    }
    inspections.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return inspections;
  }

  @override
  Future<Inspection?> getLatestInspectionFor(
    int projectId,
    String criticalPathLabel,
  ) async {
    final all = await getInspections(projectId);
    final matching = all.where(
      (i) => i.criticalPathLabel == criticalPathLabel,
    );
    if (matching.isEmpty) return null;
    return matching.first; // already sorted newest-first by getInspections
  }

  @override
  Future<List<InspectionItemRecord>> getInspectionItems(
    int inspectionId,
  ) async {
    final located = await _findInspectionFile(inspectionId);
    if (located == null) return [];
    final (_, file) = located;
    return List<Map<String, dynamic>>.from(
      (file['items'] as List?) ?? [],
    ).map(InspectionItemRecord.fromMap).toList();
  }

  @override
  Future<List<InspectionPhotoRecord>> getInspectionPhotos(
    int inspectionId,
  ) async {
    final located = await _findInspectionFile(inspectionId);
    if (located == null) return [];
    final (_, file) = located;
    final photos = List<Map<String, dynamic>>.from(
      (file['photos'] as List?) ?? [],
    ).map(InspectionPhotoRecord.fromMap).toList();
    photos.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return photos;
  }
}
