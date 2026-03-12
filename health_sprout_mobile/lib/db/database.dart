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
  /// Includes latest values, aggregates, and 7-day/30-day trends.
  Future<String> buildAiSummary({int days = 90}) async {
    final db    = await database;
    final today = DateTime.now().toLocal().toIso8601String().substring(0, 10);
    final since = DateTime.now().subtract(Duration(days: days));
    final sinceStr = since.toIso8601String().substring(0, 10);

    // Query 1: aggregates over the period
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
    ''', [sinceStr, today]);

    if (aggRows.isEmpty) return 'No health data recorded yet.';

    // Query 2: latest values (same as dashboard tiles)
    final latestAll = await getLatestAll();

    // Query 3: values from ~7 days ago and ~30 days ago for trend analysis
    final d7ago  = DateTime.now().subtract(const Duration(days: 7))
        .toIso8601String().substring(0, 10);
    final d30ago = DateTime.now().subtract(const Duration(days: 30))
        .toIso8601String().substring(0, 10);

    final lines = <String>[
      '=== HEALTH DATA SUMMARY (last $days days, from SQLite DB) ===',
      'Today\'s date: $today',
      '',
    ];

    for (final r in aggRows) {
      final metric = r['metric'] as String;
      final label  = MetricType.labels[metric] ?? metric;
      final unit   = MetricType.units[metric]  ?? '';

      final latest     = latestAll[metric];
      final latestVal  = latest?.value.toStringAsFixed(1) ?? 'unknown';
      final latestDate = latest?.date ?? 'unknown';

      // Get value from ~7 days ago
      final rows7 = await db.query('health_metrics',
        where: 'metric = ? AND date <= ? AND date >= ?',
        whereArgs: [metric, d7ago, sinceStr],
        orderBy: 'date DESC', limit: 1);
      final val7 = rows7.isNotEmpty
          ? (rows7.first['value'] as num).toDouble() : null;

      // Get value from ~30 days ago
      final rows30 = await db.query('health_metrics',
        where: 'metric = ? AND date <= ? AND date >= ?',
        whereArgs: [metric, d30ago, sinceStr],
        orderBy: 'date DESC', limit: 1);
      final val30 = rows30.isNotEmpty
          ? (rows30.first['value'] as num).toDouble() : null;

      // Build trend strings
      String trend7  = '';
      String trend30 = '';
      if (latest != null && val7 != null) {
        final diff = latest.value - val7;
        final pct  = val7 != 0 ? (diff / val7 * 100) : 0.0;
        trend7 = '7d_change=${diff >= 0 ? "+" : ""}${diff.toStringAsFixed(1)}$unit'
                 '(${pct >= 0 ? "+" : ""}${pct.toStringAsFixed(1)}%)';
      }
      if (latest != null && val30 != null) {
        final diff = latest.value - val30;
        final pct  = val30 != 0 ? (diff / val30 * 100) : 0.0;
        trend30 = '30d_change=${diff >= 0 ? "+" : ""}${diff.toStringAsFixed(1)}$unit'
                  '(${pct >= 0 ? "+" : ""}${pct.toStringAsFixed(1)}%)';
      }

      lines.add(
        '$label: latest=$latestVal$unit on $latestDate  '
        'avg=${r['avg_val']}$unit  '
        'min=${r['min_val']}$unit  max=${r['max_val']}$unit  '
        '${r['data_points']} readings  '
        '$trend7  $trend30',
      );
    }

    // Add recent daily activity log (last 7 days) for correlation analysis
    lines.add('');
    lines.add('=== RECENT DAILY LOG (last 7 days) ===');
    for (int i = 0; i < 7; i++) {
      final d = DateTime.now().subtract(Duration(days: i))
          .toIso8601String().substring(0, 10);
      final dayRows = await db.query('health_metrics',
        where: 'date = ?', whereArgs: [d], orderBy: 'metric');

      if (dayRows.isEmpty) continue;
      final dayMetrics = dayRows.map((row) {
        final m = row['metric'] as String;
        final v = (row['value'] as num).toDouble();
        final u = MetricType.units[m] ?? '';
        final shortLabel = MetricType.labels[m] ?? m;
        return '$shortLabel=${v.toStringAsFixed(1)}$u';
      }).join(', ');
      lines.add('$d: $dayMetrics');
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
