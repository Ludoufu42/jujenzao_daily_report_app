import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:universal_io/io.dart';

import '../db/database_helper.dart';

/// Every completed daily report triggers a full-database "time machine"
/// backup: one dated file per day, kept locally. (日報本身另外會自動上傳雲端 R2,
/// 見 step_preview.) Restoring from one of these backups fully overwrites the
/// current on-device database — there is no merge, by explicit product decision
/// (see the plan's "自動備份與匯入還原").
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

  /// Copies the live database to a dated local backup file. Returns the local
  /// backup file path.
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

    return BackupResult(localPath: backupPath);
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

  const BackupResult({required this.localPath});
}
