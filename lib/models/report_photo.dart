class ReportPhoto {
  final int? id;
  final int reportId;
  final String filePath;
  final int sortOrder;

  const ReportPhoto({
    this.id,
    required this.reportId,
    required this.filePath,
    required this.sortOrder,
  });

  Map<String, Object?> toMap() => {
    'id': id,
    'report_id': reportId,
    'file_path': filePath,
    'sort_order': sortOrder,
  };

  factory ReportPhoto.fromMap(Map<String, Object?> map) => ReportPhoto(
    id: map['id'] as int?,
    reportId: map['report_id'] as int,
    filePath: map['file_path'] as String,
    sortOrder: map['sort_order'] as int,
  );
}
