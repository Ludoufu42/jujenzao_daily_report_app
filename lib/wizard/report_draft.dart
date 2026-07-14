import 'package:flutter/foundation.dart';

import '../models/daily_report.dart';
import '../models/equipment_entry.dart';
import '../models/labor_entry.dart';
import '../models/material_entry.dart';
import '../models/project.dart';
import '../models/report_photo.dart';
import '../models/weather.dart';

class LaborDraftEntry {
  double? morning;
  double? afternoon;
  bool isSubcontracted = false;
  String vendor = '';
  String todayContent = '';
  String tomorrowContent = '';
}

class MaterialDraftEntry {
  double? quantity;
  String usageLocation = '';
}

class EquipmentDraftEntry {
  double? quantity;
  bool isSubcontracted = false;
  String vendor = '';
  String todayContent = '';
  String tomorrowContent = '';
}

/// Holds every in-progress field across the 7-step wizard for a single
/// daily report. Each screen mutates it directly and calls [notifyListeners].
/// The per-step `reset*` methods back the header "reset" button, which only
/// clears the current step, never the whole draft.
class ReportDraft extends ChangeNotifier {
  final Project project;

  ReportDraft(this.project) {
    reportDate = DateTime.now();
  }

  late DateTime reportDate;
  Weather weatherAm = Weather.sunny;
  Weather weatherPm = Weather.sunny;
  bool isRainOrHoliday = false;

  /// Non-null once [reportDate] is confirmed to match an already-filed
  /// report — the wizard is then editing/replacing that report instead of
  /// creating a new one, and the PDF regenerated from it never gets an
  /// isBackfilled stamp regardless of what it originally was.
  int? existingReportId;

  /// True when [reportDate] is a date with no existing report AND it is
  /// earlier than the actual day this draft is being filled in — i.e. site
  /// staff forgot to log that day at the time. Drives the 補登 PDF stamp and
  /// the per-project backfill count.
  bool isBackfillEntry = false;

  /// 目前主要徑 — which critical-path location this report's progress is
  /// about. Options are meant to be generated from the project's 專案概述
  /// floor data; exact generation rule TBD, so this is just a plain string
  /// selection for now.
  String? todayCriticalPath;

  String todayProgress = '';

  /// 明日要徑 — mirrors [todayCriticalPath] but for tomorrow's planned work.
  String? tomorrowCriticalPath;

  String tomorrowProgress = '';
  String notes = '';

  final Map<int, LaborDraftEntry> laborEntries = {};
  final Map<int, MaterialDraftEntry> materialEntries = {};
  final Map<int, EquipmentDraftEntry> equipmentEntries = {};

  final List<String> photoPaths = [];

  String? supervisorSignaturePath;

  LaborDraftEntry laborFor(int tradeTypeId) =>
      laborEntries.putIfAbsent(tradeTypeId, () => LaborDraftEntry());

  MaterialDraftEntry materialFor(int tradeTypeId) =>
      materialEntries.putIfAbsent(tradeTypeId, () => MaterialDraftEntry());

  EquipmentDraftEntry equipmentFor(int tradeTypeId) =>
      equipmentEntries.putIfAbsent(tradeTypeId, () => EquipmentDraftEntry());

  /// Called after picking a date with no existing report. [isBackfill] is
  /// true when that date is earlier than today (site staff forgot to log
  /// it). Clears out any previously loaded edit-mode data so a fresh new
  /// report starts empty.
  void startNewReportFor(DateTime date, {required bool isBackfill}) {
    reportDate = date;
    existingReportId = null;
    isBackfillEntry = isBackfill;
    // Re-derived by StepTodayProgress on init (looks up the previous
    // report's tomorrowCriticalPath to lock this day's choice, per rule 3).
    todayCriticalPath = null;
    tomorrowCriticalPath = null;
    todayProgress = '';
    tomorrowProgress = '';
    notes = '';
    laborEntries.clear();
    materialEntries.clear();
    equipmentEntries.clear();
    entriesGeneration++;
    photoPaths.clear();
    notifyListeners();
  }

  /// Called after picking a date that already has a filed report — loads
  /// every field of that report into the draft so the wizard behaves as an
  /// edit rather than a fresh entry.
  void loadExistingReport({
    required DailyReport report,
    required List<LaborEntry> laborEntriesData,
    required List<MaterialEntry> materialEntriesData,
    required List<EquipmentEntry> equipmentEntriesData,
    required List<ReportPhoto> photos,
  }) {
    reportDate = report.reportDate;
    existingReportId = report.id;
    isBackfillEntry = false;
    weatherAm = report.weatherAm;
    weatherPm = report.weatherPm;
    todayCriticalPath = report.todayCriticalPath;
    tomorrowCriticalPath = report.tomorrowCriticalPath;
    todayProgress = report.todayProgressText;
    tomorrowProgress = report.tomorrowProgressText;
    notes = report.notesText;

    laborEntries.clear();
    for (final e in laborEntriesData) {
      final entry = LaborDraftEntry()
        ..morning = e.morningCount
        ..afternoon = e.afternoonCount
        ..isSubcontracted = e.isSubcontracted
        ..vendor = e.vendor
        ..todayContent = e.todayContent
        ..tomorrowContent = e.tomorrowContent;
      laborEntries[e.tradeTypeId] = entry;
    }

    materialEntries.clear();
    for (final e in materialEntriesData) {
      final entry = MaterialDraftEntry()
        ..quantity = e.quantity
        ..usageLocation = e.usageLocation;
      materialEntries[e.tradeTypeId] = entry;
    }

    equipmentEntries.clear();
    for (final e in equipmentEntriesData) {
      final entry = EquipmentDraftEntry()
        ..quantity = e.quantity
        ..isSubcontracted = e.isSubcontracted
        ..vendor = e.vendor
        ..todayContent = e.todayContent
        ..tomorrowContent = e.tomorrowContent;
      equipmentEntries[e.tradeTypeId] = entry;
    }
    entriesGeneration++;

    photoPaths
      ..clear()
      ..addAll(photos.map((p) => p.filePath));

    notifyListeners();
  }

  void resetDateWeather() {
    reportDate = DateTime.now();
    weatherAm = Weather.sunny;
    weatherPm = Weather.sunny;
    isRainOrHoliday = false;
    notifyListeners();
  }

  void resetTodayProgress() {
    todayProgress = '';
    todayCriticalPath = null;
    notifyListeners();
  }

  void resetTomorrowProgressAndNotes() {
    tomorrowCriticalPath = null;
    tomorrowProgress = '';
    notes = '';
    notifyListeners();
  }

  /// Bumped every time [resetEntries] runs so entry-row widgets (which use
  /// TextFormField's `initialValue`, not a controller) can be keyed on it
  /// and get freshly remounted — otherwise Flutter reuses their State and
  /// the visible text never clears even though the underlying maps did.
  int entriesGeneration = 0;

  void resetEntries() {
    laborEntries.clear();
    materialEntries.clear();
    equipmentEntries.clear();
    entriesGeneration++;
    notifyListeners();
  }

  void resetPhotos() {
    photoPaths.clear();
    notifyListeners();
  }

  void touch() => notifyListeners();
}

/// Builds the persistable [DailyReport] row from an in-progress [ReportDraft].
class DailyReportBuilder {
  static DailyReport build(ReportDraft draft, bool isRainOrHoliday) {
    return DailyReport(
      id: draft.existingReportId,
      projectId: draft.project.id!,
      reportDate: draft.reportDate,
      weatherAm: draft.weatherAm,
      weatherPm: draft.weatherPm,
      isRainOrHoliday: isRainOrHoliday,
      todayCriticalPath: draft.todayCriticalPath,
      tomorrowCriticalPath: draft.tomorrowCriticalPath,
      todayProgressText: draft.todayProgress,
      tomorrowProgressText: draft.tomorrowProgress,
      notesText: draft.notes,
      isBackfilled: draft.isBackfillEntry,
      createdAt: DateTime.now(),
    );
  }
}
