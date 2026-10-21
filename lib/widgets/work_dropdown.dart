import 'package:flutter/material.dart';

import '../models/work_sequence.dart';
import '../theme.dart';

/// 要徑下拉選單的項目:值是工項固定代號,顯示「順序. 代號 名稱」。
/// [selectedCode] 若已不在目前的順序裡(例如編輯舊日報),仍補一個項目
/// 讓下拉選單能顯示它。
List<DropdownMenuItem<String>> workDropdownItems(
  WorkSequence? sequence,
  String? selectedCode, {
  Iterable<WorkItem>? only,
}) {
  final items = (only ?? sequence?.items ?? const <WorkItem>[]).toList();
  final entries = <DropdownMenuItem<String>>[
    for (final i in items)
      DropdownMenuItem(
        value: i.code,
        child: Text('${i.seq}. ${i.label}', overflow: TextOverflow.ellipsis),
      ),
  ];
  if (selectedCode != null && !entries.any((e) => e.value == selectedCode)) {
    entries.add(
      DropdownMenuItem(
        value: selectedCode,
        child: Text('$selectedCode(不在目前順序)', overflow: TextOverflow.ellipsis),
      ),
    );
  }
  return entries;
}

/// 下拉選單下方的一行狀態:版本、是否用快取、下載失敗原因。
class SequenceStatusLine extends StatelessWidget {
  final WorkSequence? sequence;
  final bool loading;
  final bool fromCache;
  final String? error;

  const SequenceStatusLine({
    super.key,
    required this.sequence,
    required this.loading,
    required this.fromCache,
    required this.error,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) return const SizedBox.shrink();
    final String text;
    var warn = false;
    if (sequence == null) {
      text = '沒有要徑順序可選：${error ?? '工程管理還沒推播'}';
      warn = true;
    } else if (fromCache) {
      text = '要徑順序 v${sequence!.ver}（離線，使用上次下載的版本${error != null ? '：$error' : ''}）';
      warn = true;
    } else {
      text = '要徑順序 v${sequence!.ver}（工程管理 ${sequence!.pushedAt} 推播）';
    }
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: warn ? Colors.red : AppColors.textSecondary,
        ),
      ),
    );
  }
}
