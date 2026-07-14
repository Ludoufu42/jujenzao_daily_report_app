class LaborEntry {
  final int? id;
  final int reportId;
  final int tradeTypeId;
  final double morningCount;
  final double afternoonCount;
  final double todayTotal;
  final double cumulative;
  final bool isSubcontracted;
  final String vendor;
  final String todayContent;
  final String tomorrowContent;

  const LaborEntry({
    this.id,
    required this.reportId,
    required this.tradeTypeId,
    required this.morningCount,
    required this.afternoonCount,
    required this.todayTotal,
    required this.cumulative,
    this.isSubcontracted = false,
    this.vendor = '',
    this.todayContent = '',
    this.tomorrowContent = '',
  });

  Map<String, Object?> toMap() => {
    'id': id,
    'report_id': reportId,
    'trade_type_id': tradeTypeId,
    'morning_count': morningCount,
    'afternoon_count': afternoonCount,
    'today_total': todayTotal,
    'cumulative': cumulative,
    'is_subcontracted': isSubcontracted ? 1 : 0,
    'vendor': vendor,
    'today_content': todayContent,
    'tomorrow_content': tomorrowContent,
  };

  factory LaborEntry.fromMap(Map<String, Object?> map) => LaborEntry(
    id: map['id'] as int?,
    reportId: map['report_id'] as int,
    tradeTypeId: map['trade_type_id'] as int,
    morningCount: (map['morning_count'] as num).toDouble(),
    afternoonCount: (map['afternoon_count'] as num).toDouble(),
    todayTotal: (map['today_total'] as num).toDouble(),
    cumulative: (map['cumulative'] as num).toDouble(),
    isSubcontracted: (map['is_subcontracted'] as int) == 1,
    vendor: map['vendor'] as String? ?? '',
    todayContent: map['today_content'] as String? ?? '',
    tomorrowContent: map['tomorrow_content'] as String? ?? '',
  );
}
