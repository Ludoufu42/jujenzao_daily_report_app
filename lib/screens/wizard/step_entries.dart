import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../db/report_repository.dart';
import '../../models/trade_category.dart';
import '../../models/trade_type.dart';
import '../../theme.dart';
import '../../widgets/confirm_dialogs.dart';
import '../../wizard/report_draft.dart';

class StepEntries extends StatefulWidget {
  final VoidCallback onNext;
  final VoidCallback onBack;

  const StepEntries({super.key, required this.onNext, required this.onBack});

  @override
  State<StepEntries> createState() => _StepEntriesState();
}

class _StepEntriesState extends State<StepEntries> {
  final _repo = ReportRepository.instance;
  String _activeCategory = kTradeCategories.first.name;
  bool _managing = false;
  bool _loading = true;
  final Map<String, List<TradeType>> _activeItems = {};
  final Map<String, List<TradeType>> _manageItems = {};

  final _newNameController = TextEditingController();
  final _newUnitController = TextEditingController();

  int get _projectId => context.read<ReportDraft>().project.id!;

  @override
  void initState() {
    super.initState();
    _loadCategory(_activeCategory);
  }

  @override
  void dispose() {
    _newNameController.dispose();
    _newUnitController.dispose();
    super.dispose();
  }

  Future<void> _loadCategory(String category) async {
    setState(() => _loading = true);
    final active = await _repo.getTradeTypes(_projectId, category);
    final all = await _repo.getTradeTypes(
      _projectId,
      category,
      includeDisabledAndDeleted: true,
    );
    setState(() {
      _activeItems[category] = active;
      _manageItems[category] = all;
      _loading = false;
    });
  }

  TradeCategoryDef get _activeDef =>
      kTradeCategories.firstWhere((c) => c.name == _activeCategory);

  Future<void> _addNewItem() async {
    final name = _newNameController.text.trim();
    final unit = _newUnitController.text.trim().isEmpty
        ? '工'
        : _newUnitController.text.trim();
    if (name.isEmpty) return;
    await _repo.addTradeType(
      projectId: _projectId,
      category: _activeCategory,
      type: _activeDef.type,
      name: name,
      unit: unit,
    );
    _newNameController.clear();
    _newUnitController.clear();
    await _loadCategory(_activeCategory);
  }

  Future<void> _toggleStatus(TradeType t) async {
    final newStatus = t.status == TradeStatus.disabled
        ? TradeStatus.active
        : TradeStatus.disabled;
    await _repo.setTradeTypeStatus(t.id!, newStatus);
    await _loadCategory(_activeCategory);
  }

  Future<void> _delete(TradeType t) async {
    final confirmed = await showDeleteTradeTypeConfirmDialog(context, t.name);
    if (!confirmed) return;
    await _repo.setTradeTypeStatus(t.id!, TradeStatus.deleted);
    await _loadCategory(_activeCategory);
  }

  Future<void> _forceDelete(TradeType t) async {
    final confirmed = await showForceDeleteTradeTypeConfirmDialog(
      context,
      t.name,
    );
    if (!confirmed) return;
    await _repo.forceDeleteTradeType(t.id!);
    await _loadCategory(_activeCategory);
  }

  @override
  Widget build(BuildContext context) {
    final draft = context.watch<ReportDraft>();

    return StepCard(
      stepNumber: 5,
      title: '人員、材料、機具紀錄',
      subtitle: '人員類：上午/下午都留空則不出現在報表。材料/機具類：入場數量留空則不出現在報表。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CategoryTabs(
            active: _activeCategory,
            onSelect: (name) {
              setState(() {
                _activeCategory = name;
                _managing = false;
              });
              if (!_activeItems.containsKey(name)) _loadCategory(name);
            },
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _activeCategory,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              ElevatedButton(
                onPressed: () => setState(() => _managing = !_managing),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                ),
                child: Text(_managing ? '收合管理' : '管理項目'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            if (_managing) _buildManagePanel(),
            ..._buildItemRows(draft),
            const Divider(height: 32, color: AppColors.border),
            TextField(
              controller: _newNameController,
              decoration: const InputDecoration(hintText: '新增其他項目'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _newUnitController,
              decoration: const InputDecoration(hintText: '單位'),
            ),
            const SizedBox(height: 10),
            PrimaryButton(label: '增加', onPressed: _addNewItem),
          ],
          const SizedBox(height: 20),
          SecondaryButton(label: '上一頁', onPressed: widget.onBack),
          const SizedBox(height: 8),
          PrimaryButton(label: '完成', onPressed: widget.onNext),
        ],
      ),
    );
  }

  Widget _buildManagePanel() {
    final items = _manageItems[_activeCategory] ?? [];
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      constraints: const BoxConstraints(maxHeight: 320),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(10),
      child: SingleChildScrollView(
        child: Column(
          children: items.map((t) {
            return Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: AppColors.border, width: 0.5),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    t.unit,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => _toggleStatus(t),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 9),
                          ),
                          child: Text(
                            t.status == TradeStatus.disabled ? '顯示' : '停用',
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => _delete(t),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 9),
                          ),
                          child: const Text('刪除'),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => _forceDelete(t),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.dangerBg,
                            foregroundColor: AppColors.danger,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 9),
                          ),
                          child: const Text('強制刪除'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  List<Widget> _buildItemRows(ReportDraft draft) {
    final items = _activeItems[_activeCategory] ?? [];
    final type = _activeDef.type;
    final gen = draft.entriesGeneration;
    return items.map((t) {
      final key = ValueKey('${t.id}_$gen');
      switch (type) {
        case TradeCategoryType.labor:
          return _LaborRow(
            key: key,
            tradeType: t,
            entry: draft.laborFor(t.id!),
            draft: draft,
          );
        case TradeCategoryType.material:
          return _MaterialRow(
            key: key,
            tradeType: t,
            entry: draft.materialFor(t.id!),
            draft: draft,
          );
        case TradeCategoryType.equipment:
          return _EquipmentRow(
            key: key,
            tradeType: t,
            entry: draft.equipmentFor(t.id!),
            draft: draft,
          );
      }
    }).toList();
  }
}

class _CategoryTabs extends StatelessWidget {
  final String active;
  final ValueChanged<String> onSelect;

  const _CategoryTabs({required this.active, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: kTradeCategories.map((c) {
        final isActive = c.name == active;
        return SizedBox(
          width: 160,
          child: ElevatedButton(
            onPressed: () => onSelect(c.name),
            style: ElevatedButton.styleFrom(
              backgroundColor: isActive
                  ? AppColors.primary
                  : AppColors.secondaryBg,
              foregroundColor: isActive ? Colors.white : AppColors.textPrimary,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
            child: Text(c.name, style: const TextStyle(fontSize: 13)),
          ),
        );
      }).toList(),
    );
  }
}

class _LaborRow extends StatelessWidget {
  final TradeType tradeType;
  final LaborDraftEntry entry;
  final ReportDraft draft;

  const _LaborRow({
    super.key,
    required this.tradeType,
    required this.entry,
    required this.draft,
  });

  double get _todayTotal => ((entry.morning ?? 0) + (entry.afternoon ?? 0)) / 2;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.only(bottom: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                flex: 3,
                child: Text(
                  tradeType.name,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
              Expanded(
                child: Text(
                  tradeType.unit,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ),
              Expanded(
                child: TextFormField(
                  initialValue: entry.morning?.toString() ?? '',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(hintText: '上午'),
                  onChanged: (v) {
                    entry.morning = double.tryParse(v);
                    draft.touch();
                  },
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: TextFormField(
                  initialValue: entry.afternoon?.toString() ?? '',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(hintText: '下午'),
                  onChanged: (v) {
                    entry.afternoon = double.tryParse(v);
                    draft.touch();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '本日合計 $_todayTotal ${tradeType.unit}',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Checkbox(
                value: entry.isSubcontracted,
                onChanged: (v) {
                  entry.isSubcontracted = v ?? false;
                  draft.touch();
                },
              ),
              const Text('代工'),
            ],
          ),
          TextFormField(
            initialValue: entry.vendor,
            decoration: const InputDecoration(hintText: '廠商'),
            onChanged: (v) => entry.vendor = v,
          ),
          const SizedBox(height: 8),
          TextFormField(
            initialValue: entry.todayContent,
            maxLines: 2,
            decoration: const InputDecoration(hintText: '今日工作內容'),
            onChanged: (v) => entry.todayContent = v,
          ),
          const SizedBox(height: 8),
          TextFormField(
            initialValue: entry.tomorrowContent,
            maxLines: 2,
            decoration: const InputDecoration(hintText: '明日工作內容'),
            onChanged: (v) => entry.tomorrowContent = v,
          ),
        ],
      ),
    );
  }
}

class _MaterialRow extends StatelessWidget {
  final TradeType tradeType;
  final MaterialDraftEntry entry;
  final ReportDraft draft;

  const _MaterialRow({
    super.key,
    required this.tradeType,
    required this.entry,
    required this.draft,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.only(bottom: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                flex: 3,
                child: Text(
                  tradeType.name,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
              Expanded(
                child: Text(
                  tradeType.unit,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ),
              Expanded(
                child: TextFormField(
                  initialValue: entry.quantity?.toString() ?? '',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(hintText: '入場'),
                  onChanged: (v) {
                    entry.quantity = double.tryParse(v);
                    draft.touch();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextFormField(
            initialValue: entry.usageLocation,
            maxLines: 2,
            decoration: const InputDecoration(hintText: '使用位置'),
            onChanged: (v) => entry.usageLocation = v,
          ),
        ],
      ),
    );
  }
}

class _EquipmentRow extends StatelessWidget {
  final TradeType tradeType;
  final EquipmentDraftEntry entry;
  final ReportDraft draft;

  const _EquipmentRow({
    super.key,
    required this.tradeType,
    required this.entry,
    required this.draft,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.only(bottom: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                flex: 3,
                child: Text(
                  tradeType.name,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
              Expanded(
                child: Text(
                  tradeType.unit,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ),
              Expanded(
                child: TextFormField(
                  initialValue: entry.quantity?.toString() ?? '',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(hintText: '入場'),
                  onChanged: (v) {
                    entry.quantity = double.tryParse(v);
                    draft.touch();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Checkbox(
                value: entry.isSubcontracted,
                onChanged: (v) {
                  entry.isSubcontracted = v ?? false;
                  draft.touch();
                },
              ),
              const Text('代工'),
            ],
          ),
          TextFormField(
            initialValue: entry.vendor,
            decoration: const InputDecoration(hintText: '廠商'),
            onChanged: (v) => entry.vendor = v,
          ),
          const SizedBox(height: 8),
          TextFormField(
            initialValue: entry.todayContent,
            maxLines: 2,
            decoration: const InputDecoration(hintText: '今日工作內容'),
            onChanged: (v) => entry.todayContent = v,
          ),
          const SizedBox(height: 8),
          TextFormField(
            initialValue: entry.tomorrowContent,
            maxLines: 2,
            decoration: const InputDecoration(hintText: '明日工作內容'),
            onChanged: (v) => entry.tomorrowContent = v,
          ),
        ],
      ),
    );
  }
}
