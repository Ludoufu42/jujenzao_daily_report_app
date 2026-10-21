enum InspectionResult { pass, defect }

extension InspectionResultLabel on InspectionResult {
  String get label => this == InspectionResult.pass ? '合格' : '缺失';
}

class Inspection {
  final int? id;
  final int projectId;

  /// The 要徑 work item this inspection covers: the 工項固定代號 from the
  /// 工程管理 sequence delivery package (WorkItem.code), e.g. "T102".
  final String workCode;
  final String templateName;
  final String? inspectorSignaturePath;
  final String? pdfPath;
  final DateTime createdAt;

  const Inspection({
    this.id,
    required this.projectId,
    required this.workCode,
    required this.templateName,
    this.inspectorSignaturePath,
    this.pdfPath,
    required this.createdAt,
  });

  Inspection copyWith({int? id, String? pdfPath}) => Inspection(
    id: id ?? this.id,
    projectId: projectId,
    workCode: workCode,
    templateName: templateName,
    inspectorSignaturePath: inspectorSignaturePath,
    pdfPath: pdfPath ?? this.pdfPath,
    createdAt: createdAt,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'project_id': projectId,
    'work_code': workCode,
    'template_name': templateName,
    'inspector_signature_path': inspectorSignaturePath,
    'pdf_path': pdfPath,
    'created_at': createdAt.toIso8601String(),
  };

  factory Inspection.fromMap(Map<String, Object?> map) => Inspection(
    id: map['id'] as int?,
    projectId: map['project_id'] as int,
    workCode: map['work_code'] as String,
    templateName: map['template_name'] as String,
    inspectorSignaturePath: map['inspector_signature_path'] as String?,
    pdfPath: map['pdf_path'] as String?,
    createdAt: DateTime.parse(map['created_at'] as String),
  );
}

class InspectionItemRecord {
  final int? id;
  final int inspectionId;
  final String itemName;
  final String description;
  final InspectionResult result;

  const InspectionItemRecord({
    this.id,
    required this.inspectionId,
    required this.itemName,
    required this.description,
    required this.result,
  });

  Map<String, Object?> toMap() => {
    'id': id,
    'inspection_id': inspectionId,
    'item_name': itemName,
    'description': description,
    'result': result.name,
  };

  factory InspectionItemRecord.fromMap(Map<String, Object?> map) =>
      InspectionItemRecord(
        id: map['id'] as int?,
        inspectionId: map['inspection_id'] as int,
        itemName: map['item_name'] as String,
        description: map['description'] as String,
        result: InspectionResult.values.byName(map['result'] as String),
      );
}

class InspectionPhotoRecord {
  final int? id;
  final int inspectionId;
  final String filePath;
  final int sortOrder;

  const InspectionPhotoRecord({
    this.id,
    required this.inspectionId,
    required this.filePath,
    required this.sortOrder,
  });

  Map<String, Object?> toMap() => {
    'id': id,
    'inspection_id': inspectionId,
    'file_path': filePath,
    'sort_order': sortOrder,
  };

  factory InspectionPhotoRecord.fromMap(Map<String, Object?> map) =>
      InspectionPhotoRecord(
        id: map['id'] as int?,
        inspectionId: map['inspection_id'] as int,
        filePath: map['file_path'] as String,
        sortOrder: map['sort_order'] as int,
      );
}
