import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:universal_io/io.dart';

import '../db/report_repository.dart';
import '../models/project.dart';
import '../services/auth_user.dart';
import '../services/backup_service.dart';
import '../services/cloud_config.dart';
import '../services/cloud_service.dart';
import '../services/google_auth.dart';
import '../services/project_sync.dart';
import '../theme.dart';
import '../widgets/confirm_dialogs.dart';
import 'beta_panel.dart';
import 'wizard/wizard_screen.dart';

/// 登入後的首頁:專案清單來自工程管理的推播(依名單決定能看哪些),員工不建專案。
class HomeScreen extends StatefulWidget {
  final AuthUser user;
  const HomeScreen({super.key, required this.user});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Project> _projects = [];
  bool _loading = true;
  bool _busy = false;
  ProjectSyncResult? _result;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  /// 開啟 App 時從雲端取得可看的專案與專案包(離線用上次的快取)。
  Future<void> _sync() async {
    setState(() => _loading = true);
    final result = await ProjectSync().sync(expectEmail: widget.user.email);
    if (!mounted) return;
    setState(() {
      _result = result;
      _projects = result.projects;
      _loading = false;
    });
  }

  Future<void> _signOut() async {
    await CloudService.instance.clearCache();
    GoogleAuth.instance.signOut();
  }

  Future<void> _exportBackup() async {
    setState(() => _busy = true);
    try {
      await BackupService.instance.exportBackup();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已備份到本機')));
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
      await _sync();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已還原備份')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = _result?.me;
    final error = me?.error;
    final blocked = error != null && (error.isAuthProblem || error.isForbidden);

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
              _UserBar(user: widget.user, onSignOut: _signOut),
              const SizedBox(height: 12),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (blocked)
                _Notice(
                  text: error.isForbidden
                      ? '${widget.user.email} 不在名單內，請聯絡管理者加入名單，再按「重新整理」。'
                      : error.message,
                  isError: true,
                  action: SecondaryButton(label: '重新整理', onPressed: _sync),
                )
              else
                StepCard(
                  stepNumber: 1,
                  title: '選擇專案',
                  subtitle: '專案由工程管理推播，不需要自己建立。',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (me?.fromCache == true)
                        const _Notice(text: '目前離線，使用上次下載的專案資料。'),
                      for (final e in _result?.bundleErrors.entries ?? const <MapEntry<int, String>>[])
                        _Notice(text: '專案 ${e.key}：${e.value}'),
                      SecondaryButton(label: '重新整理專案', onPressed: _busy ? null : _sync),
                      const SizedBox(height: 10),
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
                        const SizedBox(height: 10),
                      ],
                      if (_projects.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.border),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            '你目前沒有可填日報的專案。請聯絡管理者把你加進專案名單，或請工程管理先推播專案。',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        )
                      else
                        ..._projects.map(
                          (p) => Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _ProjectTile(
                                project: p,
                                onNewReport: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => WizardScreen(project: p),
                                    ),
                                  );
                                },
                              ),
                              if (CloudConfig.isBeta) BetaPanel(project: p),
                            ],
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

class _UserBar extends StatelessWidget {
  final AuthUser user;
  final VoidCallback onSignOut;
  const _UserBar({required this.user, required this.onSignOut});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            user.name.isNotEmpty ? '${user.name}（${user.email}）' : user.email,
            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        TextButton(onPressed: onSignOut, child: const Text('登出')),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  final String text;
  final bool isError;
  final Widget? action;
  const _Notice({required this.text, this.isError = false, this.action});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isError ? AppColors.dangerBg : Colors.white,
        border: Border.all(color: isError ? AppColors.danger : AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            style: TextStyle(color: isError ? AppColors.danger : AppColors.textSecondary),
          ),
          if (action != null) ...[const SizedBox(height: 10), action!],
        ],
      ),
    );
  }
}

class _ProjectTile extends StatelessWidget {
  final Project project;
  final VoidCallback onNewReport;

  const _ProjectTile({required this.project, required this.onNewReport});

  String get _floors =>
      '地下${project.basementFloors ?? 0}層／地上${project.aboveGroundFloors ?? 0}層／屋凸${project.roofFloors ?? 0}層';

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
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _floors,
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ),
                FutureBuilder<int>(
                  future: ReportRepository.instance.countBackfilledReports(project.id!),
                  builder: (context, snapshot) {
                    final count = snapshot.data ?? 0;
                    if (count == 0) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '補登 $count 次',
                        style: const TextStyle(fontSize: 12, color: AppColors.danger),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: ElevatedButton(onPressed: onNewReport, child: const Text('新增日報')),
          ),
        ],
      ),
    );
  }
}
