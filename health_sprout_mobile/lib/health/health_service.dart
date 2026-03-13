import 'package:health/health.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/health_metric.dart';
import '../db/database.dart';

/// Reads health data from Health Connect (Android) and stores it in SQLite.
///
/// All data flows: Health Connect → HealthService → SQLite DB → AI summary.
/// The AI never reads raw Health Connect data directly.
class HealthService {
  final Health _health = Health();
  final HealthDatabase _db = HealthDatabase();

  // ── Data types we request from Health Connect ──────────────────────────
  static const List<HealthDataType> _types = [
    HealthDataType.STEPS,
    HealthDataType.RESTING_HEART_RATE,
    HealthDataType.HEART_RATE_VARIABILITY_RMSSD,
    HealthDataType.WEIGHT,
    HealthDataType.HEIGHT,
    HealthDataType.BODY_FAT_PERCENTAGE,
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.SLEEP_DEEP,
    HealthDataType.SLEEP_REM,
    HealthDataType.SLEEP_LIGHT,
    HealthDataType.BLOOD_OXYGEN,
    HealthDataType.RESPIRATORY_RATE,
    HealthDataType.ACTIVE_ENERGY_BURNED,
    // NOTE: HealthDataType.WORKOUT excluded — SecurityException on Pixel/Android 16.
    // NOTE: HealthDataType.HEART_RATE excluded — per-second data causes OOM.
  ];

  // ── Source-filtering helpers ──────────────────────────────────────────
  //
  // When multiple apps write the same data type (Fitbit + Google Fit + phone
  // sensor), simply summing all records leads to massive over-counting.
  // For activity data (steps, calories) we prefer the wearable source.
  // Priority: Fitbit > any other source.
  //
  // The Fitbit Android app registers itself in Health Connect under the
  // package name "com.fitbit.FitbitMobile"; the human-readable sourceName
  // is typically "Fitbit".
  static bool _isFitbit(HealthDataPoint p) {
    final id   = p.sourceId.toLowerCase();
    final name = p.sourceName.toLowerCase();
    return id.contains('fitbit') || name == 'fitbit' || name.contains('fitbit');
  }

  // ── Request permissions ────────────────────────────────────────────────

  Future<bool> requestPermissions() async {
    await Permission.activityRecognition.request();
    final permissions = _types.map((_) => HealthDataAccess.READ).toList();
    try {
      return await _health.requestAuthorization(_types, permissions: permissions);
    } catch (_) {
      return false;
    }
  }

  Future<bool> hasPermissions() async {
    try {
      return await _health.hasPermissions(_types) ?? false;
    } catch (_) {
      return false;
    }
  }

  // ── Sync health data into SQLite ───────────────────────────────────────

  /// Pull up to [days] days of data from Health Connect and save to DB.
  ///
  /// Aggregation strategy per metric:
  ///   STEPS / ACTIVE_CALORIES
  ///     Only Fitbit-sourced records are used, then SUM.
  ///     Reason: multiple apps write these types simultaneously (phone sensor,
  ///     Google Fit, Fitbit). Fitbit's intraday records (one per ~15 min) sum
  ///     to the correct daily total; mixing in other sources double-counts.
  ///     If no Fitbit records exist for a day, falls back to SUM of all sources.
  ///   SUM  – sleep stages (each segment is additive)
  ///   AVG  – HRV, SpO2, breathing rate (nightly averages)
  ///   MAX  – resting HR
  ///   LATEST – weight, body fat, height, etc.
  Future<SyncResult> syncToDatabase({int days = 180}) async {
    final now   = DateTime.now();
    final start = now.subtract(Duration(days: days));
    int   saved = 0;
    int   errors = 0;

    const sumTypes = {
      MetricType.steps,
      MetricType.activeCalories,
      MetricType.sleepDurationHr,
      MetricType.sleepDeepMin,
      MetricType.sleepRemMin,
      MetricType.sleepLightMin,
      MetricType.workoutDurationMin,
      MetricType.workoutCalories,
      MetricType.workoutDistanceM,
    };
    const avgTypes = {
      MetricType.hrvRmssdMs,
      MetricType.spo2Pct,
      MetricType.breathingRate,
    };
    const maxTypes = {
      MetricType.restingHrBpm,
    };

    // Types that should only count Fitbit-sourced records.
    // For other sources we accumulate a fallback sum in case Fitbit data
    // is absent (e.g. user doesn't own a Fitbit).
    const fitbitPreferredTypes = {
      MetricType.steps,
      MetricType.activeCalories,
    };

    // Two parallel agg maps for preferred types:
    //   _fitbitAgg — Fitbit-source records only
    //   _allAgg    — all sources (fallback)
    final Map<String, _MetricAgg> fitbitAgg = {};
    final Map<String, _MetricAgg> allAgg    = {};
    // Single agg map for all other types.
    final Map<String, _MetricAgg> agg = {};

    for (final type in _types) {
      try {
        final points = await _health.getHealthDataFromTypes(
          types:     [type],
          startTime: start,
          endTime:   now,
        );

        for (final p in points) {
          final metrics = _convertToMetrics(p);
          for (final m in metrics) {
            final key = '${m.date}|${m.metric}';

            if (fitbitPreferredTypes.contains(m.metric)) {
              // Always accumulate into the "all sources" fallback.
              _aggAdd(allAgg, key, m, p.dateFrom);
              // Only accumulate into Fitbit map if this record is from Fitbit.
              if (_isFitbit(p)) {
                _aggAdd(fitbitAgg, key, m, p.dateFrom);
              }
            } else {
              _aggAdd(agg, key, m, p.dateFrom);
            }
          }
        }
      } catch (_) {
        errors++;
      }
    }

    // Merge: for fitbitPreferred types, use Fitbit data if we have any,
    // otherwise fall back to all-source data.
    for (final key in {...fitbitAgg.keys, ...allAgg.keys}) {
      agg[key] = fitbitAgg[key] ?? allAgg[key]!;
    }

    // ── Resolve aggregations ──────────────────────────────────────────
    final metrics = <HealthMetric>[];
    for (final entry in agg.entries) {
      final a = entry.value;
      final m = a.template;

      double finalVal;
      if (sumTypes.contains(m.metric)) {
        finalVal = a.sum;
      } else if (avgTypes.contains(m.metric)) {
        finalVal = a.avg;
      } else if (maxTypes.contains(m.metric)) {
        finalVal = a.max;
        // Derive sleeping HR from the spread of resting-HR readings.
        if (m.metric == MetricType.restingHrBpm &&
            a.count > 1 &&
            (a.max - a.min) > 3) {
          metrics.add(HealthMetric(
            date:   m.date,
            metric: MetricType.sleepingHrBpm,
            value:  a.min,
            unit:   'bpm',
            source: m.source,
          ));
        }
      } else {
        finalVal = a.latest;
      }

      metrics.add(HealthMetric(
        date:   m.date,
        metric: m.metric,
        value:  finalVal,
        unit:   m.unit,
        source: m.source,
        notes:  m.notes,
      ));
    }

    if (metrics.isNotEmpty) {
      await _db.upsertMetrics(metrics);
      saved = metrics.length;
    }

    return SyncResult(saved: saved, errors: errors);
  }

  void _aggAdd(Map<String, _MetricAgg> map, String key,
      HealthMetric m, DateTime ts) {
    final existing = map[key];
    if (existing == null) {
      map[key] = _MetricAgg(m, ts);
    } else {
      existing.add(m.value, ts);
    }
  }

  // ── Debug helper ───────────────────────────────────────────────────────

  /// Returns a human-readable dump of raw step and sleep records for the
  /// last [lookbackHours] hours, showing each record's source app.
  Future<String> debugHealthData({int lookbackHours = 36}) async {
    final now   = DateTime.now();
    final since = now.subtract(Duration(hours: lookbackHours));
    final buf   = StringBuffer();

    // ── Steps ──
    try {
      final pts = await _health.getHealthDataFromTypes(
        types: [HealthDataType.STEPS],
        startTime: since,
        endTime: now,
      );
      final sorted = pts.toList()
        ..sort((a, b) => a.dateFrom.compareTo(b.dateFrom));

      final fitbitPts = sorted.where(_isFitbit).toList();
      final otherPts  = sorted.where((p) => !_isFitbit(p)).toList();

      buf.writeln('=== STEPS (${pts.length} records) ===');
      buf.writeln('Fitbit records (${fitbitPts.length}):');
      double fitbitSum = 0;
      for (final p in fitbitPts) {
        final dur = p.dateTo.difference(p.dateFrom).inMinutes;
        final val = (p.value as NumericHealthValue).numericValue;
        fitbitSum += val.toDouble();
        buf.writeln('  ${p.dateFrom.toLocal().toString().substring(11,16)}'
            '-${p.dateTo.toLocal().toString().substring(11,16)}'
            ' (${dur}min): $val  [${p.sourceName} / ${p.sourceId}]');
      }
      buf.writeln('  → Fitbit SUM: $fitbitSum');
      buf.writeln('Other source records (${otherPts.length}):');
      for (final p in otherPts.take(5)) {
        final val = (p.value as NumericHealthValue).numericValue;
        buf.writeln('  ${p.dateFrom.toLocal().toString().substring(11,16)}'
            ': $val  [${p.sourceName} / ${p.sourceId}]');
      }
      if (otherPts.length > 5) buf.writeln('  ... ${otherPts.length - 5} more');
    } catch (e) {
      buf.writeln('STEPS error: $e');
    }

    // ── Sleep ──
    try {
      final pts = await _health.getHealthDataFromTypes(
        types: [
          HealthDataType.SLEEP_ASLEEP,
          HealthDataType.SLEEP_DEEP,
          HealthDataType.SLEEP_REM,
          HealthDataType.SLEEP_LIGHT,
        ],
        startTime: since,
        endTime: now,
      );
      final sorted = pts.toList()
        ..sort((a, b) => a.dateFrom.compareTo(b.dateFrom));

      buf.writeln('\n=== SLEEP (${pts.length} records) ===');
      double totalMin = 0;
      for (final p in sorted) {
        final dur  = p.dateTo.difference(p.dateFrom).inMinutes;
        final from = p.dateFrom.toLocal().toString().substring(5, 16);
        final to   = p.dateTo.toLocal().toString().substring(5, 16);
        final type = p.type.name.replaceAll('SLEEP_', '');
        buf.writeln('  $type $from→$to (${dur}min)'
            '  [${p.sourceName}]');
        if (p.type != HealthDataType.SLEEP_ASLEEP) totalMin += dur;
      }
      buf.writeln('  → deep+rem+light total: '
          '${totalMin.toStringAsFixed(0)} min'
          ' = ${(totalMin / 60).toStringAsFixed(2)} hrs');
    } catch (e) {
      buf.writeln('SLEEP error: $e');
    }

    return buf.toString();
  }

  // ── Convert HealthDataPoint → HealthMetric(s) ──────────────────────────

  List<HealthMetric> _convertToMetrics(HealthDataPoint p) {
    final src = 'health_connect';

    final isSleep = p.type == HealthDataType.SLEEP_ASLEEP ||
        p.type == HealthDataType.SLEEP_DEEP ||
        p.type == HealthDataType.SLEEP_REM ||
        p.type == HealthDataType.SLEEP_LIGHT;

    // Sleep date: attribute all segments from a night to the wake-up date.
    // Segments starting at 18:00+ are evening lead-ins → shift +1 day.
    final date = isSleep
        ? _sleepSessionDate(p.dateFrom, p.dateTo)
        : p.dateFrom.toLocal().toIso8601String().substring(0, 10);

    if (p.type == HealthDataType.WORKOUT) {
      return _convertWorkout(p, date, src);
    }

    final numValue = p.value is NumericHealthValue
        ? (p.value as NumericHealthValue).numericValue.toDouble()
        : null;
    if (numValue == null) return [];

    switch (p.type) {
      case HealthDataType.STEPS:
        return [HealthMetric(date: date, metric: MetricType.steps,
            value: numValue, unit: 'steps', source: src)];

      case HealthDataType.RESTING_HEART_RATE:
        return [HealthMetric(date: date, metric: MetricType.restingHrBpm,
            value: numValue, unit: 'bpm', source: src)];

      case HealthDataType.HEART_RATE_VARIABILITY_RMSSD:
        return [HealthMetric(date: date, metric: MetricType.hrvRmssdMs,
            value: numValue, unit: 'ms', source: src)];

      case HealthDataType.WEIGHT:
        return [HealthMetric(date: date, metric: MetricType.weightKg,
            value: numValue, unit: 'kg', source: src)];

      case HealthDataType.HEIGHT:
        return [HealthMetric(date: date, metric: MetricType.heightCm,
            value: numValue * 100, unit: 'cm', source: src)];

      case HealthDataType.BODY_FAT_PERCENTAGE:
        return [HealthMetric(date: date, metric: MetricType.bodyFatPct,
            value: numValue, unit: '%', source: src)];

      case HealthDataType.SLEEP_ASLEEP:
        return [HealthMetric(date: date, metric: MetricType.sleepDurationHr,
            value: numValue / 60, unit: 'hrs', source: src)];

      case HealthDataType.SLEEP_DEEP:
        return [
          HealthMetric(date: date, metric: MetricType.sleepDeepMin,
              value: numValue, unit: 'min', source: src),
          HealthMetric(date: date, metric: MetricType.sleepDurationHr,
              value: numValue / 60, unit: 'hrs', source: src),
        ];

      case HealthDataType.SLEEP_REM:
        return [
          HealthMetric(date: date, metric: MetricType.sleepRemMin,
              value: numValue, unit: 'min', source: src),
          HealthMetric(date: date, metric: MetricType.sleepDurationHr,
              value: numValue / 60, unit: 'hrs', source: src),
        ];

      case HealthDataType.SLEEP_LIGHT:
        return [
          HealthMetric(date: date, metric: MetricType.sleepLightMin,
              value: numValue, unit: 'min', source: src),
          HealthMetric(date: date, metric: MetricType.sleepDurationHr,
              value: numValue / 60, unit: 'hrs', source: src),
        ];

      case HealthDataType.BLOOD_OXYGEN:
        return [HealthMetric(date: date, metric: MetricType.spo2Pct,
            value: numValue * 100, unit: '%', source: src)];

      case HealthDataType.RESPIRATORY_RATE:
        return [HealthMetric(date: date, metric: MetricType.breathingRate,
            value: numValue, unit: 'brpm', source: src)];

      case HealthDataType.ACTIVE_ENERGY_BURNED:
        return [HealthMetric(date: date, metric: MetricType.activeCalories,
            value: numValue, unit: 'kcal', source: src)];

      default:
        return [];
    }
  }

  String _sleepSessionDate(DateTime dateFrom, DateTime dateTo) {
    final local = dateFrom.toLocal();
    if (local.hour >= 18) {
      return local.add(const Duration(days: 1))
          .toIso8601String().substring(0, 10);
    }
    return dateTo.toLocal().toIso8601String().substring(0, 10);
  }

  List<HealthMetric> _convertWorkout(HealthDataPoint p, String date, String src) {
    final results = <HealthMetric>[];
    final durationMin = p.dateTo.difference(p.dateFrom).inMinutes.toDouble();
    if (durationMin > 0) {
      String activityName = 'workout';
      if (p.value is WorkoutHealthValue) {
        activityName = _workoutTypeName(
            (p.value as WorkoutHealthValue).workoutActivityType);
      }
      results.add(HealthMetric(date: date, metric: MetricType.workoutDurationMin,
          value: durationMin, unit: 'min', source: src, notes: activityName));
    }
    if (p.value is WorkoutHealthValue) {
      final w = p.value as WorkoutHealthValue;
      final cal = w.totalEnergyBurned?.toDouble();
      if (cal != null && cal > 0) {
        results.add(HealthMetric(date: date, metric: MetricType.workoutCalories,
            value: cal, unit: 'kcal', source: src));
      }
      final dist = w.totalDistance?.toDouble();
      if (dist != null && dist > 0) {
        results.add(HealthMetric(date: date, metric: MetricType.workoutDistanceM,
            value: dist, unit: 'm', source: src));
      }
    }
    return results;
  }

  String _workoutTypeName(HealthWorkoutActivityType type) {
    return type.name.replaceAll('_', ' ').toLowerCase().replaceAllMapped(
      RegExp(r'\b\w'), (m) => m.group(0)!.toUpperCase(),
    );
  }
}

class SyncResult {
  final int saved;
  final int errors;
  const SyncResult({required this.saved, required this.errors});

  @override
  String toString() => 'SyncResult(saved: $saved, errors: $errors)';
}

/// Per-(date, metric) accumulator.
class _MetricAgg {
  final HealthMetric template;
  double   _sum;
  int      _count;
  double   _max;
  double   _min;
  double   _latestVal;
  DateTime _latestTs;

  _MetricAgg(this.template, DateTime ts)
      : _sum       = template.value,
        _count     = 1,
        _max       = template.value,
        _min       = template.value,
        _latestVal = template.value,
        _latestTs  = ts;

  void add(double value, DateTime ts) {
    _sum += value;
    _count++;
    if (value > _max) _max = value;
    if (value < _min) _min = value;
    if (ts.isAfter(_latestTs)) { _latestVal = value; _latestTs = ts; }
  }

  double get sum    => _sum;
  double get avg    => _sum / _count;
  double get max    => _max;
  double get min    => _min;
  double get latest => _latestVal;
  int    get count  => _count;
}
