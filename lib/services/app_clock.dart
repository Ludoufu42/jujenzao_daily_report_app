/// App 裡「現在是哪一天」的唯一來源。正式版永遠是真實時間;貝塔版可以
/// 把日期設成模擬的某一天(時分秒仍用真實的),用來在幾分鐘內測完整個專案
/// 一百多天的日報。所有「今天」「補登」「建立時間」都要走這裡,不要直接 DateTime.now()。
class AppClock {
  AppClock._();

  static DateTime? _simulatedDate;

  /// 目前是否在模擬日期(只有貝塔版會設)。
  static bool get isSimulated => _simulatedDate != null;

  static DateTime get simulatedDate => _simulatedDate ?? DateTime.now();

  static DateTime now() {
    final sim = _simulatedDate;
    final real = DateTime.now();
    if (sim == null) return real;
    return DateTime(
      sim.year,
      sim.month,
      sim.day,
      real.hour,
      real.minute,
      real.second,
    );
  }

  /// 設定模擬日期;傳 null 回到真實時間。
  static void simulate(DateTime? date) {
    _simulatedDate = date == null
        ? null
        : DateTime(date.year, date.month, date.day);
  }
}
