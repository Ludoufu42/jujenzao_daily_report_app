import 'work_sequence.dart';

/// 工程管理推播的專案包 `project-bundle/1`:專案基本資料 + 要徑順序。
/// 員工不建專案,App 從雲端下載這份、依它建立/更新本機專案。
class ProjectBundle {
  static const schemaName = 'project-bundle/1';

  final int ver;
  final String pushedAt;
  final int projectId;
  final String short;
  final String name;
  final String code;
  final String company;
  final int basementFloors;
  final int aboveGroundFloors;
  final int roofFloors;
  final DateTime? plannedStart;
  final DateTime? plannedEnd;
  final WorkSequence sequence;

  const ProjectBundle({
    required this.ver,
    required this.pushedAt,
    required this.projectId,
    required this.short,
    required this.name,
    required this.code,
    required this.company,
    required this.basementFloors,
    required this.aboveGroundFloors,
    required this.roofFloors,
    required this.plannedStart,
    required this.plannedEnd,
    required this.sequence,
  });

  /// 畫面上顯示的專案名稱:有簡稱用簡稱,沒有用全名。
  String get displayName => short.isNotEmpty ? short : name;

  factory ProjectBundle.fromJson(Map<String, dynamic> j) {
    if (j['schema'] != schemaName) {
      throw const FormatException('不是 $schemaName 的專案包');
    }
    final p = j['project'] as Map<String, dynamic>;
    final ver = (j['ver'] as num).toInt();
    final pid = (p['project_id'] as num).toInt();
    final short = p['short'] as String? ?? '';
    final pushedAt = j['pushed_at'] as String? ?? '';
    final items =
        (j['items'] as List)
            .map((e) => WorkItem.fromJson(e as Map<String, dynamic>))
            .toList()
          ..sort((a, b) => a.seq.compareTo(b.seq));
    DateTime? date(Object? v) =>
        v is String && v.isNotEmpty ? DateTime.tryParse(v) : null;
    return ProjectBundle(
      ver: ver,
      pushedAt: pushedAt,
      projectId: pid,
      short: short,
      name: p['name'] as String? ?? '',
      code: p['code'] as String? ?? '',
      company: p['company'] as String? ?? '',
      basementFloors: (p['basement_floors'] as num?)?.toInt() ?? 0,
      aboveGroundFloors: (p['above_ground_floors'] as num?)?.toInt() ?? 0,
      roofFloors: (p['roof_floors'] as num?)?.toInt() ?? 0,
      plannedStart: date(p['planned_start']),
      plannedEnd: date(p['planned_end']),
      sequence: WorkSequence(
        projectId: pid,
        projectShort: short,
        ver: ver,
        pushedAt: pushedAt,
        items: items,
      ),
    );
  }
}

/// `GET /app/me` 的結果:登入者與可看的專案。
class MeInfo {
  final String email;
  final String name;
  final List<MeProject> projects;
  const MeInfo({required this.email, required this.name, required this.projects});

  factory MeInfo.fromJson(Map<String, dynamic> j) => MeInfo(
    email: j['email'] as String? ?? '',
    name: j['name'] as String? ?? '',
    projects: [
      for (final p in (j['projects'] as List? ?? const []))
        MeProject.fromJson(p as Map<String, dynamic>),
    ],
  );

  Map<String, Object?> toJson() => {
    'email': email,
    'name': name,
    'projects': projects.map((p) => p.toJson()).toList(),
  };
}

class MeProject {
  final int projectId;
  final String? short;
  final String? name;
  final int? bundleVer;
  const MeProject({required this.projectId, this.short, this.name, this.bundleVer});

  factory MeProject.fromJson(Map<String, dynamic> j) => MeProject(
    projectId: (j['project_id'] as num).toInt(),
    short: j['short'] as String?,
    name: j['name'] as String?,
    bundleVer: (j['bundle_ver'] as num?)?.toInt(),
  );

  Map<String, Object?> toJson() => {
    'project_id': projectId,
    'short': short,
    'name': name,
    'bundle_ver': bundleVer,
  };
}
