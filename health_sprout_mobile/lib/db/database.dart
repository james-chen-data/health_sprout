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

  /// Get latest value for every metric type — used to build the dashboard.
  /// Uses MAX(date) to find the most recent reading, not MAX(id).
  Future<Map<String, HealthMetric>> getLatestAll() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT h.* FROM health_metrics h
      INNER JOIN (
        SELECT metric, MAX(date) as max_date
        FROM health_metrics
        GROUP BY metric
      ) latest ON h.metric = latest.metric AND h.date = latest.max_date
      GROUP BY h.metric
      ORDER BY h.metric
    ''');
    return {
      for (final r in rows) (r['metric'] as String): HealthMetric.fromMap(r),
    };
  }

  /// Build a compact AI-readable summary of recent health data.
  /// The AI uses this instead of raw values — no hallucination risk.
  Future<String> buildAiSummary({int days = 30}) async {
    final db    = await database;
    final since = DateTime.now().subtract(Duration(days: days));
    final sinceStr = since.toIso8601String().substring(0, 10);

    final rows = await db.rawQuery('''
      SELECT
        m.metric,
        ROUND(AVG(m.value), 1)  as avg_val,
        ROUND(MIN(m.value), 1)  as min_val,
        ROUND(MAX(m.value), 1)  as max_val,
        COUNT(*)                as data_points,
        l.date                  as latest_date,
        ROUND(l.value, 1)       as latest_val
      FROM health_metrics m
      INNER JOIN (
        SELECT h.metric, h.date, h.value
        FROM health_metrics h
        INNER JOIN (
          SELECT metric, MAX(date) as max_date
          FROM health_metrics
          WHERE date >= ?
          GROUP BY metric
        ) ld ON h.metric = ld.metric AND h.date = ld.max_date
        GROUP BY h.metric
      ) l ON m.metric = l.metric
      WHERE m.date >= ?
      GROUP BY m.metric
      ORDER BY m.metric
    ''', [sinceStr, sinceStr]);

    if (rows.isEmpty) return 'No health data recorded yet.';

    final lines = <String>[
      '=== HEALTH DATA SUMMARY (last $days days, from SQLite DB) ===',
    ];

    for (final r in rows) {
      final metric = r['metric'] as String;
      final label  = MetricType.labels[metric] ?? metric;
      final unit   = MetricType.units[metric]  ?? '';
      lines.add(
        '$label: avg=${r['avg_val']}$unit  '
        'min=${r['min_val']}$unit  '
        'max=${r['max_val']}$unit  '
        'latest=${r['latest_val']}$unit on ${r['latest_date']}  '
        '(${r['data_points']} readings)',
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
