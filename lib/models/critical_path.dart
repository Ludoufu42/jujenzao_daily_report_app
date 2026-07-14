import 'project.dart';

const _cnNum = [
  '零', '一', '二', '三', '四', '五', '六', '七', '八', '九', '十',
  '十一', '十二', '十三', '十四', '十五', '十六', '十七', '十八', '十九', '二十',
];

String _cn(int n) => n < _cnNum.length ? _cnNum[n] : '$n';

const _fixedPreliminary = ['圍籬施作', '擋土設施施作', '土方出土', 'PC灌漿'];
const _fixedFoundation = [
  '放樣工程', '柱鋼筋組立', '地梁鋼筋組立', '大底灌漿', '套管施作', '地梁灌漿', '樓板施作', '樓板灌漿',
];
// 地下樓層沒有外模組立（周圍是擋土壁，不需要外模）。
const _basementFloorItems = ['放樣工程', '柱鋼筋組立', '牆鋼筋組立', '內牆封模', '梁板鋼筋組立', '樓層灌漿'];
// 地上樓層與屋凸層邏輯相同，都比地下樓層多一項外模組立。
const _aboveGroundFloorItems = [
  '放樣工程', '柱鋼筋組立', '外模組立', '牆鋼筋組立', '內牆封模', '梁板鋼筋組立', '樓層灌漿',
];

class CriticalPathStep {
  final int number;
  final String firstHalf;
  final String secondHalf;

  const CriticalPathStep({
    required this.number,
    required this.firstHalf,
    required this.secondHalf,
  });

  /// The dropdown's display text is always the direct concatenation of the
  /// two halves — every row repeats its group's firstHalf (not just the
  /// first row of the group), otherwise a row picked on its own would show
  /// an incomplete label.
  String get label => '$firstHalf$secondHalf';
}

/// Generates the full, ordered 要徑 (critical path) list for a project based
/// on its 專案概述 floor counts — basement floors are sequenced deepest to
/// shallowest (built first), then above-ground floors bottom to top, then
/// roof-projection floors bottom to top. Mirrors the pattern taught via
/// 工程要徑範例.xlsx. Only covers through structural completion (每層樓層灌漿)
/// — later phases (裝修/機電 etc.) are not modeled yet.
List<CriticalPathStep> generateCriticalPathSteps(Project project) {
  final steps = <CriticalPathStep>[];
  var number = 1;

  void add(String firstHalf, String secondHalf) {
    steps.add(
      CriticalPathStep(number: number, firstHalf: firstHalf, secondHalf: secondHalf),
    );
    number++;
  }

  for (final item in _fixedPreliminary) {
    add('假設工程', item);
  }
  for (final item in _fixedFoundation) {
    add('基礎工程', item);
  }

  final basementFloors = project.basementFloors ?? 0;
  for (var floor = basementFloors; floor >= 1; floor--) {
    final label = '地下${_cn(floor)}樓';
    for (final item in _basementFloorItems) {
      add(label, item);
    }
  }

  final aboveGroundFloors = project.aboveGroundFloors ?? 0;
  for (var floor = 1; floor <= aboveGroundFloors; floor++) {
    final label = '地上${_cn(floor)}樓';
    for (final item in _aboveGroundFloorItems) {
      add(label, item);
    }
  }

  final roofFloors = project.roofFloors ?? 0;
  for (var floor = 1; floor <= roofFloors; floor++) {
    final label = '屋凸${_cn(floor)}層';
    for (final item in _aboveGroundFloorItems) {
      add(label, item);
    }
  }

  return steps;
}

/// The step immediately after [currentLabel] in [steps], or null if
/// [currentLabel] is the last step (or not found at all).
CriticalPathStep? nextCriticalPathStep(
  List<CriticalPathStep> steps,
  String? currentLabel,
) {
  if (currentLabel == null) return null;
  final index = steps.indexWhere((s) => s.label == currentLabel);
  if (index == -1 || index == steps.length - 1) return null;
  return steps[index + 1];
}
