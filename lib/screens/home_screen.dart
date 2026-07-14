import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:universal_io/io.dart';

import '../db/report_repository.dart';
import '../models/holiday_calendar.dart';
import '../models/project.dart';
import '../services/backup_service.dart';
import '../services/dropbox_service.dart';
import '../theme.dart';
import '../widgets/confirm_dialogs.dart';
import 'wizard/wizard_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _repo = ReportRepository.instance;
  List<Project> _projects = [];
  bool _showCreateForm = false;
  bool _loading = true;
  bool _busy = false;

  final _nameController = TextEditingController();
  final _companyController = TextEditingController();
  final _siteAreaController = TextEditingController();
  final _basementFloorsController = TextEditingController();
  final _basementFloorAreaController = TextEditingController();
  final _aboveGroundFloorsController = TextEditingController();
  final _typicalFloorAreaController = TextEditingController();
  final _roofFloorsController = TextEditingController();
  final _roofFloorAreaController = TextEditingController();
  DateTime? _startDate;
  DateTime? _plannedCompletionDate;
  bool _tracksWorkingDays = false;
  bool _excludeWeekends = false;
  bool _excludeNationalHolidays = false;
  bool _excludeBadWeather = false;

  @override
  void initState() {
    super.initState();
    _loadProjects();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _companyController.dispose();
    _siteAreaController.dispose();
    _basementFloorsController.dispose();
    _basementFloorAreaController.dispose();
    _aboveGroundFloorsController.dispose();
    _typicalFloorAreaController.dispose();
    _roofFloorsController.dispose();
    _roofFloorAreaController.dispose();
    super.dispose();
  }

  Future<void> _loadProjects() async {
    final projects = await _repo.getProjects();
    setState(() {
      _projects = projects;
      _loading = false;
    });
  }

  Future<void> _exportBackup() async {
    setState(() => _busy = true);
    try {
      final result = await BackupService.instance.exportBackup();
      if (!mounted) return;
      final message = result.uploadedToCloud
          ? '已備份到本機與 Dropbox'
          : (dropboxSetupHint != null
                ? '已備份到本機（尚未連結 Dropbox，雲端備份略過）'
                : '已備份到本機，但雲端上傳失敗：${result.uploadError}');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('備份失敗：$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importBackup() async {
    final backups = await BackupService.instance.listLocalBackups();
    if (!mounted) return;
    if (backups.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('本機還沒有任何備份檔')));
      return;
    }

    final chosen = await showDialog<File>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('選擇要還原的備份'),
        content: SizedBox(
          width: 360,
          child: ListView(
            shrinkWrap: true,
            children: backups
                .map(
                  (f) => ListTile(
                    title: Text(p.basename(f.path)),
                    onTap: () => Navigator.of(context).pop(f),
                  ),
                )
                .toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
        ],
      ),
    );
    if (chosen == null || !mounted) return;

    final confirmed = await showRestoreBackupConfirmDialog(context);
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    try {
      await BackupService.instance.restoreFromBackup(chosen);
      await _loadProjects();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已還原備份')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleDropboxLink() async {
    setState(() => _busy = true);
    try {
      final linked = await DropboxService.instance.isLinked();
      if (linked) {
        await DropboxService.instance.unlink();
      } else {
        await DropboxService.instance.linkAccount();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Dropbox 連結失敗：$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickDate({required bool isStart}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
      } else {
        _plannedCompletionDate = picked;
      }
    });
  }

  Future<void> _createProject() async {
    final name = _nameController.text.trim();
    final company = _companyController.text.trim();
    if (name.isEmpty ||
        company.isEmpty ||
        _startDate == null ||
        _plannedCompletionDate == null) {
      return;
    }
    await _repo.createProject(
      Project(
        name: name,
        companyName: company,
        startDate: _startDate!,
        plannedCompletionDate: _plannedCompletionDate!,
        tracksWorkingDays: _tracksWorkingDays,
        excludeWeekends: _tracksWorkingDays && _excludeWeekends,
        excludeNationalHolidays: _tracksWorkingDays && _excludeNationalHolidays,
        excludeBadWeather: _tracksWorkingDays && _excludeBadWeather,
        siteAreaPing: double.tryParse(_siteAreaController.text.trim()),
        basementFloors: int.tryParse(_basementFloorsController.text.trim()),
        basementFloorAreaPing: double.tryParse(
          _basementFloorAreaController.text.trim(),
        ),
        aboveGroundFloors: int.tryParse(
          _aboveGroundFloorsController.text.trim(),
        ),
        typicalFloorAreaPing: double.tryParse(
          _typicalFloorAreaController.text.trim(),
        ),
        roofFloors: int.tryParse(_roofFloorsController.text.trim()),
        roofFloorAreaPing: double.tryParse(
          _roofFloorAreaController.text.trim(),
        ),
      ),
    );
    _nameController.clear();
    _companyController.clear();
    _siteAreaController.clear();
    _basementFloorsController.clear();
    _basementFloorAreaController.clear();
    _aboveGroundFloorsController.clear();
    _typicalFloorAreaController.clear();
    _roofFloorsController.clear();
    _roofFloorAreaController.clear();
    setState(() {
      _startDate = null;
      _plannedCompletionDate = null;
      _tracksWorkingDays = false;
      _excludeWeekends = false;
      _excludeNationalHolidays = false;
      _excludeBadWeather = false;
      _showCreateForm = false;
    });
    await _loadProjects();
  }

  Future<void> _deleteProject(Project project) async {
    final confirmed = await _showDeleteProjectConfirm(project.name);
    if (!confirmed) return;
    await _repo.deleteProject(project.id!);
    await _loadProjects();
  }

  Future<bool> _showDeleteProjectConfirm(String name) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('確定要刪除專案「$name」嗎？'),
        content: const Text('這個專案底下所有的日報表資料都會一併刪除，此動作無法復原。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              '確定刪除',
              style: TextStyle(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  String? get _holidayCoverageWarning {
    if (_plannedCompletionDate == null) return null;
    final maxKnownYear = availableHolidayYears.reduce((a, b) => a > b ? a : b);
    if (_plannedCompletionDate!.year <= maxKnownYear) return null;
    return '目前只建有 ${availableHolidayYears.toList()..sort()} 年度的國定假日資料，'
        '超過 $maxKnownYear 年的部分暫不會被排除，等政府公告後需再更新。';
  }

  String get _calendarDaysPreview {
    if (_startDate == null || _plannedCompletionDate == null) {
      return '日曆天：請選擇日期';
    }
    final days = _plannedCompletionDate!.difference(_startDate!).inDays;
    return '日曆天：$days 天';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final dateFormat = DateFormat('yyyy-MM-dd');

    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AppHeader(),
              const SizedBox(height: 16),
              StepCard(
                stepNumber: 1,
                title: '建立專案',
                subtitle: '建立各別專案，分別累計人員、材料與機具紀錄。',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_showCreateForm) ...[
                      TextField(
                        controller: _nameController,
                        decoration: const InputDecoration(hintText: '輸入新專案名稱'),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _companyController,
                        decoration: const InputDecoration(hintText: '公司名稱'),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        '專案概述',
                        style: TextStyle(fontWeight: FontWeight.w500, fontSize: 15),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Text('基地面積'),
                          const SizedBox(width: 8),
                          _NumberField(controller: _siteAreaController),
                          const SizedBox(width: 6),
                          const Text('坪'),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Text('地下層'),
                          const SizedBox(width: 8),
                          _NumberField(
                            controller: _basementFloorsController,
                            isInteger: true,
                          ),
                          const SizedBox(width: 6),
                          const Text('層'),
                          const SizedBox(width: 12),
                          const Text('每層面積'),
                          const SizedBox(width: 8),
                          _NumberField(controller: _basementFloorAreaController),
                          const SizedBox(width: 6),
                          const Text('坪'),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Text('地上層'),
                          const SizedBox(width: 8),
                          _NumberField(
                            controller: _aboveGroundFloorsController,
                            isInteger: true,
                          ),
                          const SizedBox(width: 6),
                          const Text('層'),
                          const SizedBox(width: 12),
                          const Text('標準層面積'),
                          const SizedBox(width: 8),
                          _NumberField(controller: _typicalFloorAreaController),
                          const SizedBox(width: 6),
                          const Text('坪'),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Text('屋凸'),
                          const SizedBox(width: 8),
                          _NumberField(
                            controller: _roofFloorsController,
                            isInteger: true,
                          ),
                          const SizedBox(width: 6),
                          const Text('層'),
                          const SizedBox(width: 12),
                          const Text('單層面積'),
                          const SizedBox(width: 8),
                          _NumberField(controller: _roofFloorAreaController),
                          const SizedBox(width: 6),
                          const Text('坪'),
                        ],
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        '開工日期',
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 6),
                      _DateField(
                        label: _startDate == null
                            ? '請選擇日期'
                            : dateFormat.format(_startDate!),
                        onTap: () => _pickDate(isStart: true),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        '預定竣工日期',
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 6),
                      _DateField(
                        label: _plannedCompletionDate == null
                            ? '請選擇日期'
                            : dateFormat.format(_plannedCompletionDate!),
                        onTap: () => _pickDate(isStart: false),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 14,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.secondaryBg.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(_calendarDaysPreview),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.border, width: 1.5),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Expanded(child: Text('請問是否要計算工作天')),
                                const Text('是'),
                                Checkbox(
                                  value: _tracksWorkingDays,
                                  onChanged: (v) => setState(
                                    () => _tracksWorkingDays = v ?? false,
                                  ),
                                ),
                                const Text('否'),
                                Checkbox(
                                  value: !_tracksWorkingDays,
                                  onChanged: (v) => setState(
                                    () => _tracksWorkingDays = !(v ?? true),
                                  ),
                                ),
                              ],
                            ),
                            if (_tracksWorkingDays) ...[
                              const SizedBox(height: 8),
                              const Text('請問不計入工作天的事項'),
                              CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                controlAffinity: ListTileControlAffinity.leading,
                                title: const Text('週六日'),
                                value: _excludeWeekends,
                                onChanged: (v) =>
                                    setState(() => _excludeWeekends = v ?? false),
                              ),
                              CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                controlAffinity: ListTileControlAffinity.leading,
                                title: const Text('國定假日'),
                                value: _excludeNationalHolidays,
                                onChanged: (v) => setState(
                                  () => _excludeNationalHolidays = v ?? false,
                                ),
                              ),
                              if (_excludeNationalHolidays &&
                                  _holidayCoverageWarning != null)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    left: 12,
                                    bottom: 8,
                                  ),
                                  child: Text(
                                    _holidayCoverageWarning!,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.danger,
                                    ),
                                  ),
                                ),
                              CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                controlAffinity: ListTileControlAffinity.leading,
                                title: const Text('因為天氣或其他因素無法施工'),
                                value: _excludeBadWeather,
                                onChanged: (v) => setState(
                                  () => _excludeBadWeather = v ?? false,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      PrimaryButton(label: '新增專案', onPressed: _createProject),
                      const SizedBox(height: 10),
                    ],
                    if (!kIsWeb) ...[
                      Row(
                        children: [
                          Expanded(
                            child: SecondaryButton(
                              label: '匯出資料備份',
                              onPressed: _busy ? null : _exportBackup,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: SecondaryButton(
                              label: '匯入資料備份',
                              onPressed: _busy ? null : _importBackup,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      FutureBuilder<bool>(
                        future: DropboxService.instance.isLinked(),
                        builder: (context, snapshot) {
                          final linked = snapshot.data ?? false;
                          return TextButton(
                            onPressed: _busy ? null : _toggleDropboxLink,
                            child: Text(
                              linked
                                  ? 'Dropbox 已連結（點擊取消連結）'
                                  : '連結 Dropbox 帳號（用於雲端備份）',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 10),
                    ] else
                      const Padding(
                        padding: EdgeInsets.only(bottom: 10),
                        child: Text(
                          '網頁試用版僅供畫面預覽，資料備份與 Dropbox 雲端同步僅正式版（Android）提供。',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    if (!_showCreateForm)
                      PrimaryButton(
                        label: '建立新專案',
                        onPressed: () => setState(() => _showCreateForm = true),
                      ),
                    if (_projects.isEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.border),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          '尚未建立專案，請先輸入專案名稱。',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      )
                    else
                      ..._projects.map(
                        (p) => _ProjectTile(
                          project: p,
                          onNewReport: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => WizardScreen(project: p),
                              ),
                            );
                          },
                          onDelete: () => _deleteProject(p),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _DateField({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(label),
      ),
    );
  }
}

class _ProjectTile extends StatelessWidget {
  final Project project;
  final VoidCallback onNewReport;
  final VoidCallback onDelete;

  const _ProjectTile({
    required this.project,
    required this.onNewReport,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  project.name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                FutureBuilder<int>(
                  future: ReportRepository.instance.countBackfilledReports(
                    project.id!,
                  ),
                  builder: (context, snapshot) {
                    final count = snapshot.data ?? 0;
                    if (count == 0) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '補登 $count 次',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.danger,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ElevatedButton(
                    onPressed: onNewReport,
                    child: const Text('新增日報'),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: onDelete,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.dangerBg,
                      foregroundColor: AppColors.danger,
                      elevation: 0,
                    ),
                    child: const Text('刪除專案'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  final TextEditingController controller;
  final bool isInteger;

  const _NumberField({required this.controller, this.isInteger = false});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      child: TextField(
        controller: controller,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.numberWithOptions(decimal: !isInteger),
        decoration: const InputDecoration(
          contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        ),
      ),
    );
  }
}
