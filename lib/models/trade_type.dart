import 'trade_category.dart';

enum TradeStatus { active, disabled, deleted }

class TradeType {
  final int? id;
  final int projectId;
  final String category;
  final TradeCategoryType type;
  final String name;
  final String unit;
  final int sortOrder;
  final TradeStatus status;

  const TradeType({
    this.id,
    required this.projectId,
    required this.category,
    required this.type,
    required this.name,
    required this.unit,
    required this.sortOrder,
    this.status = TradeStatus.active,
  });

  TradeType copyWith({int? id, TradeStatus? status}) => TradeType(
    id: id ?? this.id,
    projectId: projectId,
    category: category,
    type: type,
    name: name,
    unit: unit,
    sortOrder: sortOrder,
    status: status ?? this.status,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'project_id': projectId,
    'category': category,
    'type': type.name,
    'name': name,
    'unit': unit,
    'sort_order': sortOrder,
    'status': status.name,
  };

  factory TradeType.fromMap(Map<String, Object?> map) => TradeType(
    id: map['id'] as int?,
    projectId: map['project_id'] as int,
    category: map['category'] as String,
    type: TradeCategoryType.values.byName(map['type'] as String),
    name: map['name'] as String,
    unit: map['unit'] as String,
    sortOrder: map['sort_order'] as int,
    status: TradeStatus.values.byName(map['status'] as String),
  );
}
