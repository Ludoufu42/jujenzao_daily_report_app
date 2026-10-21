import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../db/report_repository.dart';
import '../../models/work_sequence.dart';
import '../../services/cloud_report_sync.dart';
import '../../models/inspection_checklist.dart';
import '../../theme.dart';
import '../../widgets/work_dropdown.dart';
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
  bool _loadingLock = true;
  // Null while free-choice; non-null (and equal to the locked 工項代號) once
  // rule 3 applies — the dropdown then only ever offers this one option.
  String? _lockedToPath;
  // True when the lock above is not the normal "advance to what was planned"
  // case, but a forced roll-back because the previous report's 要徑 was never
  // actually inspected.
  bool _lockedBecauseUninspected = false;

  bool _resolveStarted = false;

  WorkSequence? get _sequence => _draft.sequence;

  String _nameOf(String code) => _sequence?.byCode(code)?.label ?? code;

  @override
  void initState() {
    super.initState();
    _draft = context.read<ReportDraft>();
    _controller = TextEditingController(text: _draft.todayProgress);
    _draft.addListener(_syncFromDraft);
    _maybeResolveLock();
  }

  /// 要等雲端的要徑順序下載完(或確定沒有)才能判斷鎖定。
  void _maybeResolveLock() {
    if (_resolveStarted || _draft.sequenceLoading) return;
    _resolveStarted = true;
    _resolveLock();
  }

  /// 昨天(前一份日報)的今日要徑:今日要徑只能是它或它後面的,絕不會是更早的。
  String? _floorCode;

  Future<void> _resolveLock() async {
    if (_sequence == null) {
      setState(() => _loadingLock = false);
      return;
    }
    final previous = await CloudReportSync().previousReport(
      _draft.project,
      _draft.reportDate,
    );
    if (!mounted) return;
    _floorCode = previous?.todayWorkCode;

    // 前一份日報的要徑如果必須查驗、卻沒有查驗紀錄,今日要徑就鎖在同一項,
    // 完成查驗才能往下。別支手機送的日報在本機查不到查驗紀錄,不拿來判斷。
    if (_draft.todayWorkCode == null &&
        previous != null &&
        !previous.fromCloud) {
      final previousToday = previous.todayWorkCode;
      final previousStep = _sequence!.byCode(previousToday);
      final requiredInspection =
          previousStep != null && templateForWorkItem(previousStep.name) != null;
      if (requiredInspection) {
        final inspected = await _repo.getLatestInspectionFor(
          _draft.project.id!,
          previousToday!,
        );
        if (!mounted) return;
        if (inspected == null) {
          _lockedToPath = previousToday;
          _lockedBecauseUninspected = true;
          _draft.todayWorkCode = _lockedToPath;
          _draft.todayWorkVer = _sequence!.ver;
          _draft.touch();
        }
      }
    }
    setState(() => _loadingLock = false);
  }

  void _syncFromDraft() {
    _maybeResolveLock();
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
                  child: (_loadingLock || _draft.sequenceLoading)
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
                            hint: Text(
                              _sequence == null ? '尚無要徑順序' : '請選擇要徑',
                            ),
                            value: _draft.todayWorkCode,
                            items: workDropdownItems(
                              _sequence,
                              _draft.todayWorkCode,
                              only: _sequence?.itemsFrom(_floorCode),
                            ),
                            // Locked once rule 3 applies — this step is only
                            // a free choice on the project's first report.
                            onChanged: _lockedToPath != null
                                ? null
                                : (v) {
                                    setState(() {
                                      _draft.todayWorkCode = v;
                                      _draft.todayWorkVer = _sequence?.ver;
                                    });
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
                    final selectedCode = _draft.todayWorkCode;
                    if (selectedCode == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('請先選擇目前主要徑')),
                      );
                      return;
                    }
                    final step = _sequence?.byCode(selectedCode);
                    if (step == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('目前的要徑順序找不到這個工項')),
                      );
                      return;
                    }
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => CriticalPathInspectionScreen(
                          project: _draft.project,
                          workCode: step.code,
                          workItemName: step.name,
                        ),
                      ),
                    );
                  },
                  child: const Text('要徑查驗'),
                ),
              ),
            ],
          ),
          SequenceStatusLine(
            sequence: _sequence,
            loading: _draft.sequenceLoading,
            fromCache: _draft.sequenceFromCache,
            error: _draft.sequenceError,
          ),
          if (_floorCode != null && _sequence?.byCode(_floorCode) != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '今日要徑只能是昨天的「${_nameOf(_floorCode!)}」或它後面的項目',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          if (_lockedToPath != null) ...[
            const SizedBox(height: 4),
            Text(
              _lockedBecauseUninspected
                  ? '前一個要徑「${_nameOf(_lockedToPath!)}」尚未完成查驗，今日要徑已鎖定於此，請完成查驗後才能繼續下一步'
                  : '',
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
