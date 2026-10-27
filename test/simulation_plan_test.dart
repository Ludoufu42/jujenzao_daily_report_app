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
    final start = DateTime(2026, 11, 2);
    final end = DateTime(2027, 5, 10);
    final plan = SimulationPlan.generate(
      sequence: seq,
      start: start,
      targetEnd: end,
      seed: 7,
    );

    test('跑完整個要徑,最後一天剛好做完最後一項', () {
      expect(plan, isNotEmpty);
      expect(plan.last.isLast, isTrue);
      expect(plan.last.today.code, seq.items.last.code);
      expect(plan.where((d) => d.isLast), hasLength(1));
    });

    test('每個日曆天都填日報(含週六、週日),日期連續、從開工日開始', () {
      expect(plan.first.date, start);
      for (var i = 1; i < plan.length; i++) {
        expect(
          plan[i].date.difference(plan[i - 1].date).inDays,
          1,
          reason: '${plan[i - 1].date} 到 ${plan[i].date} 中間少了日子',
        );
      }
      expect(plan.any((d) => d.date.weekday == DateTime.sunday), isTrue);
      expect(plan.any((d) => d.date.weekday == DateTime.saturday), isTrue);
    });

    test('不計工期的日子(週末、國定假日、颱風):要徑不前進、原因寫清楚', () {
      final off = plan.where((d) => d.stopped).toList();
      expect(off, isNotEmpty);
      for (final d in off) {
        expect(d.finished, 0, reason: '${d.date} ${d.offReason}');
        expect(d.tomorrow.code, d.today.code);
      }
      // 週末一律不計工期
      for (final d in plan.where(
        (d) =>
            d.date.weekday == DateTime.saturday ||
            d.date.weekday == DateTime.sunday,
      )) {
        expect(d.offReason, isNotNull);
      }
      // 國定假日(平日放假)不計工期:2026-12-25 行憲紀念日是週五。
      final xingxian = plan.firstWhere((d) => d.date == DateTime(2026, 12, 25));
      expect(xingxian.offReason, '國定假日');
      // 颱風天(沒有其他原因時)標成颱風
      final typhoon = plan.where((d) => d.offReason == '颱風');
      expect(typhoon, isNotEmpty);
      for (final d in typhoon) {
        expect(
          d.weatherAm == Weather.typhoon || d.weatherPm == Weather.typhoon,
          isTrue,
        );
      }
    });

    test('只有工作日(週一到週五、非國定假日、非颱風)才推進要徑;豪大雨照常施工', () {
      for (final d in plan.where((d) => d.finished > 0)) {
        expect(d.date.weekday, lessThanOrEqualTo(DateTime.friday));
        expect(SimulationPlan.isNationalHoliday(d.date), isFalse);
        expect(d.offReason, isNull);
      }
      final heavy = plan.where(
        (d) =>
            (d.weatherAm == Weather.heavyRain ||
                d.weatherPm == Weather.heavyRain) &&
            d.offReason == null,
      );
      expect(heavy, isNotEmpty);
    });

    test('今日要徑絕不早於昨天的今日要徑;明日要徑絕不早於今日', () {
      int idx(String code) => seq.items.indexWhere((i) => i.code == code);
      for (var i = 0; i < plan.length; i++) {
        expect(
          idx(plan[i].tomorrow.code),
          greaterThanOrEqualTo(idx(plan[i].today.code)),
        );
        if (i > 0) {
          expect(
            idx(plan[i].today.code),
            greaterThanOrEqualTo(idx(plan[i - 1].today.code)),
          );
          expect(
            idx(plan[i].today.code),
            greaterThanOrEqualTo(idx(plan[i - 1].tomorrow.code)),
          );
        }
      }
    });

    test('有「一天做完兩項」的日子(今天已經在後面的項目)', () {
      expect(plan.any((d) => d.finished == 2), isTrue);
    });

    test('完工日接近預定完工日(依預定完工日推算工期,不是亂跑)', () {
      final days = plan.last.date.difference(end).inDays;
      expect(days.abs(), lessThanOrEqualTo(60), reason: '模擬完工 ${plan.last.date}');
      expect(plan.length, inInclusiveRange(120, 260));
    });

    test('對著合約完工日(2027-06-30,161 個工作天)推算:完工日接近它,且計入的工作天接近 161 減去颱風', () {
      final contractEnd = DateTime(2027, 6, 30);
      expect(SimulationPlan.countWorkdays(DateTime(2026, 11, 1), contractEnd), 161);
      for (final seed in [1, 2, 3]) {
        final p = SimulationPlan.generate(
          sequence: seq,
          start: start,
          targetEnd: contractEnd,
          seed: seed,
        );
        final gap = p.last.date.difference(contractEnd).inDays;
        expect(gap.abs(), lessThanOrEqualTo(60), reason: 'seed $seed 完工 ${p.last.date}');
        final counted = p.where((d) => d.offReason == null).length;
        expect(counted, inInclusiveRange(120, 175), reason: 'seed $seed');
      }
    });

    test('同樣的種子產生同樣的計畫;空的順序沒有計畫', () {
      final again = SimulationPlan.generate(
        sequence: seq,
        start: start,
        targetEnd: end,
        seed: 7,
      );
      expect(again.length, plan.length);
      expect(again.last.date, plan.last.date);
      expect(
        SimulationPlan.generate(sequence: _seq(0), start: start),
        isEmpty,
      );
    });

    test('工作日計算:2026 年底(行憲紀念日連假)與一般週別', () {
      // 2026-12-21(一)~12-27(日):12-25~27 連假,工作日只有 21~24 共 4 天。
      expect(
        SimulationPlan.countWorkdays(DateTime(2026, 12, 21), DateTime(2026, 12, 27)),
        4,
      );
      // 2026-11-02(一)~11-08(日):5 個工作日。
      expect(
        SimulationPlan.countWorkdays(DateTime(2026, 11, 2), DateTime(2026, 11, 8)),
        5,
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
