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
    HealthDataType.HEART_RATE,
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
  ];

  // ── Request permissions ────────────────────────────────────────────────

  Future<bool> requestPermissions() async {
    // Android 13+ needs activity recognition
    await Permission.activityRecognition.request();

    final permissions = _types
        .map((_) => HealthDataAccess.READ)
        .toList();

    try {
      final granted = await _health.requestAuthorization(
        _types,
        permissions: permissions,
      );
      return granted;
    } catch (e) {
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
  /// Returns the number of new data points written.
  Future<SyncResult> syncToDatabase({int days = 180}) async {
    final now   = DateTime.now();
    final start = now.subtract(Duration(days: days));
    int   saved = 0;
    int   errors = 0;

    // Use a map to deduplicate: (date, metricType) → latest-timestamp reading
    // This prevents older readings (e.g. Fitbit daily estimates) from
    // overwriting the most recent direct measurement on the same day.
    final Map<String, ({HealthMetric metric, DateTime timestamp})> best = {};

    for (final type in _types) {
      try {
        final points = await _health.getHealthDataFromTypes(
          types:     [type],
          startTime: start,
          endTime:   now,
        );

        for (final p in points) {
          final m = _convertToMetric(p);
          if (m == null) continue;
          final key = '${m.date}|${m.metric}';
          // Keep the reading with the latest dateFrom timestamp
          final existing = best[key];
          if (existing == null || p.dateFrom.isAfter(existing.timestamp)) {
            best[key] = (metric: m, timestamp: p.dateFrom);
          }
        }
      } catch (_) {
        errors++;
      }
    }

    final metrics = best.values.map((e) => e.metric).toList();

    if (metrics.isNotEmpty) {
      await _db.upsertMetrics(metrics);
      saved = metrics.length;
    }

    return SyncResult(saved: saved, errors: errors);
  }

  // ── Convert HealthDataPoint → HealthMetric ─────────────────────────────

  HealthMetric? _convertToMetric(HealthDataPoint p) {
    // Use LOCAL time for the date — avoids UTC offset pushing evening readings
    // into the next calendar day (common in US timezones).
    final date = p.dateFrom.toLocal().toIso8601String().substring(0, 10);
    final src  = 'health_connect';

    double? val;
    String? metricType;
    String? unit;

    final numValue = p.value is NumericHealthValue
        ? (p.value as NumericHealthValue).numericValue.toDouble()
        : null;

    if (numValue == null) return null;

    switch (p.type) {
      case HealthDataType.STEPS:
        metricType = MetricType.steps;
        val  = numValue;
        unit = 'steps';

      case HealthDataType.HEART_RATE:
        // Skip — we use RESTING_HEART_RATE for the daily metric
        return null;

      case HealthDataType.RESTING_HEART_RATE:
        metricType = MetricType.restingHrBpm;
        val  = numValue;
        unit = 'bpm';

      case HealthDataType.HEART_RATE_VARIABILITY_RMSSD:
        metricType = MetricType.hrvRmssdMs;
        val  = numValue;
        unit = 'ms';

      case HealthDataType.WEIGHT:
        metricType = MetricType.weightKg;
        // Health Connect stores weight in kg
        val  = numValue;
        unit = 'kg';

      case HealthDataType.HEIGHT:
        metricType = MetricType.heightCm;
        val  = numValue * 100; // metres → cm
        unit = 'cm';

      case HealthDataType.BODY_FAT_PERCENTAGE:
        metricType = MetricType.bodyFatPct;
        val  = numValue;
        unit = '%';

      case HealthDataType.SLEEP_ASLEEP:
        metricType = MetricType.sleepDurationHr;
        val  = numValue / 60; // minutes → hours
        unit = 'hrs';

      case HealthDataType.SLEEP_DEEP:
        metricType = MetricType.sleepDeepMin;
        val  = numValue;
        unit = 'min';

      case HealthDataType.SLEEP_REM:
        metricType = MetricType.sleepRemMin;
        val  = numValue;
        unit = 'min';

      case HealthDataType.SLEEP_LIGHT:
        metricType = MetricType.sleepLightMin;
        val  = numValue;
        unit = 'min';

      case HealthDataType.BLOOD_OXYGEN:
        metricType = MetricType.spo2Pct;
        val  = numValue * 100; // 0-1 → percentage
        unit = '%';

      case HealthDataType.RESPIRATORY_RATE:
        metricType = MetricType.breathingRate;
        val  = numValue;
        unit = 'brpm';

      case HealthDataType.ACTIVE_ENERGY_BURNED:
        metricType = MetricType.activeCalories;
        val  = numValue;
        unit = 'kcal';

      default:
        return null;
    }

    if (metricType == null || val == null) return null;

    return HealthMetric(
      date:   date,
      metric: metricType,
      value:  val,
      unit:   unit!,
      source: src,
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
