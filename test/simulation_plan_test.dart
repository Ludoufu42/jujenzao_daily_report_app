import 'package:flutter_test/flutter_test.dart';
import 'package:jujenzao_daily_report_app/models/weather.dart';
import 'package:jujenzao_daily_report_app/models/work_sequence.dart';
import 'package:jujenzao_daily_report_app/services/app_clock.dart';
import 'package:jujenzao_daily_report_app/services/simulation_plan.dart';

WorkSequence _seq(int n) => WorkSequence(
  projectId: 2,
  projectShort: 't',
  ver: 1,
  pushedAt: '',
  items: [
    for (var i = 1; i <= n; i++)
      WorkItem(
        seq: i,
        code: 'T${100 + i}',
        name: i % 5 == 0 ? '樓層灌漿 $i' : '工項 $i',
      ),
  ],
);

void main() {
  group('SimulationPlan', () {
    final seq = _seq(54);
    final plan = SimulationPlan.generate(
      sequence: seq,
      start: DateTime(2026, 11, 2),
      seed: 7,
    );

    test('跑完整個要徑,最後一天剛好做完最後一項', () {
      expect(plan, isNotEmpty);
      expect(plan.last.isLast, isTrue);
      expect(plan.last.today.code, seq.items.last.code);
      expect(plan.where((d) => d.isLast), hasLength(1));
      // 54 個工項、平均幾天一項,天數落在合理範圍(不是 2 天也不是 1000 天)。
      expect(plan.length, inInclusiveRange(60, 400));
    });

    test('週日不施工;日期嚴格遞增', () {
      expect(plan.any((d) => d.date.weekday == DateTime.sunday), isFalse);
      for (var i = 1; i < plan.length; i++) {
        expect(plan[i].date.isAfter(plan[i - 1].date), isTrue);
      }
      expect(plan.first.date, DateTime(2026, 11, 2));
    });

    test('今日要徑絕不早於昨天的今日要徑;明日要徑絕不早於今日', () {
      int idx(String code) => seq.items.indexWhere((i) => i.code == code);
      for (var i = 0; i < plan.length; i++) {
        expect(idx(plan[i].tomorrow.code), greaterThanOrEqualTo(idx(plan[i].today.code)));
        if (i > 0) {
          expect(idx(plan[i].today.code), greaterThanOrEqualTo(idx(plan[i - 1].today.code)));
          // 昨天的明日要徑 = 今天一開始在做的項目,今日要徑只會在它或它之後。
          expect(idx(plan[i].today.code), greaterThanOrEqualTo(idx(plan[i - 1].tomorrow.code)));
        }
      }
    });

    test('停工日(豪大雨/颱風)進度不前進', () {
      final stopped = plan.where((d) => d.stopped).toList();
      expect(stopped, isNotEmpty);
      for (final d in stopped) {
        expect(d.finished, 0);
        expect(d.tomorrow.code, d.today.code);
        expect(
          d.weatherAm == Weather.heavyRain ||
              d.weatherAm == Weather.typhoon ||
              d.weatherPm == Weather.heavyRain ||
              d.weatherPm == Weather.typhoon,
          isTrue,
        );
      }
    });

    test('有「一天做完兩項」的日子(今天已經在後面的項目)', () {
      expect(plan.any((d) => d.finished == 2), isTrue);
    });

    test('同樣的種子產生同樣的計畫;空的順序沒有計畫', () {
      final again = SimulationPlan.generate(
        sequence: seq,
        start: DateTime(2026, 11, 2),
        seed: 7,
      );
      expect(again.length, plan.length);
      expect(again.last.date, plan.last.date);
      expect(
        SimulationPlan.generate(sequence: _seq(0), start: DateTime(2026, 11, 2)),
        isEmpty,
      );
    });
  });

  group('AppClock', () {
    tearDown(() => AppClock.simulate(null));

    test('模擬日期:年月日換成模擬的,時分秒仍是真實的;清掉就回到真實時間', () {
      expect(AppClock.isSimulated, isFalse);
      AppClock.simulate(DateTime(2027, 3, 5, 23, 59));
      final now = AppClock.now();
      expect([now.year, now.month, now.day], [2027, 3, 5]);
      expect(AppClock.isSimulated, isTrue);
      AppClock.simulate(null);
      expect(AppClock.now().year, DateTime.now().year);
    });
  });
}
