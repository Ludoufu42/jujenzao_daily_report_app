class EquipmentEntry {
  final int? id;
  final int reportId;
  final int tradeTypeId;
  final double quantity;
  final double cumulative;
  final bool isSubcontracted;
  final String vendor;
  final String todayContent;
  final String tomorrowContent;

  const EquipmentEntry({
    this.id,
    required this.reportId,
    required this.tradeTypeId,
    required this.quantity,
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
    'quantity': quantity,
    'cumulative': cumulative,
    'is_subcontracted': isSubcontracted ? 1 : 0,
    'vendor': vendor,
    'today_content': todayContent,
    'tomorrow_content': tomorrowContent,
  };

  factory EquipmentEntry.fromMap(Map<String, Object?> map) => EquipmentEntry(
    id: map['id'] as int?,
    reportId: map['report_id'] as int,
    tradeTypeId: map['trade_type_id'] as int,
    quantity: (map['quantity'] as num).toDouble(),
    cumulative: (map['cumulative'] as num).toDouble(),
    isSubcontracted: (map['is_subcontracted'] as int) == 1,
    vendor: map['vendor'] as String? ?? '',
    todayContent: map['today_content'] as String? ?? '',
    tomorrowContent: map['tomorrow_content'] as String? ?? '',
  );
}
