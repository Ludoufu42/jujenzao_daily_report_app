import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The app ships for Android, but this lets us `flutter run -d windows`
/// during development on machines with no Android emulator configured.
void ensurePlatformDatabaseFactory() {
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
}
