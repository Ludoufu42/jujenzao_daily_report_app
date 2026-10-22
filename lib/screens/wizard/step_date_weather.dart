import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../db/report_repository.dart';
import '../../models/weather.dart';
import '../../services/app_clock.dart';
import '../../services/cloud_report_sync.dart';
import '../../theme.dart';
import '../../wizard/report_draft.dart';

class StepDateWeather extends StatefulWidget {
  final VoidCallback onNext;
  final VoidCallback onBack;

  const StepDateWeather({
    super.key,
    required this.onNext,
    required this.onBack,
  });

  @override
  State<StepDateWeather> createState() => _StepDateWeatherState();
}

class _StepDateWeatherState extends State<StepDateWeather> {
  final _repo = ReportRepository.instance;
  bool _checkingDate = false;

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Future<void> _pickDate(ReportDraft draft) async {
    final now = AppClock.now();
    // 專案開工日還沒到時(提早建立的專案),選日期的範圍不能從未來開始,否則會當掉。
    final start = draft.project.startDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: draft.reportDate.isAfter(now) ? now : draft.reportDate,
      firstDate: start.isAfter(now) ? now : start,
      lastDate: now,
      helpText: '選擇日報日期（可選過去日期進行補登或修改）',
    );
    if (picked == null) return;

    setState(() => _checkingDate = true);
    try {
      // 這天雲端上若已有別人(或另一支手機)送出的日報,先載進本機。
      String? cloudNote;
      try {
        cloudNote = (await CloudReportSync()
                .pullIfNewer(draft.project, picked)
                .timeout(const Duration(seconds: 10)))
            .note;
      } catch (_) {}
      final existing = await _repo.getReportByDate(draft.project.id!, picked);
      if (existing == null) {
        draft.startNewReportFor(
          picked,
          isBackfill: !_isSameDay(picked, now),
        );
        if (mounted && !_isSameDay(picked, now)) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('這天還沒有報表，將建立為「補登」報表'),
            ),
          );
        }
      } else {
        final laborEntries = await _repo.getLaborEntries(existing.id!);
        final materialEntries = await _repo.getMaterialEntries(existing.id!);
        final equipmentEntries = await _repo.getEquipmentEntries(existing.id!);
        final photos = await _repo.getReportPhotos(existing.id!);
        draft.loadExistingReport(
          report: existing,
          laborEntriesData: laborEntries,
          materialEntriesData: materialEntries,
          equipmentEntriesData: equipmentEntries,
          photos: photos,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(cloudNote ?? '這天已經有報表，已載入內容供修改')),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _checkingDate = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = context.watch<ReportDraft>();
    final dateFormat = DateFormat('yyyy年M月d日');

    return StepCard(
      stepNumber: 2,
      title: '日報日期與天氣',
      subtitle: '專案：${draft.project.name}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('日報日期', style: TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          InkWell(
            onTap: _checkingDate ? null : () => _pickDate(draft),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: _checkingDate
                  ? const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : Text(
                      dateFormat.format(draft.reportDate),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
            ),
          ),
          if (draft.existingReportId != null) ...[
            const SizedBox(height: 6),
            const Text(
              '修改既有報表：儲存後會覆蓋這天原本的內容',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ] else if (draft.isBackfillEntry) ...[
            const SizedBox(height: 6),
            const Text(
              '補登報表：這天沒有原始紀錄，PDF 會加註「補登」標記',
              style: TextStyle(fontSize: 12, color: AppColors.danger),
            ),
          ],
          const SizedBox(height: 18),
          const Text(
            '上午',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          _WeatherGrid(
            selected: draft.weatherAm,
            onSelect: (w) {
              draft.weatherAm = w;
              draft.touch();
            },
          ),
          const SizedBox(height: 18),
          const Text(
            '下午',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          _WeatherGrid(
            selected: draft.weatherPm,
            onSelect: (w) {
              draft.weatherPm = w;
              draft.touch();
            },
          ),
          const SizedBox(height: 20),
          SecondaryButton(label: '上一頁', onPressed: widget.onBack),
          const SizedBox(height: 8),
          PrimaryButton(label: '完成', onPressed: widget.onNext),
        ],
      ),
    );
  }
}

class _WeatherGrid extends StatelessWidget {
  final Weather selected;
  final ValueChanged<Weather> onSelect;

  const _WeatherGrid({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    const firstRow = [Weather.sunny, Weather.cloudy, Weather.rainy];
    const secondRow = [Weather.heavyRain, Weather.typhoon];

    Widget option(Weather w) {
      final isSelected = w == selected;
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: InkWell(
            onTap: () => onSelect(w),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primary : Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected ? AppColors.primary : AppColors.border,
                ),
              ),
              child: Text(
                w.label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: isSelected ? Colors.white : AppColors.textPrimary,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        Row(children: firstRow.map(option).toList()),
        Row(
          children: [
            ...secondRow.map(option),
            const Expanded(child: SizedBox()),
          ],
        ),
      ],
    );
  }
}
