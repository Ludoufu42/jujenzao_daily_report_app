import 'package:intl/intl.dart';

import '../wizard/report_draft.dart';
import '../wizard/report_preview_data.dart';
import 'cloud_report_sync.dart';
import 'cloud_service.dart';

/// 日報上傳雲端的內容(`daily-report/1`)。要徑只存工項固定代號 + 版本號,
/// 不存名稱(名稱在 R2 的要徑順序交付包裡,用代號 + 版本對得上)。
Map<String, Object?> buildReportPayload(
  ReportDraft draft,
  ReportPreviewData data,
) {
  final project = draft.project;
  return {
    'schema': 'daily-report/2',
    'bundle_ver': draft.sequence?.ver,
    'project_id': project.platformProjectId,
    'project_name': project.name,
    'report_date': DateFormat('yyyy-MM-dd').format(draft.reportDate),
    'uploaded_at': DateTime.now().toIso8601String(),
    'is_backfill': draft.isBackfillEntry,
    'weather_am': draft.weatherAm.name,
    'weather_pm': draft.weatherPm.name,
    'is_rain_or_holiday': draft.isRainOrHoliday,
    'today_work': {'code': draft.todayWorkCode, 'ver': draft.todayWorkVer},
    'tomorrow_work': {
      'code': draft.tomorrowWorkCode,
      'ver': draft.tomorrowWorkVer,
    },
    'today_progress': draft.todayProgress,
    'tomorrow_progress': draft.tomorrowProgress,
    'notes': draft.notes,
    'photo_count': draft.photoPaths.length,
    'labor': [
      for (final r in data.laborRows)
        {
          'category': r.tradeType.category,
          'name': r.tradeType.name,
          'morning': r.morning,
          'afternoon': r.afternoon,
          'today_total': r.todayTotal,
          'cumulative': r.cumulative,
          'is_subcontracted': r.isSubcontracted,
          'vendor': r.vendor,
          'today_content': r.todayContent,
          'tomorrow_content': r.tomorrowContent,
        },
    ],
    'materials': [
      for (final r in data.materialRows)
        {
          'category': r.tradeType.category,
          'name': r.tradeType.name,
          'unit': r.tradeType.unit,
          'quantity': r.quantity,
          'cumulative': r.cumulative,
          'usage_location': r.usageLocation,
        },
    ],
    'equipment': [
      for (final r in data.equipmentRows)
        {
          'category': r.tradeType.category,
          'name': r.tradeType.name,
          'unit': r.tradeType.unit,
          'quantity': r.quantity,
          'cumulative': r.cumulative,
          'is_subcontracted': r.isSubcontracted,
          'vendor': r.vendor,
          'today_content': r.todayContent,
          'tomorrow_content': r.tomorrowContent,
        },
    ],
  };
}

/// 把存好的日報上傳 R2。回傳給畫面顯示的結果文字。
Future<String> uploadReportToCloud(
  ReportDraft draft,
  ReportPreviewData data,
) async {
  final pid = draft.project.platformProjectId;
  if (pid == null) return '已儲存日報（這個專案不是從工程管理推播來的，未上傳雲端）';
  try {
    final payload = buildReportPayload(draft, data);
    final date = payload['report_date'] as String;
    final rev = await CloudService.instance.uploadReport(pid, date, payload);
    // 記下這份日報在雲端的修訂號,之後開日報才知道雲端有沒有比本機更新的。
    await CloudReportSync().recordRev(pid, date, rev);
    return '已儲存日報並上傳雲端（第 $rev 次送出）';
  } on CloudException catch (e) {
    return '已儲存日報，但雲端上傳失敗：${e.message}';
  } catch (e) {
    return '已儲存日報，但雲端上傳失敗（$e）';
  }
}
