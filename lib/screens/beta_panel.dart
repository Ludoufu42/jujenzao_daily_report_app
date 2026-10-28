import 'package:flutter/material.dart';

import '../models/project.dart';
import '../models/project_bundle.dart';
import '../services/app_clock.dart';
import '../services/cloud_config.dart';
import '../services/cloud_service.dart';
import '../services/report_simulator.dart';
import '../theme.dart';

String _d(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// 貝塔版專用:模擬時鐘面板。只有 `--dart-define=BETA=true` 建置的版本才會出現。
/// 把「今天」調成專案期間的任何一天,再用一般的填日報畫面手動填;
/// 或一鍵自動跑完整個專案(見 [SimulatorScreen])。
class BetaPanel extends StatefulWidget {
  final Project project;
  const BetaPanel({super.key, required this.project});

  @override
  State<BetaPanel> createState() => _BetaPanelState();
}

class _BetaPanelState extends State<BetaPanel> {
  DateTime get _start => widget.project.startDate;

  void _set(DateTime d) => setState(() => AppClock.simulate(d));

  void _addDays(int n) {
    var d = AppClock.simulatedDate.add(Duration(days: n));
    // 「下一個工作日」:跳過週日。
    while (n > 0 && d.weekday == DateTime.sunday) {
      d = d.add(const Duration(days: 1));
    }
    _set(d);
  }

  Future<void> _pick() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: AppClock.simulatedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: '選擇「今天」要模擬成哪一天',
    );
    if (picked != null) _set(picked);
  }

  @override
  Widget build(BuildContext context) {
    final sim = AppClock.isSimulated;
    final start = _start;
    final day = sim
        ? AppClock.simulatedDate.difference(start).inDays + 1
        : null;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E0),
        border: Border.all(color: const Color(0xFFE0A800)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '貝塔測試：${widget.project.name}',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          ),
          const SizedBox(height: 4),
          Text(
            sim
                ? '模擬日期：${_d(AppClock.simulatedDate)}（開工第 $day 天）　開工日 ${_d(start)}'
                : '目前用真實時間　開工日 ${_d(start)}',
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 4),
          const Text(
            '資料送到開發環境,不會進正式的雲端。調好日期後按上面專案的「新增日報」,就是那一天的日報。',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: () => _set(start),
                child: const Text('日期＝開工日'),
              ),
              OutlinedButton(
                onPressed: sim ? () => _addDays(1) : null,
                child: const Text('下一個工作日'),
              ),
              OutlinedButton(
                onPressed: sim ? () => _addDays(7) : null,
                child: const Text('+7 天'),
              ),
              OutlinedButton(onPressed: _pick, child: const Text('選日期')),
              OutlinedButton(
                onPressed: sim
                    ? () => setState(() => AppClock.simulate(null))
                    : null,
                child: const Text('回到真實時間'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ElevatedButton(
            onPressed: () => Navigator.of(context)
                .push(
                  MaterialPageRoute(
                    builder: (_) => SimulatorScreen(project: widget.project),
                  ),
                )
                .then((_) => setState(() {})),
            child: const Text('自動跑完整個專案的日報'),
          ),
        ],
      ),
    );
  }
}

/// 自動跑完整個專案:依要徑順序一天一天填日報、上傳、(選擇)產 PDF。
class SimulatorScreen extends StatefulWidget {
  final Project project;
  const SimulatorScreen({super.key, required this.project});

  @override
  State<SimulatorScreen> createState() => _SimulatorScreenState();
}

class _SimulatorScreenState extends State<SimulatorScreen> {
  ReportSimulator? _sim;
  bool _twoSubmits = true;
  bool _withPdf = true;
  bool _forget = true;
  final _daysController = TextEditingController();
  DateTime? _targetEnd = DateTime.tryParse(CloudConfig.betaTargetEnd);
  String? _prepError;
  bool _preparing = false;

  @override
  void dispose() {
    _daysController.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _preparing = true;
      _prepError = null;
    });
    final pid = widget.project.platformProjectId;
    ProjectBundle? bundle;
    if (pid != null) {
      bundle = (await CloudService.instance.fetchBundle(pid)).bundle;
    }
    if (!mounted) return;
    if (bundle == null) {
      setState(() {
        _preparing = false;
        _prepError = '下載不到這個專案的要徑順序(開發環境還沒有專案包?)';
      });
      return;
    }
    final sim = ReportSimulator(project: widget.project, bundle: bundle);
    setState(() {
      _sim = sim;
      _preparing = false;
    });
    sim.run(
      SimulationOptions(
        twoSubmits: _twoSubmits,
        withPdf: _withPdf,
        maxDays: int.tryParse(_daysController.text.trim()),
        targetEnd: _targetEnd,
        forgetRate: _forget ? 0.04 : 0,
        seed: 5, // 這一組隨機天氣大約在合約完工日前後完工,拿來示範
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sim = _sim;
    return Scaffold(
      appBar: AppBar(title: const Text('自動跑完整個專案')),
      backgroundColor: AppColors.pageBackground,
      body: SafeArea(child: sim == null ? _options() : _progress(sim)),
    );
  }

  Widget _options() => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Text(
        '專案：${widget.project.name}',
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 8),
      const Text(
        '會依工程管理推播的要徑順序,從開工日一天一天填日報(每天都填,含週六、週日)。'
        '工期單位是工作天:週末、國定假日、颱風天不計工期、要徑不前進。'
        '全部送到開發環境,本機資料庫也會寫入這些日報。',
        style: TextStyle(color: AppColors.textSecondary),
      ),
      const SizedBox(height: 12),
      CheckboxListTile(
        value: _twoSubmits,
        onChanged: (v) => setState(() => _twoSubmits = v ?? true),
        title: const Text('每天送出兩次（中午前、下班前）'),
        controlAffinity: ListTileControlAffinity.leading,
      ),
      CheckboxListTile(
        value: _forget,
        onChanged: (v) => setState(() => _forget = v ?? true),
        title: const Text('模擬員工偶爾忘記填日報（約 4%，工期照跑，部分隔幾天補登）'),
        controlAffinity: ListTileControlAffinity.leading,
      ),
      CheckboxListTile(
        value: _withPdf,
        onChanged: (v) => setState(() => _withPdf = v ?? true),
        title: const Text('每天都產生 PDF 並上傳'),
        controlAffinity: ListTileControlAffinity.leading,
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: TextField(
          controller: _daysController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: '只跑前幾天（留空 = 跑完整個專案）'),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _targetEnd == null
                    ? '目標完工日：用工程管理的預定完工日'
                    : '目標完工日：${_d(_targetEnd!)}（工期依它推算）',
              ),
            ),
            TextButton(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _targetEnd ?? DateTime(2027, 6, 30),
                  firstDate: DateTime(2026),
                  lastDate: DateTime(2100),
                  helpText: '模擬要在哪一天前後完工（例如合約最後一天）',
                );
                if (picked != null) setState(() => _targetEnd = picked);
              },
              child: const Text('改'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      if (_prepError != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            _prepError!,
            style: const TextStyle(color: AppColors.danger),
          ),
        ),
      ElevatedButton(
        onPressed: _preparing ? null : _start,
        child: Text(_preparing ? '準備中…' : '開始'),
      ),
    ],
  );

  Widget _progress(ReportSimulator sim) {
    return ListenableBuilder(
      listenable: sim.state,
      builder: (context, _) {
        final s = sim.state;
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s.current,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: s.total == 0 ? null : s.done / s.total,
              ),
              const SizedBox(height: 6),
              Text(
                '${s.done}/${s.total} 天　日報上傳 ${s.jsonOk}（失敗 ${s.jsonFailed}）　'
                'PDF ${s.pdfOk}（失敗 ${s.pdfFailed}）　錯誤 ${s.errors}　'
                '忘記填 ${s.forgot}　補登 ${s.backfilled}　'
                '${s.clock.elapsed.inSeconds} 秒',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (s.running)
                    OutlinedButton(
                      onPressed: sim.cancel,
                      child: const Text('停止'),
                    ),
                  if (s.finished)
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('回首頁'),
                    ),
                ],
              ),
              if (s.summary != null) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(s.summary!),
                ),
              ],
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  reverse: true,
                  itemCount: s.log.length,
                  itemBuilder: (_, i) => Text(
                    s.log[s.log.length - 1 - i],
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
