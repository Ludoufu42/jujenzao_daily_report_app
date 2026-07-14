import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../db/report_repository.dart';
import '../../models/critical_path.dart';
import '../../models/inspection_checklist.dart';
import '../../theme.dart';
import '../../wizard/report_draft.dart';
import 'critical_path_inspection_screen.dart';

class StepTodayProgress extends StatefulWidget {
  final VoidCallback onNext;
  final VoidCallback onBack;

  const StepTodayProgress({
    super.key,
    required this.onNext,
    required this.onBack,
  });

  @override
  State<StepTodayProgress> createState() => _StepTodayProgressState();
}

class _StepTodayProgressState extends State<StepTodayProgress> {
  final _repo = ReportRepository.instance;
  late final ReportDraft _draft;
  late final TextEditingController _controller;
  late final List<CriticalPathStep> _criticalPathSteps;

  bool _loadingLock = true;
  // Null while free-choice; non-null (and equal to the locked label) once
  // rule 3 applies — the dropdown then only ever offers this one option.
  String? _lockedToPath;
  // True when the lock above is not the normal "advance to what was planned"
  // case, but a forced roll-back because the previous report's 要徑 was never
  // actually inspected.
  bool _lockedBecauseUninspected = false;

  CriticalPathStep? _findStep(String label) {
    for (final s in _criticalPathSteps) {
      if (s.label == label) return s;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _draft = context.read<ReportDraft>();
    _controller = TextEditingController(text: _draft.todayProgress);
    _draft.addListener(_syncFromDraft);
    _criticalPathSteps = generateCriticalPathSteps(_draft.project);
    _resolveLock();
  }

  Future<void> _resolveLock() async {
    // Editing an existing report, or already resolved earlier this session
    // (e.g. returning to this step after going "上一頁") — trust whatever is
    // already on the draft rather than re-deriving it.
    if (_draft.todayCriticalPath != null) {
      setState(() => _loadingLock = false);
      return;
    }

    final previous = await _repo.getMostRecentReportBefore(
      _draft.project.id!,
      _draft.reportDate,
    );
    if (!mounted) return;

    if (previous != null) {
      final previousToday = previous.todayCriticalPath;
      final previousStep =
          previousToday != null ? _findStep(previousToday) : null;
      final requiredInspection =
          previousStep != null && templateForWorkItem(previousStep.secondHalf) != null;

      if (requiredInspection) {
        final inspected = await _repo.getLatestInspectionFor(
          _draft.project.id!,
          previousToday!,
        );
        if (!mounted) return;
        if (inspected == null) {
          // The previous report's 要徑 was never inspected — force this
          // report back onto that same step (instead of advancing to
          // whatever it planned as tomorrow's) until it's inspected.
          _lockedToPath = previousToday;
          _lockedBecauseUninspected = true;
          _draft.todayCriticalPath = _lockedToPath;
          _draft.touch();
          setState(() => _loadingLock = false);
          return;
        }
      }

      if (previous.tomorrowCriticalPath != null) {
        // Rule 3: not the project's first report — today's 要徑 is locked to
        // whatever the previous report planned as tomorrow's.
        _lockedToPath = previous.tomorrowCriticalPath;
        _draft.todayCriticalPath = _lockedToPath;
        _draft.touch();
      }
      // else: previous report never set a tomorrowCriticalPath — leave it as
      // a free choice.
    }
    // else: rule 1 — project's very first report — leave it as a free choice.
    setState(() => _loadingLock = false);
  }

  void _syncFromDraft() {
    if (_controller.text != _draft.todayProgress) {
      _controller.text = _draft.todayProgress;
    }
  }

  @override
  void dispose() {
    _draft.removeListener(_syncFromDraft);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StepCard(
      stepNumber: 3,
      title: '今日進度',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('目前主要徑', style: TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: _lockedToPath != null
                        ? AppColors.pageBackground
                        : Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: _loadingLock
                      ? const Center(
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            hint: const Text('請選擇要徑'),
                            value: _draft.todayCriticalPath,
                            items: _criticalPathSteps
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
                            // Locked once rule 3 applies — this step is only
                            // a free choice on the project's first report.
                            onChanged: _lockedToPath != null
                                ? null
                                : (v) {
                                    setState(() => _draft.todayCriticalPath = v);
                                    _draft.touch();
                                  },
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 48,
                child: OutlinedButton(
                  onPressed: () {
                    final selectedLabel = _draft.todayCriticalPath;
                    if (selectedLabel == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('請先選擇目前主要徑')),
                      );
                      return;
                    }
                    final step = _criticalPathSteps.firstWhere(
                      (s) => s.label == selectedLabel,
                    );
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => CriticalPathInspectionScreen(
                          project: _draft.project,
                          criticalPathLabel: step.label,
                          workItemName: step.secondHalf,
                        ),
                      ),
                    );
                  },
                  child: const Text('要徑查驗'),
                ),
              ),
            ],
          ),
          if (_lockedToPath != null) ...[
            const SizedBox(height: 4),
            Text(
              _lockedBecauseUninspected
                  ? '前一個要徑「$_lockedToPath」尚未完成查驗，今日要徑已鎖定於此，請完成查驗後才能繼續下一步'
                  : '依前一份報表規劃，今日要徑已鎖定，不可自行更改',
              style: TextStyle(
                fontSize: 12,
                color: _lockedBecauseUninspected
                    ? Colors.red
                    : AppColors.textSecondary,
                fontWeight: _lockedBecauseUninspected
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
            ),
          ],
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            maxLines: 8,
            decoration: const InputDecoration(hintText: '請輸入今日施工內容、進度、問題與處理事項'),
            onChanged: (v) => _draft.todayProgress = v,
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
