import 'dart:math';

import '../models/holiday_calendar.dart';
import '../models/weather.dart';
import '../models/work_sequence.dart';

/// 貝塔版模擬的「某一天」:這天的天氣、今日要徑、明日要徑。
class SimDay {
  final DateTime date;
  final Weather weatherAm;
  final Weather weatherPm;

  /// 不計工期、要徑不前進的原因(週末、國定假日、颱風);null = 這天是工作日。
  /// 這些日子日報照填(週日也可以填),只是不計入工期。
  final String? offReason;
  final WorkItem today;
  final WorkItem tomorrow;

  /// 這天做完幾個要徑項目(0 = 還在做同一項;2 = 一天做完兩項)。
  final int finished;

  /// 專案的最後一個要徑項目在這天完成。
  final bool isLast;

  const SimDay({
    required this.date,
    required this.weatherAm,
    required this.weatherPm,
    required this.offReason,
    required this.today,
    required this.tomorrow,
    required this.finished,
    required this.isLast,
  });

  /// 這天不計工期(要徑不前進)。
  bool get stopped => offReason != null;
}

/// 依工程管理的要徑順序,產生整個專案一天一天的施工計畫(純邏輯,不碰資料庫與網路)。
///
/// 模型(貝塔測試用,數字是假設):
/// - **每個日曆天都填日報**,包含週六、週日與國定假日。
/// - 工期單位是「工作天」(週一到週五):週末、國定假日(人事行政總處行事曆的紅字)
///   與颱風天**不計工期**,這些日子要徑不前進。豪大雨照常施工。
/// - 工作日才推進要徑:每個項目要做 1~N 天(放樣、灌漿 1 天),N 依「預定完工日」
///   推算,讓整個模擬大約在預定完工日前後結束(隨機,會差幾週);約一成的日子一天做完兩項。
/// - 今日要徑只會是昨天的今日要徑或它後面的;明日要徑只會是今日或它後面的。
class SimulationPlan {
  static List<SimDay> generate({
    required WorkSequence sequence,
    required DateTime start,
    DateTime? targetEnd,
    int seed = 1,
    int maxDays = 700,
  }) {
    final items = sequence.items;
    if (items.isEmpty) return const [];
    final rng = Random(seed);
    final days = <SimDay>[];
    final first = DateTime(start.year, start.month, start.day);

    // 灌漿、放樣只要 1 天;其餘項目的平均工作天數,依「預定完工日前的工作日數」扣掉
    // 這些 1 天項目與預期的颱風天後推算,讓整個模擬大約在預定完工日前後結束。
    bool oneDay(WorkItem i) => i.name.contains('灌漿') || i.name.contains('放樣');
    final oneDayCount = items.where(oneDay).length;
    var mean = 3.0;
    if (targetEnd != null && targetEnd.isAfter(first)) {
      final workdays = countWorkdays(first, targetEnd) * 0.96;
      final others = items.length - oneDayCount;
      if (others > 0) mean = max(1.0, (workdays - oneDayCount) / others);
    }
    // 其餘項目的工期在 1~maxDur 之間平均分布,平均 = (maxDur + 1) / 2。
    final maxDur = max(1, (2 * mean - 1).round());

    int duration(WorkItem item) => oneDay(item) ? 1 : 1 + rng.nextInt(maxDur);

    Weather weather() {
      final r = rng.nextDouble();
      if (r < 0.45) return Weather.sunny;
      if (r < 0.75) return Weather.cloudy;
      if (r < 0.92) return Weather.rainy;
      if (r < 0.97) return Weather.heavyRain;
      return Weather.typhoon;
    }

    var cur = 0;
    var remaining = duration(items[0]);
    var date = first;
    while (cur < items.length && days.length < maxDays) {
      final am = weather();
      final pm = weather();
      final typhoon = am == Weather.typhoon || pm == Weather.typhoon;
      final off = typhoon ? '颱風' : offDayReason(date);
      var todayIdx = cur;
      var finished = 0;
      if (off == null) {
        remaining -= 1;
        if (remaining <= 0) {
          finished = 1;
          cur += 1;
          if (cur < items.length) {
            remaining = duration(items[cur]);
            // 一天做完兩項:新的這一項如果很短,有一成機會也當天做完。
            if (rng.nextDouble() < 0.10 &&
                remaining <= 2 &&
                cur + 1 < items.length) {
              finished = 2;
              todayIdx = cur;
              cur += 1;
              remaining = duration(items[cur]);
            }
          }
        }
      }
      final isLast = cur >= items.length;
      final lastIdx = items.length - 1;
      final today = min(todayIdx, lastIdx);
      final tomorrow = max(min(cur, lastIdx), today);
      days.add(
        SimDay(
          date: date,
          weatherAm: am,
          weatherPm: pm,
          offReason: off,
          today: items[today],
          tomorrow: items[tomorrow],
          finished: finished,
          isLast: isLast,
        ),
      );
      date = date.add(const Duration(days: 1));
    }
    return days;
  }

  /// 不是工作日的原因(週末、國定假日);是工作日就回傳 null。颱風另外判斷。
  static String? offDayReason(DateTime d) {
    if (isNationalHoliday(d)) return '國定假日';
    if (d.weekday == DateTime.saturday || d.weekday == DateTime.sunday) {
      return '週末';
    }
    return null;
  }

  static bool isNationalHoliday(DateTime d) {
    final key =
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return kTaiwanHolidaysByYear[d.year]?.contains(key) ?? false;
  }

  /// 從 [from] 到 [to](含)有幾個工作日(週一到週五、不是國定假日)。
  static int countWorkdays(DateTime from, DateTime to) {
    var n = 0;
    var d = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day);
    while (!d.isAfter(end)) {
      if (offDayReason(d) == null) n++;
      d = d.add(const Duration(days: 1));
    }
    return n;
  }
}
