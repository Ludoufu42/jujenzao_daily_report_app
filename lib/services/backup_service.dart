import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:universal_io/io.dart';

import '../db/database_helper.dart';
import 'dropbox_config.dart';
import 'dropbox_service.dart';

/// Every completed daily report triggers a full-database "time machine"
/// backup: one dated file per day, kept locally AND (if the user has linked
/// Dropbox) mirrored to the App-folder on Dropbox. Restoring from one of
/// these backups fully overwrites the current on-device database — there is
/// no merge, by explicit product decision (see the plan's "自動備份與匯入還原").
class BackupService {
  BackupService._internal();
  static final BackupService instance = BackupService._internal();

  Future<Directory> _backupsDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'backups'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  String _backupFileName(DateTime date) =>
      'backup_${DateFormat('yyyyMMdd_HHmmss').format(date)}.db';

  /// Copies the live database to a dated local backup file, and — if a
  /// Dropbox account is linked — uploads that same file to Dropbox. Returns
  /// the local backup file path. Upload failures are surfaced to the caller
  /// (so the UI can tell the user "只存到本機、雲端上傳失敗") rather than
  /// silently swallowed, since a backup you think is off-device but isn't is
  /// worse than no backup at all.
  Future<BackupResult> exportBackup() async {
    final dbPath = await DatabaseHelper.instance.databaseFilePath();
    final dbFile = File(dbPath);
    if (!await dbFile.exists()) {
      throw StateError('本機資料庫檔案不存在，無法備份');
    }

    final now = DateTime.now();
    final backupsDir = await _backupsDir();
    final backupPath = p.join(backupsDir.path, _backupFileName(now));
    await dbFile.copy(backupPath);

    var uploadedToCloud = false;
    String? uploadError;
    try {
      if (await DropboxService.instance.isLinked()) {
        await DropboxService.instance.uploadFile(
          backupPath,
          '/backups/${p.basename(backupPath)}',
        );
        uploadedToCloud = true;
      }
    } catch (e) {
      uploadError = e.toString();
    }

    return BackupResult(
      localPath: backupPath,
      uploadedToCloud: uploadedToCloud,
      uploadError: uploadError,
    );
  }

  Future<List<File>> listLocalBackups() async {
    final dir = await _backupsDir();
    final files = await dir
        .list()
        .where((e) => e is File && e.path.endsWith('.db'))
        .cast<File>()
        .toList();
    files.sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  /// Fully overwrites the current on-device database with [backupFile]'s
  /// contents. The caller is responsible for confirming this destructive,
  /// irreversible action with the user first.
  Future<void> restoreFromBackup(File backupFile) async {
    await DatabaseHelper.instance.close();
    final dbPath = await DatabaseHelper.instance.databaseFilePath();
    await backupFile.copy(dbPath);
  }
}

class BackupResult {
  final String localPath;
  final bool uploadedToCloud;
  final String? uploadError;

  const BackupResult({
    required this.localPath,
    required this.uploadedToCloud,
    this.uploadError,
  });
}

/// Surfaced in the settings UI to explain the Dropbox setup prerequisite.
String? get dropboxSetupHint => DropboxConfig.isConfigured
    ? null
    : '尚未設定 Dropbox App Key，備份目前只會存在本機。請至 Dropbox App Console 建立一個 App（App folder 權限），把 App Key 交給開發者填入設定。';
