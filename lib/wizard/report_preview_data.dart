import '../db/report_repository.dart';
import '../models/trade_category.dart';
import '../models/trade_type.dart';
import 'report_draft.dart';

class LaborPreviewRow {
  final TradeType tradeType;
  final double morning;
  final double afternoon;
  final double todayTotal;
  final double cumulative;
  final bool isSubcontracted;
  final String vendor;
  final String todayContent;
  final String tomorrowContent;

  LaborPreviewRow({
    required this.tradeType,
    required this.morning,
    required this.afternoon,
    required this.todayTotal,
    required this.cumulative,
    required this.isSubcontracted,
    required this.vendor,
    required this.todayContent,
    required this.tomorrowContent,
  });
}

class MaterialPreviewRow {
  final TradeType tradeType;
  final double quantity;
  final double cumulative;
  final String usageLocation;

  MaterialPreviewRow({
    required this.tradeType,
    required this.quantity,
    required this.cumulative,
    required this.usageLocation,
  });
}

class EquipmentPreviewRow {
  final TradeType tradeType;
  final double quantity;
  final double cumulative;
  final bool isSubcontracted;
  final String vendor;
  final String todayContent;
  final String tomorrowContent;

  EquipmentPreviewRow({
    required this.tradeType,
    required this.quantity,
    required this.cumulative,
    required this.isSubcontracted,
    required this.vendor,
    required this.todayContent,
    required this.tomorrowContent,
  });
}

class ReportPreviewData {
  final int calendarDays;
  final int remainingDays;
  /// null when the project didn't opt in to tracking 工作天 at creation time.
  final int? workingDays;
  final String weekdayLabel;
  final List<LaborPreviewRow> laborRows;
  final List<MaterialPreviewRow> materialRows;
  final List<EquipmentPreviewRow> equipmentRows;
  final Map<String, double> laborByCategory;

  ReportPreviewData({
    required this.calendarDays,
    required this.remainingDays,
    required this.workingDays,
    required this.weekdayLabel,
    required this.laborRows,
    required this.materialRows,
    required this.equipmentRows,
    required this.laborByCategory,
  });

  static const _weekdayLabels = ['一', '二', '三', '四', '五', '六', '日'];

  static const _rainyWeathers = {'rainy', 'heavyRain', 'typhoon'};

  static Future<ReportPreviewData> build(
    ReportDraft draft,
    ReportRepository repo,
  ) async {
    final project = draft.project;
    final reportDate = draft.reportDate;

    final calendarDays = reportDate.difference(project.startDate).inDays + 1;
    final remainingDays = project.plannedCompletionDate
        .difference(reportDate)
        .inDays;

    int? workingDays;
    if (project.tracksWorkingDays) {
      final todayIsBadWeather =
          _rainyWeathers.contains(draft.weatherAm.name) ||
          _rainyWeathers.contains(draft.weatherPm.name);
      workingDays = await repo.countWorkingDays(
        project: project,
        uptoDate: reportDate,
        uptoDateIsBadWeather: todayIsBadWeather,
      );
    }

    final weekdayLabel = '星期${_weekdayLabels[reportDate.weekday - 1]}';

    // Build id -> TradeType lookup across all 7 categories.
    final allTradeTypes = <int, TradeType>{};
    for (final cat in kTradeCategories) {
      final items = await repo.getTradeTypes(
        project.id!,
        cat.name,
        includeDisabledAndDeleted: true,
      );
      for (final t in items) {
        allTradeTypes[t.id!] = t;
      }
    }

    final laborRows = <LaborPreviewRow>[];
    for (final entry in draft.laborEntries.entries) {
      final morning = entry.value.morning ?? 0;
      final afternoon = entry.value.afternoon ?? 0;
      if (morning <= 0 && afternoon <= 0) continue;
      final tradeType = allTradeTypes[entry.key];
      if (tradeType == null) continue;
      final todayTotal = (morning + afternoon) / 2;
      final prevCumulative = await repo.previousCumulative(
        'labor_entries',
        project.id!,
        entry.key,
        reportDate,
      );
      laborRows.add(
        LaborPreviewRow(
          tradeType: tradeType,
          morning: morning,
          afternoon: afternoon,
          todayTotal: todayTotal,
          cumulative: prevCumulative + todayTotal,
          isSubcontracted: entry.value.isSubcontracted,
          vendor: entry.value.vendor,
          todayContent: entry.value.todayContent,
          tomorrowContent: entry.value.tomorrowContent,
        ),
      );
    }

    final materialRows = <MaterialPreviewRow>[];
    for (final entry in draft.materialEntries.entries) {
      final qty = entry.value.quantity ?? 0;
      if (qty <= 0) continue;
      final tradeType = allTradeTypes[entry.key];
      if (tradeType == null) continue;
      final prevCumulative = await repo.previousCumulative(
        'material_entries',
        project.id!,
        entry.key,
        reportDate,
      );
      materialRows.add(
        MaterialPreviewRow(
          tradeType: tradeType,
          quantity: qty,
          cumulative: prevCumulative + qty,
          usageLocation: entry.value.usageLocation,
        ),
      );
    }

    final equipmentRows = <EquipmentPreviewRow>[];
    for (final entry in draft.equipmentEntries.entries) {
      final qty = entry.value.quantity ?? 0;
      if (qty <= 0) continue;
      final tradeType = allTradeTypes[entry.key];
      if (tradeType == null) continue;
      final prevCumulative = await repo.previousCumulative(
        'equipment_entries',
        project.id!,
        entry.key,
        reportDate,
      );
      equipmentRows.add(
        EquipmentPreviewRow(
          tradeType: tradeType,
          quantity: qty,
          cumulative: prevCumulative + qty,
          isSubcontracted: entry.value.isSubcontracted,
          vendor: entry.value.vendor,
          todayContent: entry.value.todayContent,
          tomorrowContent: entry.value.tomorrowContent,
        ),
      );
    }

    final laborByCategory = <String, double>{};
    for (final row in laborRows) {
      laborByCategory.update(
        row.tradeType.category,
        (v) => v + row.todayTotal,
        ifAbsent: () => row.todayTotal,
      );
    }

    return ReportPreviewData(
      calendarDays: calendarDays,
      remainingDays: remainingDays,
      workingDays: workingDays,
      weekdayLabel: weekdayLabel,
      laborRows: laborRows,
      materialRows: materialRows,
      equipmentRows: equipmentRows,
      laborByCategory: laborByCategory,
    );
  }
}
