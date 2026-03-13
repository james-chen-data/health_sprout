import 'package:shared_preferences/shared_preferences.dart';

/// User's preferred display units. All data is stored in metric (kg, cm)
/// in the database; this class only controls display conversion.
class UnitPrefs {
  static const String _prefWeight = 'unit_weight';  // 'kg' or 'lbs'
  static const String _prefLength = 'unit_length';  // 'cm' or 'in'

  // Conversion factors
  static const double kgToLbs  = 2.20462;
  static const double lbsToKg  = 1 / kgToLbs;
  static const double cmToIn   = 0.393701;
  static const double inToCm   = 1 / cmToIn;
  static const double mToMiles = 0.000621371;

  String weightUnit; // 'kg' or 'lbs'
  String lengthUnit; // 'cm' or 'in'

  UnitPrefs({this.weightUnit = 'lbs', this.lengthUnit = 'in'});

  bool get isImperial => weightUnit == 'lbs';

  /// Load saved preferences (defaults to imperial / lbs).
  static Future<UnitPrefs> load() async {
    final prefs = await SharedPreferences.getInstance();
    return UnitPrefs(
      weightUnit: prefs.getString(_prefWeight) ?? 'lbs',
      lengthUnit: prefs.getString(_prefLength) ?? 'in',
    );
  }

  /// Save preferences.
  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefWeight, weightUnit);
    await prefs.setString(_prefLength, lengthUnit);
  }

  // ── Display conversion (DB stores metric, display in user preference) ──

  /// Convert a metric value to the user's preferred display unit.
  double displayValue(double dbValue, String metricType) {
    switch (metricType) {
      case 'weight_kg':
        return weightUnit == 'lbs' ? dbValue * kgToLbs : dbValue;
      case 'height_cm':
        return lengthUnit == 'in' ? dbValue * cmToIn : dbValue;
      case 'workout_distance_m':
        // Imperial: meters → miles; Metric: meters → km
        return lengthUnit == 'in' ? dbValue * mToMiles : dbValue / 1000;
      default:
        return dbValue;
    }
  }

  /// Get the display unit string for a metric type.
  String displayUnit(String metricType, String dbUnit) {
    switch (metricType) {
      case 'weight_kg':
        return weightUnit == 'lbs' ? 'lbs' : 'kg';
      case 'height_cm':
        return lengthUnit == 'in' ? 'in' : 'cm';
      case 'workout_distance_m':
        return lengthUnit == 'in' ? 'mi' : 'km';
      default:
        return dbUnit;
    }
  }

  /// Format a value for display with the correct unit.
  String format(double dbValue, String metricType, String dbUnit) {
    final v = displayValue(dbValue, metricType);
    final u = displayUnit(metricType, dbUnit);
    return '${v.toStringAsFixed(1)} $u';
  }
}
