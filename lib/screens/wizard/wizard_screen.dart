import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../db/report_repository.dart';
import '../../models/project.dart';
import '../../services/cloud_report_sync.dart';
import '../../services/cloud_service.dart';
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
    _loadSequence();
    _loadToday();
  }

  bool _booting = true;

  /// "新增日報" always opens on today's date by default. 一天會填兩次、可能換手機,
  /// 所以先看雲端有沒有今天已送出的日報(比本機新就載進來);本機已經有今天的
  /// 日報就載入修改,避免同一天出現兩份。
  Future<void> _loadToday() async {
    String? note;
    try {
      final outcome = await CloudReportSync()
          .pullIfNewer(widget.project, _draft.reportDate)
          .timeout(const Duration(seconds: 10));
      note = outcome.note;
    } catch (_) {
      // 連不上雲端就用本機的,不擋住填日報。
    }
    final repo = ReportRepository.instance;
    final existing = await repo.getReportByDate(
      widget.project.id!,
      _draft.reportDate,
    );
    if (!mounted) return;
    if (existing != null) {
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
    }
    setState(() => _booting = false);
    if (note != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(note)));
    }
  }

  /// 開日報時從雲端下載工程管理推播的要徑順序(沒網路就用上次的快取)。
  Future<void> _loadSequence() async {
    final pid = widget.project.platformProjectId;
    if (pid == null) {
      _draft.setSequence(null, error: '這個專案不是從工程管理推播來的');
      return;
    }
    final result = await CloudService.instance.fetchBundle(pid);
    if (!mounted) return;
    _draft.setSequence(
      result.bundle?.sequence,
      fromCache: result.fromCache,
      error: result.error,
    );
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
                if (_booting)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(
                      child: Column(
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 12),
                          Text('正在檢查雲端是否已有今天的日報…'),
                        ],
                      ),
                    ),
                  )
                else
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
