import 'weather.dart';

class DailyReport {
  final int? id;
  final int projectId;
  final DateTime reportDate;
  final Weather weatherAm;
  final Weather weatherPm;
  final bool isRainOrHoliday;

  /// 目前主要徑 / 明日要徑 (see lib/models/critical_path.dart) — the exact
  /// display label of the selected CriticalPathStep. Persisted so the next
  /// report can look up "what did yesterday's report plan for tomorrow" to
  /// lock today's choice, per the project's sequential 要徑 rule.
  final String? todayCriticalPath;
  final String? tomorrowCriticalPath;

  final String todayProgressText;
  final String tomorrowProgressText;
  final String notesText;
  final String? supervisorSignaturePath;

  /// True when this report was first created for a date earlier than the
  /// day it was actually filled in (site staff forgot to log that day at
  /// the time). Set once at creation and never changed by later edits —
  /// this is what drives the red "補登" stamp on the PDF and the per-project
  /// backfill count used in staff performance review.
  final bool isBackfilled;
  final DateTime createdAt;

  const DailyReport({
    this.id,
    required this.projectId,
    required this.reportDate,
    required this.weatherAm,
    required this.weatherPm,
    this.isRainOrHoliday = false,
    this.todayCriticalPath,
    this.tomorrowCriticalPath,
    this.todayProgressText = '',
    this.tomorrowProgressText = '',
    this.notesText = '',
    this.supervisorSignaturePath,
    this.isBackfilled = false,
    required this.createdAt,
  });

  DailyReport copyWith({int? id, String? supervisorSignaturePath}) =>
      DailyReport(
        id: id ?? this.id,
        projectId: projectId,
        reportDate: reportDate,
        weatherAm: weatherAm,
        weatherPm: weatherPm,
        isRainOrHoliday: isRainOrHoliday,
        todayCriticalPath: todayCriticalPath,
        tomorrowCriticalPath: tomorrowCriticalPath,
        todayProgressText: todayProgressText,
        tomorrowProgressText: tomorrowProgressText,
        notesText: notesText,
        supervisorSignaturePath:
            supervisorSignaturePath ?? this.supervisorSignaturePath,
        isBackfilled: isBackfilled,
        createdAt: createdAt,
      );

  Map<String, Object?> toMap() => {
    'id': id,
    'project_id': projectId,
    'report_date': reportDate.toIso8601String(),
    'weather_am': weatherAm.name,
    'weather_pm': weatherPm.name,
    'is_rain_or_holiday': isRainOrHoliday ? 1 : 0,
    'today_critical_path': todayCriticalPath,
    'tomorrow_critical_path': tomorrowCriticalPath,
    'today_progress_text': todayProgressText,
    'tomorrow_progress_text': tomorrowProgressText,
    'notes_text': notesText,
    'supervisor_signature_path': supervisorSignaturePath,
    'is_backfilled': isBackfilled ? 1 : 0,
    'created_at': createdAt.toIso8601String(),
  };

  factory DailyReport.fromMap(Map<String, Object?> map) => DailyReport(
    id: map['id'] as int?,
    projectId: map['project_id'] as int,
    reportDate: DateTime.parse(map['report_date'] as String),
    weatherAm: Weather.values.byName(map['weather_am'] as String),
    weatherPm: Weather.values.byName(map['weather_pm'] as String),
    isRainOrHoliday: (map['is_rain_or_holiday'] as int) == 1,
    todayCriticalPath: map['today_critical_path'] as String?,
    tomorrowCriticalPath: map['tomorrow_critical_path'] as String?,
    todayProgressText: map['today_progress_text'] as String? ?? '',
    tomorrowProgressText: map['tomorrow_progress_text'] as String? ?? '',
    notesText: map['notes_text'] as String? ?? '',
    supervisorSignaturePath: map['supervisor_signature_path'] as String?,
    isBackfilled: (map['is_backfilled'] as int? ?? 0) == 1,
    createdAt: DateTime.parse(map['created_at'] as String),
  );
}
