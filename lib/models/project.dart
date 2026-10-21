class Project {
  final int? id;
  final String name;
  final String companyName;
  final DateTime startDate;
  final DateTime plannedCompletionDate;

  /// Whether this project tracks 工作天 (actual working days) in addition to
  /// 日曆天 (raw calendar days). If false, reports only ever show 日曆天.
  final bool tracksWorkingDays;
  final bool excludeWeekends;
  final bool excludeNationalHolidays;
  final bool excludeBadWeather;

  /// 專案概述 (building overview) — all optional, kept as raw numbers so
  /// future modules can reference the same project without redefining them.
  final double? siteAreaPing;
  final int? basementFloors;
  final double? basementFloorAreaPing;
  final int? aboveGroundFloors;
  final double? typicalFloorAreaPing;
  final int? roofFloors;
  final double? roofFloorAreaPing;

  /// 對應「振愷整合平台」工程管理的專案 id(交付包的 project_id)。
  /// 有填才會從雲端下載要徑順序、上傳日報。
  final int? platformProjectId;

  const Project({
    this.id,
    required this.name,
    required this.companyName,
    required this.startDate,
    required this.plannedCompletionDate,
    this.tracksWorkingDays = false,
    this.excludeWeekends = false,
    this.excludeNationalHolidays = false,
    this.excludeBadWeather = false,
    this.siteAreaPing,
    this.basementFloors,
    this.basementFloorAreaPing,
    this.aboveGroundFloors,
    this.typicalFloorAreaPing,
    this.roofFloors,
    this.roofFloorAreaPing,
    this.platformProjectId,
  });

  Project copyWith({int? id, int? platformProjectId}) => Project(
    id: id ?? this.id,
    name: name,
    companyName: companyName,
    startDate: startDate,
    plannedCompletionDate: plannedCompletionDate,
    tracksWorkingDays: tracksWorkingDays,
    excludeWeekends: excludeWeekends,
    excludeNationalHolidays: excludeNationalHolidays,
    excludeBadWeather: excludeBadWeather,
    siteAreaPing: siteAreaPing,
    basementFloors: basementFloors,
    basementFloorAreaPing: basementFloorAreaPing,
    aboveGroundFloors: aboveGroundFloors,
    typicalFloorAreaPing: typicalFloorAreaPing,
    roofFloors: roofFloors,
    roofFloorAreaPing: roofFloorAreaPing,
    platformProjectId: platformProjectId ?? this.platformProjectId,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'company_name': companyName,
    'start_date': startDate.toIso8601String(),
    'planned_completion_date': plannedCompletionDate.toIso8601String(),
    'tracks_working_days': tracksWorkingDays ? 1 : 0,
    'exclude_weekends': excludeWeekends ? 1 : 0,
    'exclude_national_holidays': excludeNationalHolidays ? 1 : 0,
    'exclude_bad_weather': excludeBadWeather ? 1 : 0,
    'site_area_ping': siteAreaPing,
    'basement_floors': basementFloors,
    'basement_floor_area_ping': basementFloorAreaPing,
    'above_ground_floors': aboveGroundFloors,
    'typical_floor_area_ping': typicalFloorAreaPing,
    'roof_floors': roofFloors,
    'roof_floor_area_ping': roofFloorAreaPing,
    'platform_project_id': platformProjectId,
  };

  factory Project.fromMap(Map<String, Object?> map) => Project(
    id: map['id'] as int?,
    name: map['name'] as String,
    companyName: map['company_name'] as String,
    startDate: DateTime.parse(map['start_date'] as String),
    plannedCompletionDate: DateTime.parse(
      map['planned_completion_date'] as String,
    ),
    tracksWorkingDays: (map['tracks_working_days'] as int? ?? 0) == 1,
    excludeWeekends: (map['exclude_weekends'] as int? ?? 0) == 1,
    excludeNationalHolidays:
        (map['exclude_national_holidays'] as int? ?? 0) == 1,
    excludeBadWeather: (map['exclude_bad_weather'] as int? ?? 0) == 1,
    siteAreaPing: (map['site_area_ping'] as num?)?.toDouble(),
    basementFloors: map['basement_floors'] as int?,
    basementFloorAreaPing: (map['basement_floor_area_ping'] as num?)
        ?.toDouble(),
    aboveGroundFloors: map['above_ground_floors'] as int?,
    typicalFloorAreaPing: (map['typical_floor_area_ping'] as num?)
        ?.toDouble(),
    roofFloors: map['roof_floors'] as int?,
    roofFloorAreaPing: (map['roof_floor_area_ping'] as num?)?.toDouble(),
    platformProjectId: map['platform_project_id'] as int?,
  );
}
