/// Official Taiwan government-agency holiday calendar (行政院人事行政總處
/// 辦公日曆表), used to exclude 國定假日 when a project tracks 工作天.
///
/// This can only be sourced from the government's actual yearly
/// announcement — lunar-based holidays (春節, 端午, 中秋) shift every year
/// and cannot be computed, and Taiwan typically only publishes next year's
/// calendar a few months in advance. Add each new year's dates here once
/// DGPA (dgpa.gov.tw) publishes them; projects spanning years not listed
/// here simply won't have those later years' holidays excluded.
library;

const Map<int, List<String>> kTaiwanHolidaysByYear = {
  2026: [
    // 元旦
    '2026-01-01', '2026-01-02', '2026-01-03', '2026-01-04',
    // 農曆春節
    '2026-02-14', '2026-02-15', '2026-02-16', '2026-02-17', '2026-02-18',
    '2026-02-19', '2026-02-20', '2026-02-21', '2026-02-22',
    // 228和平紀念日
    '2026-02-27', '2026-02-28', '2026-03-01',
    // 兒童節暨民族掃墓節
    '2026-04-03', '2026-04-04', '2026-04-05', '2026-04-06',
    // 勞動節
    '2026-05-01', '2026-05-02', '2026-05-03',
    // 端午節
    '2026-06-19', '2026-06-20', '2026-06-21',
    // 中秋節暨教師節
    '2026-09-25', '2026-09-26', '2026-09-27', '2026-09-28',
    // 國慶日
    '2026-10-09', '2026-10-10', '2026-10-11',
    // 臺灣光復暨古寧頭大捷紀念日
    '2026-10-24', '2026-10-25', '2026-10-26',
    // 行憲紀念日
    '2026-12-25', '2026-12-26', '2026-12-27',
  ],
  2027: [
    // 元旦
    '2027-01-01', '2027-01-02', '2027-01-03',
    // 農曆春節（含初一初二補假 2/9-2/10）
    '2027-02-04', '2027-02-05', '2027-02-06', '2027-02-07', '2027-02-08',
    '2027-02-09', '2027-02-10',
    // 228和平紀念日
    '2027-02-27', '2027-02-28', '2027-03-01',
    // 兒童節暨民族掃墓節
    '2027-04-03', '2027-04-04', '2027-04-05', '2027-04-06',
    // 勞動節
    '2027-04-30', '2027-05-01', '2027-05-02',
    // 端午節（平日，無連假）
    '2027-06-09',
    // 中秋節（平日，無連假）
    '2027-09-15',
    // 教師節（平日，無連假）
    '2027-09-28',
    // 國慶日
    '2027-10-09', '2027-10-10', '2027-10-11',
    // 臺灣光復暨古寧頭大捷紀念日
    '2027-10-23', '2027-10-24', '2027-10-25',
    // 行憲紀念日
    '2027-12-24', '2027-12-25', '2027-12-26',
  ],
};

final Set<String> _kTaiwanHolidayDateStrings = {
  for (final dates in kTaiwanHolidaysByYear.values) ...dates,
};

bool isTaiwanNationalHoliday(DateTime date) {
  final key =
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
  return _kTaiwanHolidayDateStrings.contains(key);
}

/// Years for which we actually have official holiday data — surfaced in the
/// UI so users know a project's 工作天 count may be incomplete once it runs
/// past the last year we have data for.
Set<int> get availableHolidayYears => kTaiwanHolidaysByYear.keys.toSet();
