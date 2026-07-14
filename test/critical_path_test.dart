import 'package:flutter_test/flutter_test.dart';

import 'package:jujenzao_daily_report_app/models/critical_path.dart';
import 'package:jujenzao_daily_report_app/models/project.dart';

Project _project({
  required int basement,
  required int aboveGround,
  required int roof,
}) => Project(
  name: 'Test',
  companyName: 'Test',
  startDate: DateTime(2026, 1, 1),
  plannedCompletionDate: DateTime(2027, 1, 1),
  basementFloors: basement,
  aboveGroundFloors: aboveGround,
  roofFloors: roof,
);

void main() {
  test('地下二地上三屋凸一 matches the reference example exactly (52 steps)', () {
    final steps = generateCriticalPathSteps(
      _project(basement: 2, aboveGround: 3, roof: 1),
    );

    expect(steps.length, 52);
    expect(steps[0].label, '假設工程圍籬施作');
    expect(steps[3].label, '假設工程PC灌漿');
    expect(steps[4].label, '基礎工程放樣工程');
    expect(steps[11].label, '基礎工程樓板灌漿');
    // 地下樓層由深到淺：地下二樓先於地下一樓。
    expect(steps[12].label, '地下二樓放樣工程');
    expect(steps[17].label, '地下二樓樓層灌漿');
    expect(steps[18].label, '地下一樓放樣工程');
    // 地下樓層沒有外模組立。
    expect(steps.sublist(12, 24).any((s) => s.secondHalf == '外模組立'), isFalse);
    // 地上樓層由低到高，且含外模組立。
    expect(steps[24].label, '地上一樓放樣工程');
    expect(steps[26].label, '地上一樓外模組立');
    expect(steps[38].label, '地上三樓放樣工程');
    // 屋凸層接續地上樓層之後。
    expect(steps[45].label, '屋凸一層放樣工程');
    expect(steps.last.label, '屋凸一層樓層灌漿');
    // 編號連續不重複、從1開始。
    expect(steps.map((s) => s.number).toList(), List.generate(52, (i) => i + 1));
  });

  test('地下零地上五屋凸二 has no basement section and 61 steps total', () {
    final steps = generateCriticalPathSteps(
      _project(basement: 0, aboveGround: 5, roof: 2),
    );

    expect(steps.length, 61);
    // No 地下 labels anywhere.
    expect(steps.any((s) => s.firstHalf.startsWith('地下')), isFalse);
    // Foundation work is immediately followed by 地上一樓.
    expect(steps[11].label, '基礎工程樓板灌漿');
    expect(steps[12].label, '地上一樓放樣工程');
    expect(steps.last.label, '屋凸二層樓層灌漿');
  });

  test('a project with no floor data still yields the fixed 12-step base',
      () {
    final steps = generateCriticalPathSteps(
      Project(
        name: 'No floors set',
        companyName: 'Test',
        startDate: DateTime(2026, 1, 1),
        plannedCompletionDate: DateTime(2027, 1, 1),
      ),
    );
    expect(steps.length, 12);
  });

  group('nextCriticalPathStep (backs the 明日要徑 rule)', () {
    test('returns the immediately following step', () {
      final steps = generateCriticalPathSteps(
        _project(basement: 0, aboveGround: 2, roof: 0),
      );
      final next = nextCriticalPathStep(steps, '假設工程圍籬施作');
      expect(next!.label, '假設工程擋土設施施作');
    });

    test('returns null for the last step', () {
      final steps = generateCriticalPathSteps(
        _project(basement: 0, aboveGround: 1, roof: 0),
      );
      expect(nextCriticalPathStep(steps, steps.last.label), isNull);
    });

    test('returns null for a null or unrecognised label', () {
      final steps = generateCriticalPathSteps(
        _project(basement: 0, aboveGround: 1, roof: 0),
      );
      expect(nextCriticalPathStep(steps, null), isNull);
      expect(nextCriticalPathStep(steps, '不存在的要徑'), isNull);
    });
  });
}
