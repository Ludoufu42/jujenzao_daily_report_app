/// 工程管理「推播」交付包 `works-sequence/1` 的要徑順序(從 R2 的 latest.json 下載)。
/// 只有順序,沒有日期;各工序何時開始由日報填表人決定。
/// 工項一律用固定代號 [WorkItem.code] 識別,名稱可能被改,不能當識別。
class WorkItem {
  final int seq;
  final String code;
  final String name;
  final String grp;
  final String path;

  const WorkItem({
    required this.seq,
    required this.code,
    required this.name,
    this.grp = '',
    this.path = '',
  });

  /// 下拉選單顯示用,例如「T102 假設工程 圍籬施作」。
  String get label => '$code $name';

  factory WorkItem.fromJson(Map<String, dynamic> j) => WorkItem(
    seq: (j['seq'] as num).toInt(),
    code: j['code'] as String,
    name: j['name'] as String? ?? '',
    grp: j['grp'] as String? ?? '',
    path: j['path'] as String? ?? '',
  );

  Map<String, Object?> toJson() => {
    'seq': seq,
    'code': code,
    'name': name,
    'grp': grp,
    'path': path,
  };
}

class WorkSequence {
  static const schemaName = 'works-sequence/1';

  final int projectId;
  final String projectShort;
  final int ver;
  final String pushedAt;
  final List<WorkItem> items;

  const WorkSequence({
    required this.projectId,
    required this.projectShort,
    required this.ver,
    required this.pushedAt,
    required this.items,
  });

  /// 解析交付包;格式不對就丟 [FormatException]。
  factory WorkSequence.fromJson(Map<String, dynamic> j) {
    if (j['schema'] != schemaName) {
      throw FormatException('不是 $schemaName 的交付包');
    }
    final items =
        (j['items'] as List)
            .map((e) => WorkItem.fromJson(e as Map<String, dynamic>))
            .toList()
          ..sort((a, b) => a.seq.compareTo(b.seq));
    return WorkSequence(
      projectId: (j['project_id'] as num).toInt(),
      projectShort: j['project_short'] as String? ?? '',
      ver: (j['ver'] as num).toInt(),
      pushedAt: j['pushed_at'] as String? ?? '',
      items: items,
    );
  }

  Map<String, Object?> toJson() => {
    'schema': schemaName,
    'project_id': projectId,
    'project_short': projectShort,
    'ver': ver,
    'pushed_at': pushedAt,
    'count': items.length,
    'items': items.map((i) => i.toJson()).toList(),
  };

  WorkItem? byCode(String? code) {
    if (code == null) return null;
    for (final i in items) {
      if (i.code == code) return i;
    }
    return null;
  }

  /// 從 [code] 這一項起(含)到最後的工項。今日要徑只能是昨天的要徑或它後面的
  /// (進度只會往前,一天做完兩個要徑也可能);[code] 是 null 或找不到就是全部。
  List<WorkItem> itemsFrom(String? code) {
    if (code == null) return items;
    final index = items.indexWhere((i) => i.code == code);
    return index == -1 ? items : items.sublist(index);
  }

  /// 順序上緊接在 [code] 之後的工項;[code] 是最後一項或找不到就回 null。
  WorkItem? next(String? code) {
    if (code == null) return null;
    final index = items.indexWhere((i) => i.code == code);
    if (index == -1 || index == items.length - 1) return null;
    return items[index + 1];
  }
}
