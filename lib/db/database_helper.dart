import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import 'platform_db_factory_stub.dart'
    if (dart.library.io) 'platform_db_factory_io.dart'
    if (dart.library.html) 'platform_db_factory_web.dart';

class DatabaseHelper {
  DatabaseHelper._internal();
  static final DatabaseHelper instance = DatabaseHelper._internal();

  static const String dbFileName = 'jujenzao_daily_report.db';

  Database? _db;
  static bool _ffiInitialized = false;

  static void _ensureDesktopFfiFactory() {
    if (_ffiInitialized) return;
    ensurePlatformDatabaseFactory();
    _ffiInitialized = true;
  }

  Future<Database> get database async {
    _ensureDesktopFfiFactory();
    _db ??= await _open();
    return _db!;
  }

  Future<String> databaseFilePath() async {
    final dbDir = await getDatabasesPath();
    return join(dbDir, dbFileName);
  }

  Future<Database> _open() async {
    final path = await databaseFilePath();
    return openDatabase(
      path,
      version: 6,
      onCreate: (db, version) => createSchema(db),
      onUpgrade: (db, oldVersion, newVersion) => _upgrade(db, oldVersion),
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }

  static Future<void> _upgrade(Database db, int oldVersion) async {
    if (oldVersion < 2) {
      await db.execute(
        'ALTER TABLE projects ADD COLUMN tracks_working_days INTEGER NOT NULL DEFAULT 0',
      );
      await db.execute(
        'ALTER TABLE projects ADD COLUMN exclude_weekends INTEGER NOT NULL DEFAULT 0',
      );
      await db.execute(
        'ALTER TABLE projects ADD COLUMN exclude_national_holidays INTEGER NOT NULL DEFAULT 0',
      );
      await db.execute(
        'ALTER TABLE projects ADD COLUMN exclude_bad_weather INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (oldVersion < 3) {
      await db.execute(
        'ALTER TABLE daily_reports ADD COLUMN is_backfilled INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (oldVersion < 4) {
      await db.execute(
        'ALTER TABLE projects ADD COLUMN site_area_ping REAL',
      );
      await db.execute(
        'ALTER TABLE projects ADD COLUMN basement_floors INTEGER',
      );
      await db.execute(
        'ALTER TABLE projects ADD COLUMN basement_floor_area_ping REAL',
      );
      await db.execute(
        'ALTER TABLE projects ADD COLUMN above_ground_floors INTEGER',
      );
      await db.execute(
        'ALTER TABLE projects ADD COLUMN typical_floor_area_ping REAL',
      );
      await db.execute(
        'ALTER TABLE projects ADD COLUMN roof_floors INTEGER',
      );
      await db.execute(
        'ALTER TABLE projects ADD COLUMN roof_floor_area_ping REAL',
      );
    }
    if (oldVersion < 5) {
      await db.execute(
        'ALTER TABLE daily_reports ADD COLUMN today_critical_path TEXT',
      );
      await db.execute(
        'ALTER TABLE daily_reports ADD COLUMN tomorrow_critical_path TEXT',
      );
    }
    if (oldVersion < 6) {
      await _createInspectionTables(db);
    }
  }

  static Future<void> _createInspectionTables(Database db) async {
    await db.execute('''
      CREATE TABLE inspections (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        project_id INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
        critical_path_label TEXT NOT NULL,
        template_name TEXT NOT NULL,
        inspector_signature_path TEXT,
        pdf_path TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE inspection_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        inspection_id INTEGER NOT NULL REFERENCES inspections(id) ON DELETE CASCADE,
        item_name TEXT NOT NULL,
        description TEXT NOT NULL,
        result TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE inspection_photos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        inspection_id INTEGER NOT NULL REFERENCES inspections(id) ON DELETE CASCADE,
        file_path TEXT NOT NULL,
        sort_order INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_inspections_project ON inspections(project_id)',
    );
    await db.execute(
      'CREATE INDEX idx_inspection_items_inspection ON inspection_items(inspection_id)',
    );
    await db.execute(
      'CREATE INDEX idx_inspection_photos_inspection ON inspection_photos(inspection_id)',
    );
  }

  /// Exposed as a static, reusable schema-creation routine so tests can
  /// build an equivalent in-memory database via sqflite_common_ffi.
  static Future<void> createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE projects (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        company_name TEXT NOT NULL,
        start_date TEXT NOT NULL,
        planned_completion_date TEXT NOT NULL,
        tracks_working_days INTEGER NOT NULL DEFAULT 0,
        exclude_weekends INTEGER NOT NULL DEFAULT 0,
        exclude_national_holidays INTEGER NOT NULL DEFAULT 0,
        exclude_bad_weather INTEGER NOT NULL DEFAULT 0,
        site_area_ping REAL,
        basement_floors INTEGER,
        basement_floor_area_ping REAL,
        above_ground_floors INTEGER,
        typical_floor_area_ping REAL,
        roof_floors INTEGER,
        roof_floor_area_ping REAL
      )
    ''');

    await db.execute('''
      CREATE TABLE trade_types (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        project_id INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
        category TEXT NOT NULL,
        type TEXT NOT NULL,
        name TEXT NOT NULL,
        unit TEXT NOT NULL,
        sort_order INTEGER NOT NULL,
        status TEXT NOT NULL DEFAULT 'active'
      )
    ''');

    await db.execute('''
      CREATE TABLE daily_reports (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        project_id INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
        report_date TEXT NOT NULL,
        weather_am TEXT NOT NULL,
        weather_pm TEXT NOT NULL,
        is_rain_or_holiday INTEGER NOT NULL DEFAULT 0,
        today_critical_path TEXT,
        tomorrow_critical_path TEXT,
        today_progress_text TEXT NOT NULL DEFAULT '',
        tomorrow_progress_text TEXT NOT NULL DEFAULT '',
        notes_text TEXT NOT NULL DEFAULT '',
        supervisor_signature_path TEXT,
        is_backfilled INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE labor_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        report_id INTEGER NOT NULL REFERENCES daily_reports(id) ON DELETE CASCADE,
        trade_type_id INTEGER NOT NULL REFERENCES trade_types(id),
        morning_count REAL NOT NULL DEFAULT 0,
        afternoon_count REAL NOT NULL DEFAULT 0,
        today_total REAL NOT NULL DEFAULT 0,
        cumulative REAL NOT NULL DEFAULT 0,
        is_subcontracted INTEGER NOT NULL DEFAULT 0,
        vendor TEXT NOT NULL DEFAULT '',
        today_content TEXT NOT NULL DEFAULT '',
        tomorrow_content TEXT NOT NULL DEFAULT ''
      )
    ''');

    await db.execute('''
      CREATE TABLE material_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        report_id INTEGER NOT NULL REFERENCES daily_reports(id) ON DELETE CASCADE,
        trade_type_id INTEGER NOT NULL REFERENCES trade_types(id),
        quantity REAL NOT NULL DEFAULT 0,
        cumulative REAL NOT NULL DEFAULT 0,
        usage_location TEXT NOT NULL DEFAULT ''
      )
    ''');

    await db.execute('''
      CREATE TABLE equipment_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        report_id INTEGER NOT NULL REFERENCES daily_reports(id) ON DELETE CASCADE,
        trade_type_id INTEGER NOT NULL REFERENCES trade_types(id),
        quantity REAL NOT NULL DEFAULT 0,
        cumulative REAL NOT NULL DEFAULT 0,
        is_subcontracted INTEGER NOT NULL DEFAULT 0,
        vendor TEXT NOT NULL DEFAULT '',
        today_content TEXT NOT NULL DEFAULT '',
        tomorrow_content TEXT NOT NULL DEFAULT ''
      )
    ''');

    await db.execute('''
      CREATE TABLE report_photos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        report_id INTEGER NOT NULL REFERENCES daily_reports(id) ON DELETE CASCADE,
        file_path TEXT NOT NULL,
        sort_order INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute(
      'CREATE INDEX idx_trade_types_project ON trade_types(project_id)',
    );
    await db.execute(
      'CREATE INDEX idx_daily_reports_project_date ON daily_reports(project_id, report_date)',
    );
    await db.execute(
      'CREATE INDEX idx_labor_entries_report ON labor_entries(report_id)',
    );
    await db.execute(
      'CREATE INDEX idx_material_entries_report ON material_entries(report_id)',
    );
    await db.execute(
      'CREATE INDEX idx_equipment_entries_report ON equipment_entries(report_id)',
    );
    await db.execute(
      'CREATE INDEX idx_report_photos_report ON report_photos(report_id)',
    );

    await _createInspectionTables(db);
  }

  Future<void> close() async {
    final db = _db;
    if (db != null) {
      await db.close();
      _db = null;
    }
  }
}
