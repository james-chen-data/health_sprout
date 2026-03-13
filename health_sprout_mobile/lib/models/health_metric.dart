/// A single health measurement stored in the local SQLite database.
///
/// Every data point — whether from Health Connect, Fitbit, or manual entry —
/// is stored as a row in this schema. The AI always reads from the DB;
/// it never guesses or hallucinates metric values.
class HealthMetric {
  final int?   id;
  final String date;       // ISO-8601 date: "2026-03-11"
  final String metric;     // See MetricType constants below
  final double value;
  final String unit;       // "bpm", "kg", "ms", "%", "steps", etc.
  final String source;     // "health_connect", "fitbit", "manual"
  final String? notes;

  const HealthMetric({
    this.id,
    required this.date,
    required this.metric,
    required this.value,
    required this.unit,
    required this.source,
    this.notes,
  });

  Map<String, dynamic> toMap() => {
    'id':     id,
    'date':   date,
    'metric': metric,
    'value':  value,
    'unit':   unit,
    'source': source,
    'notes':  notes,
  };

  factory HealthMetric.fromMap(Map<String, dynamic> m) => HealthMetric(
    id:     m['id'] as int?,
    date:   m['date'] as String,
    metric: m['metric'] as String,
    value:  (m['value'] as num).toDouble(),
    unit:   m['unit'] as String,
    source: m['source'] as String,
    notes:  m['notes'] as String?,
  );

  @override
  String toString() =>
      'HealthMetric($date | $metric: $value $unit | source: $source)';
}

/// Canonical metric name constants — used as the `metric` column value.
/// Always use these constants so queries are consistent.
class MetricType {
  // Body composition
  static const String weightKg        = 'weight_kg';
  static const String bodyFatPct      = 'body_fat_pct';
  static const String bmi             = 'bmi';
  static const String heightCm        = 'height_cm';
  static const String bmrKcal         = 'bmr_kcal';           // Basal metabolic rate

  // Heart
  static const String restingHrBpm    = 'resting_hr_bpm';
  static const String sleepingHrBpm   = 'sleeping_hr_bpm';    // Avg HR during sleep
  static const String hrvRmssdMs      = 'hrv_rmssd_ms';       // HRV — RMSSD in milliseconds

  // Respiratory / blood oxygen
  static const String spo2Pct         = 'spo2_pct';           // Blood oxygen %
  static const String breathingRate   = 'breathing_rate';     // Breaths per minute (during sleep)

  // Activity
  static const String steps           = 'steps';
  static const String activeCalories  = 'active_calories_kcal';

  // Workouts
  static const String workoutType       = 'workout_type';
  static const String workoutDurationMin = 'workout_duration_min';
  static const String workoutCalories   = 'workout_calories_kcal';
  static const String workoutDistanceM  = 'workout_distance_m';

  // Sleep
  static const String sleepDurationHr = 'sleep_duration_hr';
  static const String sleepDeepMin    = 'sleep_deep_min';
  static const String sleepRemMin     = 'sleep_rem_min';
  static const String sleepLightMin   = 'sleep_light_min';
  static const String sleepEfficiency = 'sleep_efficiency_pct';

  // Units map — used for display
  static const Map<String, String> units = {
    weightKg:        'kg',
    bodyFatPct:      '%',
    bmi:             '',
    heightCm:        'cm',
    bmrKcal:         'kcal',
    restingHrBpm:    'bpm',
    sleepingHrBpm:   'bpm',
    hrvRmssdMs:      'ms',
    spo2Pct:         '%',
    breathingRate:   'brpm',
    steps:           'steps',
    activeCalories:      'kcal',
    workoutDurationMin:  'min',
    workoutCalories:     'kcal',
    workoutDistanceM:    'm',
    sleepDurationHr: 'hrs',
    sleepDeepMin:    'min',
    sleepRemMin:     'min',
    sleepLightMin:   'min',
    sleepEfficiency: '%',
  };

  // Human-readable labels for display
  static const Map<String, String> labels = {
    weightKg:        'Weight',
    bodyFatPct:      'Body Fat',
    bmi:             'BMI',
    heightCm:        'Height',
    bmrKcal:         'BMR',
    restingHrBpm:    'Resting Heart Rate',
    sleepingHrBpm:   'Sleeping Heart Rate',
    hrvRmssdMs:      'HRV (RMSSD)',
    spo2Pct:         'Blood Oxygen (SpO₂)',
    breathingRate:   'Breathing Rate',
    steps:           'Daily Steps',
    activeCalories:      'Active Calories',
    workoutDurationMin:  'Workout Duration',
    workoutCalories:     'Workout Calories',
    workoutDistanceM:    'Workout Distance',
    sleepDurationHr: 'Sleep Duration',
    sleepDeepMin:    'Deep Sleep',
    sleepRemMin:     'REM Sleep',
    sleepLightMin:   'Light Sleep',
    sleepEfficiency: 'Sleep Efficiency',
  };
}
