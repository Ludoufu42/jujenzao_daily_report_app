import '../db/report_repository.dart';
import 'report_draft.dart';

/// 把填到一半(或填好)的日報草稿寫進本機資料庫:新的日報就建立,已經有的就覆蓋。
/// 手動填日報(預覽頁)與貝塔版的自動模擬都走這一條,確保測到的是同一套儲存邏輯。
/// 儲存後 [ReportDraft.existingReportId] 會指到這份日報。
Future<void> persistDraft(ReportDraft draft, ReportRepository repo) async {
  final laborInputs = draft.laborEntries.entries
      .map(
        (e) => LaborEntryInput(
          tradeTypeId: e.key,
          morningCount: e.value.morning ?? 0,
          afternoonCount: e.value.afternoon ?? 0,
          isSubcontracted: e.value.isSubcontracted,
          vendor: e.value.vendor,
          todayContent: e.value.todayContent,
          tomorrowContent: e.value.tomorrowContent,
        ),
      )
      .toList();
  final materialInputs = draft.materialEntries.entries
      .map(
        (e) => MaterialEntryInput(
          tradeTypeId: e.key,
          quantity: e.value.quantity ?? 0,
          usageLocation: e.value.usageLocation,
        ),
      )
      .toList();
  final equipmentInputs = draft.equipmentEntries.entries
      .map(
        (e) => EquipmentEntryInput(
          tradeTypeId: e.key,
          quantity: e.value.quantity ?? 0,
          isSubcontracted: e.value.isSubcontracted,
          vendor: e.value.vendor,
          todayContent: e.value.todayContent,
          tomorrowContent: e.value.tomorrowContent,
        ),
      )
      .toList();

  final rainyWeathers = {'rainy', 'heavyRain', 'typhoon'};
  final isRainOrHoliday =
      rainyWeathers.contains(draft.weatherAm.name) ||
      rainyWeathers.contains(draft.weatherPm.name);

  final report = DailyReportBuilder.build(draft, isRainOrHoliday);
  if (draft.existingReportId != null) {
    await repo.updateDailyReportWithEntries(
      report: report,
      laborInputs: laborInputs,
      materialInputs: materialInputs,
      equipmentInputs: equipmentInputs,
      photoPaths: draft.photoPaths,
    );
  } else {
    final newId = await repo.createDailyReportWithEntries(
      report: report,
      laborInputs: laborInputs,
      materialInputs: materialInputs,
      equipmentInputs: equipmentInputs,
      photoPaths: draft.photoPaths,
    );
    draft.existingReportId = newId;
  }
}
