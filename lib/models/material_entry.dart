class MaterialEntry {
  final int? id;
  final int reportId;
  final int tradeTypeId;
  final double quantity;
  final double cumulative;
  final String usageLocation;

  const MaterialEntry({
    this.id,
    required this.reportId,
    required this.tradeTypeId,
    required this.quantity,
    required this.cumulative,
    this.usageLocation = '',
  });

  Map<String, Object?> toMap() => {
    'id': id,
    'report_id': reportId,
    'trade_type_id': tradeTypeId,
    'quantity': quantity,
    'cumulative': cumulative,
    'usage_location': usageLocation,
  };

  factory MaterialEntry.fromMap(Map<String, Object?> map) => MaterialEntry(
    id: map['id'] as int?,
    reportId: map['report_id'] as int,
    tradeTypeId: map['trade_type_id'] as int,
    quantity: (map['quantity'] as num).toDouble(),
    cumulative: (map['cumulative'] as num).toDouble(),
    usageLocation: map['usage_location'] as String? ?? '',
  );
}
