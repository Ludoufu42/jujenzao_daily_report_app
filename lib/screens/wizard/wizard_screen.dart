import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../db/report_repository.dart';
import '../../models/project.dart';
import '../../theme.dart';
import '../../wizard/report_draft.dart';
import 'step_date_weather.dart';
import 'step_entries.dart';
import 'step_photos.dart';
import 'step_preview.dart';
import 'step_today_progress.dart';
import 'step_tomorrow_progress.dart';

class WizardScreen extends StatefulWidget {
  final Project project;
  const WizardScreen({super.key, required this.project});

  @override
  State<WizardScreen> createState() => _WizardScreenState();
}

class _WizardScreenState extends State<WizardScreen> {
  late final ReportDraft _draft = ReportDraft(widget.project);
  int _step = 2;

  @override
  void initState() {
    super.initState();
    // "新增日報" always opens on today's date by default — if today already
    // has a filed report, load it for editing instead of risking a second,
    // duplicate report for the same day.
    ReportRepository.instance
        .getReportByDate(widget.project.id!, _draft.reportDate)
        .then((existing) async {
      if (existing == null || !mounted) return;
      final repo = ReportRepository.instance;
      final laborEntries = await repo.getLaborEntries(existing.id!);
      final materialEntries = await repo.getMaterialEntries(existing.id!);
      final equipmentEntries = await repo.getEquipmentEntries(existing.id!);
      final photos = await repo.getReportPhotos(existing.id!);
      if (!mounted) return;
      _draft.loadExistingReport(
        report: existing,
        laborEntriesData: laborEntries,
        materialEntriesData: materialEntries,
        equipmentEntriesData: equipmentEntries,
        photos: photos,
      );
    });
  }

  void _goNext() => setState(() => _step++);

  void _goBack() {
    if (_step == 2) {
      Navigator.of(context).pop();
    } else {
      setState(() => _step--);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _draft,
      child: Scaffold(
        backgroundColor: AppColors.pageBackground,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppHeader(onReset: _resetHandlerForStep(_step)),
                const SizedBox(height: 16),
                _buildStep(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  VoidCallback _resetHandlerForStep(int step) {
    switch (step) {
      case 2:
        return () => _draft.resetDateWeather();
      case 3:
        return () => _draft.resetTodayProgress();
      case 4:
        return () => _draft.resetTomorrowProgressAndNotes();
      case 5:
        return () => _draft.resetEntries();
      case 6:
        return () => _draft.resetPhotos();
      default:
        return () {};
    }
  }

  Widget _buildStep() {
    switch (_step) {
      case 2:
        return StepDateWeather(onNext: _goNext, onBack: _goBack);
      case 3:
        return StepTodayProgress(onNext: _goNext, onBack: _goBack);
      case 4:
        return StepTomorrowProgress(onNext: _goNext, onBack: _goBack);
      case 5:
        return StepEntries(onNext: _goNext, onBack: _goBack);
      case 6:
        return StepPhotos(onNext: _goNext, onBack: _goBack);
      case 7:
        return StepPreview(onBack: _goBack);
      default:
        return const SizedBox.shrink();
    }
  }
}
