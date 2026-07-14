import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../db/report_repository.dart';
import '../../models/critical_path.dart';
import '../../models/inspection_checklist.dart';
import '../../theme.dart';
import '../../wizard/report_draft.dart';

class StepTomorrowProgress extends StatefulWidget {
  final VoidCallback onNext;
  final VoidCallback onBack;

  const StepTomorrowProgress({
    super.key,
    required this.onNext,
    required this.onBack,
  });

  @override
  State<StepTomorrowProgress> createState() => _StepTomorrowProgressState();
}

class _StepTomorrowProgressState extends State<StepTomorrowProgress> {
  final _repo = ReportRepository.instance;
  late final ReportDraft _draft;
  late final TextEditingController _progressController;
  late final TextEditingController _notesController;
  late final List<CriticalPathStep> _criticalPathSteps;
  bool _checkingInspection = false;

  @override
  void initState() {
    super.initState();
    _draft = context.read<ReportDraft>();
    _progressController = TextEditingController(text: _draft.tomorrowProgress);
    _notesController = TextEditingController(text: _draft.notes);
    _draft.addListener(_syncFromDraft);
    _criticalPathSteps = generateCriticalPathSteps(_draft.project);
  }

  void _syncFromDraft() {
    if (_progressController.text != _draft.tomorrowProgress) {
      _progressController.text = _draft.tomorrowProgress;
    }
    if (_notesController.text != _draft.notes) {
      _notesController.text = _draft.notes;
    }
  }

  @override
  void dispose() {
    _draft.removeListener(_syncFromDraft);
    _progressController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  /// Rule 2: 明日要徑 can only be today's 要徑 itself (still working on it) or
  /// the very next 要徑 after it (today's finished, moving on).
  List<CriticalPathStep> get _allowedOptions {
    final today = _draft.todayCriticalPath;
    if (today == null) return _criticalPathSteps;
    final current = _criticalPathSteps.where((s) => s.label == today);
    final next = nextCriticalPathStep(_criticalPathSteps, today);
    return [...current, ?next];
  }

  @override
  Widget build(BuildContext context) {
    final options = _allowedOptions;
    // If today's selection was cleared/changed since a tomorrow choice was
    // made, drop a now-invalid tomorrow selection rather than show a value
    // that isn't one of the current dropdown items.
    if (_draft.tomorrowCriticalPath != null &&
        !options.any((s) => s.label == _draft.tomorrowCriticalPath)) {
      _draft.tomorrowCriticalPath = null;
    }

    return StepCard(
      stepNumber: 4,
      title: '明日進度',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('明日要徑', style: TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                hint: const Text('請選擇要徑'),
                value: _draft.tomorrowCriticalPath,
                items: options
                    .map(
                      (s) => DropdownMenuItem(
                        value: s.label,
                        child: Text(
                          '${s.number}. ${s.label}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  setState(() {
                    _draft.tomorrowCriticalPath = v;
                  });
                  _draft.touch();
                },
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '明日要徑只能選今日要徑本身，或今日要徑的下一項',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _progressController,
            maxLines: 6,
            decoration: const InputDecoration(hintText: '請輸入明日預計施工內容'),
            onChanged: (v) => _draft.tomorrowProgress = v,
          ),
          const SizedBox(height: 16),
          const Text('備註', style: TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          TextField(
            controller: _notesController,
            maxLines: 6,
            decoration: const InputDecoration(hintText: '交辦事項與重要事項'),
            onChanged: (v) => _draft.notes = v,
          ),
          const SizedBox(height: 20),
          SecondaryButton(label: '上一頁', onPressed: widget.onBack),
          const SizedBox(height: 8),
          PrimaryButton(
            label: '完成',
            onPressed: _checkingInspection ? null : _handleFinish,
          ),
        ],
      ),
    );
  }

  CriticalPathStep? _findStep(String label) {
    for (final s in _criticalPathSteps) {
      if (s.label == label) return s;
    }
    return null;
  }

  Future<void> _handleFinish() async {
    final today = _draft.todayCriticalPath;
    final tomorrow = _draft.tomorrowCriticalPath;

    if (today != null && tomorrow != null && tomorrow != today) {
      final todayStep = _findStep(today);
      final requiresInspection =
          todayStep != null && templateForWorkItem(todayStep.secondHalf) != null;

      if (requiresInspection) {
        setState(() => _checkingInspection = true);
        final inspected = await _repo.getLatestInspectionFor(
          _draft.project.id!,
          today,
        );
        if (!mounted) return;
        setState(() => _checkingInspection = false);

        if (inspected == null) {
          final proceedAnyway = await _showSkipInspectionWarning(today);
          if (proceedAnyway != true) return;
        }
      }
    }

    widget.onNext();
  }

  Future<bool?> _showSkipInspectionWarning(String label) async {
    final confirmedSkip = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 32),
            SizedBox(width: 8),
            Expanded(child: Text('尚未完成要徑查驗')),
          ],
        ),
        content: Text(
          '目前要徑「$label」尚未完成查驗，直接前往下一個要徑會被視為跳過查驗。'
          '確定要跳過嗎？',
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          Row(
            children: [
              Expanded(
                child: SecondaryButton(
                  label: '返回填寫查驗',
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('確認跳過'),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (confirmedSkip != true || !mounted) return confirmedSkip;
    return _showSkipEasterEgg();
  }

  Future<bool> _showSkipEasterEgg() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320, maxHeight: 320),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset(
                  'assets/easter_egg/fangzhang.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '你這次有大麻煩了，方丈為人很小器的!!',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('跳過'),
          ),
        ],
      ),
    );
    return result ?? true;
  }
}
