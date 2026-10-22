import 'dart:math';

import '../models/weather.dart';
import '../models/work_sequence.dart';

/// 貝塔版模擬的「某一天」:這天的天氣、今日要徑、明日要徑。
class SimDay {
  final DateTime date;
  final Weather weatherAm;
  final Weather weatherPm;

  /// 豪大雨/颱風:這天停工,進度不前進。
  final bool stopped;
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
    required this.stopped,
    required this.today,
    required this.tomorrow,
    required this.finished,
    required this.isLast,
  });
}

/// 依工程管理的要徑順序,產生整個專案一天一天的施工計畫(純邏輯,不碰資料庫與網路)。
///
/// 模型(貝塔測試用,數字是假設):
/// - 週日不施工、不填日報;週一到週六每天填。
/// - 天氣隨機;豪大雨與颱風當天停工,進度不前進(日報照填)。
/// - 每個要徑項目要做 1~6 天(放樣、灌漿 1 天),做完換下一項;約一成的日子
///   一天做完兩項(今天已經在後面的項目)。
/// - 今日要徑只會是昨天的今日要徑或它後面的;明日要徑只會是今日或它後面的。
class SimulationPlan {
  static List<SimDay> generate({
    required WorkSequence sequence,
    required DateTime start,
    int seed = 1,
    int maxDays = 600,
  }) {
    final items = sequence.items;
    if (items.isEmpty) return const [];
    final rng = Random(seed);
    final days = <SimDay>[];

    int duration(WorkItem item) {
      if (item.name.contains('灌漿') || item.name.contains('放樣')) return 1;
      return 2 + rng.nextInt(5);
    }

    Weather weather() {
      final r = rng.nextDouble();
      if (r < 0.45) return Weather.sunny;
      if (r < 0.75) return Weather.cloudy;
      if (r < 0.90) return Weather.rainy;
      if (r < 0.97) return Weather.heavyRain;
      return Weather.typhoon;
    }

    var cur = 0;
    var remaining = duration(items[0]);
    var date = DateTime(start.year, start.month, start.day);
    while (cur < items.length && days.length < maxDays) {
      if (date.weekday == DateTime.sunday) {
        date = date.add(const Duration(days: 1));
        continue;
      }
      final am = weather();
      final pm = weather();
      final stopped = _heavy(am) || _heavy(pm);
      var todayIdx = cur;
      var finished = 0;
      if (!stopped) {
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
      final tomorrowIdx = min(cur, items.length - 1);
      days.add(
        SimDay(
          date: date,
          weatherAm: am,
          weatherPm: pm,
          stopped: stopped,
          today: items[min(todayIdx, items.length - 1)],
          tomorrow: items[max(tomorrowIdx, min(todayIdx, items.length - 1))],
          finished: finished,
          isLast: isLast,
        ),
      );
      date = date.add(const Duration(days: 1));
    }
    return days;
  }

  static bool _heavy(Weather w) =>
      w == Weather.heavyRain || w == Weather.typhoon;
}
