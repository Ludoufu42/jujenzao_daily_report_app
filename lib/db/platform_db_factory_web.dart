import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

/// Web has no real filesystem/native SQLite — sqflite_common_ffi_web runs
/// SQLite compiled to WASM, persisted via IndexedDB, behind the same
/// sqflite `Database`/`DatabaseExecutor` API the rest of the app already uses.
///
/// Using the no-web-worker variant: it runs SQLite on the main thread instead
/// of a SharedWorker, which is less scalable but far more reliable across
/// browsers/embedded previews (the worker handshake is a known rough edge of
/// this still-experimental package).
void ensurePlatformDatabaseFactory() {
  databaseFactory = databaseFactoryFfiWebNoWebWorker;
}
