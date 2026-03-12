import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/health_metric.dart';

/// Singleton SQLite database — single source of truth for all health metrics.
///
/// The AI coaching layer always reads from here; it never holds metric values
/// in memory or infers them from conversation context.
class HealthDatabase {
  static final HealthDatabase _instance = HealthDatabase._internal();
  factory HealthDatabase() => _instance;
  HealthDatabase._internal();

  static Database? _db;

  Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path   = join(dbPath, 'health_sprout.db');

    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE health_metrics (
            id      INTEGER PRIMARY KEY AUTOINCREMENT,
            date    TEXT    NOT NULL,        -- "2026-03-11"
            metric  TEXT    NOT NULL,        -- MetricType constant
            value   REAL    NOT NULL,
            unit    TEXT    NOT NULL,
            source  TEXT    NOT NULL,        -- "health_connect" | "fitbit" | "manual"
            notes   TEXT
          )
        ''');

        // Index for fast date-range queries
        await db.execute(
          'CREATE INDEX idx_metric_date ON health_metrics (metric, date)',
        );

        // Prevent duplicate entries for same date+metric+source
        await db.execute(
          'CREATE UNIQUE INDEX idx_unique_day '
          'ON health_metrics (date, metric, source)',
        );
      },
    );
  }

  // ── Write ────────────────────────────────────────────────────────────────

  /// Insert or replace a single metric (upsert by date+metric+source).
  Future<void> upsertMetric(HealthMetric m) async {
    final db = await database;
    await db.insert(
      'health_metrics',
      m.toMap()..remove('id'),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Bulk upsert a list of metrics (used after a Health Connect sync).
  Future<void> upsertMetrics(List<HealthMetric> metrics) async {
    final db = await database;
    final batch = db.batch();
    for (final m in metrics) {
      batch.insert(
        'health_metrics',
        m.toMap()..remove('id'),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  // ── Read ─────────────────────────────────────────────────────────────────

  /// Get all values for one metric type, ordered by date ascending.
  Future<List<HealthMetric>> getMetricHistory(
    String metricType, {
    int days = 90,
  }) async {
    final db    = await database;
    final since = DateTime.now().subtract(Duration(days: days));
    final sinceStr = since.toIso8601String().substring(0, 10);

    final rows = await db.query(
      'health_metrics',
      where: 'metric = ? AND date >= ?',
      whereArgs: [metricType, sinceStr],
      orderBy: 'date ASC',
    );
    return rows.map(HealthMetric.fromMap).toList();
  }

  /// Get the most recent value for a metric.
  Future<HealthMetric?> getLatestMetric(String metricType) async {
    final db   = await database;
    final rows = await db.query(
      'health_metrics',
      where:    'metric = ?',
      whereArgs: [metricType],
      orderBy:  'date DESC',
      limit:    1,
    );
    return rows.isEmpty ? null : HealthMetric.fromMap(rows.first);
  }

  /// Get latest value for every metric type — used to build the dashboard + AI.
  /// Runs one clean query per metric: ORDER BY date DESC LIMIT 1.
  /// Caps at today's date to exclude any accidentally future-dated rows.
  Future<Map<String, HealthMetric>> getLatestAll() async {
    final db = await database;
    final today = DateTime.now().toLocal().toIso8601String().substring(0, 10);

    // Get distinct metric types
    final metricRows = await db.rawQuery(
        'SELECT DISTINCT metric FROM health_metrics ORDER BY metric');

    final result = <String, HealthMetric>{};
    for (final mr in metricRows) {
      final metric = mr['metric'] as String;
      final rows = await db.query(
        'health_metrics',
        where:     'metric = ? AND date <= ?',
        whereArgs: [metric, today],
        orderBy:   'date DESC',
        limit:     1,
      );
      if (rows.isNotEmpty) {
        result[metric] = HealthMetric.fromMap(rows.first);
      }
    }
    return result;
  }

  /// Build a compact AI-readable summary of recent health data.
  /// Uses getLatestAll() for latest values — same source as the dashboard tiles.
  Future<String> buildAiSummary({int days = 30}) async {
    final db    = await database;
    final since = DateTime.now().subtract(Duration(days: days));
    final sinceStr = since.toIso8601String().substring(0, 10);

    // Query 1: aggregates over the period (only date-filtered, no latest logic)
    final aggRows = await db.rawQuery('''
      SELECT metric,
             ROUND(AVG(value), 2) as avg_val,
             ROUND(MIN(value), 2) as min_val,
             ROUND(MAX(value), 2) as max_val,
             COUNT(*)             as data_points
      FROM health_metrics
      WHERE date >= ? AND date <= ?
      GROUP BY metric
      ORDER BY metric
    ''', [sinceStr, DateTime.now().toIso8601String().substring(0, 10)]);

    if (aggRows.isEmpty) return 'No health data recorded yet.';

    // Query 2: use getLatestAll() — the EXACT same function the dashboard uses.
    // This guarantees the AI sees the same "latest" values as the tiles.
    final latestAll = await getLatestAll();

    final lines = <String>[
      '=== HEALTH DATA SUMMARY (last $days days, from SQLite DB) ===',
      'Today\'s date: ${DateTime.now().toIso8601String().substring(0, 10)}',
    ];

    for (final r in aggRows) {
      final metric = r['metric'] as String;
      final label  = MetricType.labels[metric] ?? metric;
      final unit   = MetricType.units[metric]  ?? '';

      final latest     = latestAll[metric];
      final latestVal  = latest?.value.toStringAsFixed(1) ?? 'unknown';
      final latestDate = latest?.date ?? 'unknown';

      lines.add(
        '$label: latest=$latestVal$unit on $latestDate  '
        'avg=${r['avg_val']}$unit  '
        'min=${r['min_val']}$unit  '
        'max=${r['max_val']}$unit  '
        '(${r['data_points']} readings in last $days days)',
      );
    }
    lines.add('=== END HEALTH DATA ===');
    return lines.join('\n');
  }

  /// Count total rows (useful for showing "X days of data synced").
  Future<int> countRows() async {
    final db   = await database;
    final rows = await db.rawQuery('SELECT COUNT(*) as n FROM health_metrics');
    return (rows.first['n'] as int?) ?? 0;
  }

  /// Delete all data (used for account reset).
  Future<void> clearAll() async {
    final db = await database;
    await db.delete('health_metrics');
  }
}
