import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../db/database.dart';
import '../models/health_metric.dart';
import '../models/unit_prefs.dart';
import 'chat_screen.dart';

class MetricsScreen extends StatefulWidget {
  const MetricsScreen({super.key});

  @override
  State<MetricsScreen> createState() => _MetricsScreenState();
}

class _MetricsScreenState extends State<MetricsScreen> {
  final HealthDatabase _db = HealthDatabase();

  String _selectedMetric = MetricType.weightKg;
  int    _selectedDays   = 90;
  List<HealthMetric> _data = [];
  bool   _loading          = true;
  UnitPrefs _units         = UnitPrefs();

  static const _metricOptions = [
    MetricType.weightKg,
    MetricType.bodyFatPct,
    MetricType.restingHrBpm,
    MetricType.sleepingHrBpm,
    MetricType.hrvRmssdMs,
    MetricType.spo2Pct,
    MetricType.steps,
    MetricType.sleepDurationHr,
    MetricType.sleepDeepMin,
    MetricType.sleepRemMin,
    MetricType.breathingRate,
    MetricType.activeCalories,
    MetricType.workoutDurationMin,
    MetricType.workoutCalories,
    MetricType.workoutDistanceM,
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() { _loading = true; });
    final data  = await _db.getMetricHistory(
        _selectedMetric, days: _selectedDays);
    final units = await UnitPrefs.load();
    setState(() { _data = data; _loading = false; _units = units; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F9F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
        title: const Text('Health History'),
      ),
      body: Column(children: [

        // ── Controls ───────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value:       _selectedMetric,
                decoration:  const InputDecoration(
                    labelText: 'Metric',
                    border:    OutlineInputBorder(),
                    isDense:   true),
                items: _metricOptions.map((m) => DropdownMenuItem(
                  value: m,
                  child: Text(MetricType.labels[m] ?? m,
                      style: const TextStyle(fontSize: 13)),
                )).toList(),
                onChanged: (v) {
                  if (v != null) {
                    setState(() { _selectedMetric = v; });
                    _loadData();
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            DropdownButton<int>(
              value: _selectedDays,
              items: const [
                DropdownMenuItem(value: 30,  child: Text('30d')),
                DropdownMenuItem(value: 90,  child: Text('90d')),
                DropdownMenuItem(value: 180, child: Text('6m')),
                DropdownMenuItem(value: 365, child: Text('1y')),
              ],
              onChanged: (v) {
                if (v != null) {
                  setState(() { _selectedDays = v; });
                  _loadData();
                }
              },
            ),
          ]),
        ),

        // ── Trend card ────────────────────────────────────────────────────
        if (_data.length >= 2) _TrendCard(data: _data, metric: _selectedMetric, units: _units),

        // ── Chart ─────────────────────────────────────────────────────────
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _data.isEmpty
                  ? _emptyView()
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 16, 8),
                      child: _MetricChart(
                          data:   _data,
                          metric: _selectedMetric,
                          units:  _units),
                    ),
        ),

        // ── Stats row ────────────────────────────────────────────────────
        if (_data.isNotEmpty) _StatsRow(data: _data, metric: _selectedMetric, units: _units),

        // ── AI Insights button ──────────────────────────────────────────
        if (_data.length >= 3)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: Text('AI: Analyze my ${MetricType.labels[_selectedMetric] ?? _selectedMetric} trends'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1565C0),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () {
                  final label = MetricType.labels[_selectedMetric] ?? _selectedMetric;
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => ChatScreen(
                      mode: ChatMode.bodyCoach,
                      initialMessage:
                        'Analyze my $label trends over the last ${_selectedDays} days. '
                        'What patterns do you see? Are there any correlations with my '
                        'sleep, heart rate, HRV, or activity data? '
                        'Give me specific insights and actionable suggestions.',
                    ),
                  ));
                },
              ),
            ),
          ),
      ]),
    );
  }

  Widget _emptyView() => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.bar_chart, size: 64, color: Colors.grey[300]),
      const SizedBox(height: 8),
      Text('No ${MetricType.labels[_selectedMetric] ?? _selectedMetric} data',
          style: TextStyle(color: Colors.grey[600], fontSize: 16)),
      const SizedBox(height: 4),
      Text('Sync Health Connect from the home screen',
          style: TextStyle(color: Colors.grey[500], fontSize: 13)),
    ]),
  );
}

// ── Trend card ──────────────────────────────────────────────────────────────

class _TrendCard extends StatelessWidget {
  final List<HealthMetric> data;
  final String metric;
  final UnitPrefs units;
  const _TrendCard({required this.data, required this.metric, required this.units});

  @override
  Widget build(BuildContext context) {
    final latestRaw = data.last.value;
    final latest    = units.displayValue(latestRaw, metric);
    final unit      = units.displayUnit(metric, data.last.unit);
    final label     = MetricType.labels[metric] ?? metric;

    // Compare latest to 7-day-ago value (or earliest if less data)
    final weekAgoIdx = data.length > 7 ? data.length - 8 : 0;
    final previousRaw = data[weekAgoIdx].value;
    final previous    = units.displayValue(previousRaw, metric);
    final change     = latest - previous;
    final changePct  = previous != 0 ? (change / previous * 100) : 0.0;

    // Determine if change is good/bad based on metric type
    final isPositiveGood = _isHigherBetter(metric);
    final isGood = isPositiveGood ? change > 0 : change < 0;
    final isNeutral = change.abs() < 0.01;

    final trendColor = isNeutral ? Colors.grey
        : isGood ? const Color(0xFF2E7D32) : Colors.red[700]!;
    final trendIcon = isNeutral ? Icons.trending_flat
        : change > 0 ? Icons.trending_up : Icons.trending_down;

    String fmt(double v) => v.abs() < 10
        ? v.toStringAsFixed(2)
        : v.toStringAsFixed(1);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Card(
        elevation: 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(children: [
            // Current value
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              const SizedBox(height: 2),
              Text('${fmt(latest)} $unit',
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold,
                      color: Color(0xFF1B5E20))),
              Text('as of ${data.last.date}',
                  style: TextStyle(fontSize: 11, color: Colors.grey[500])),
            ]),
            const Spacer(),
            // Trend
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: trendColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(trendIcon, size: 20, color: trendColor),
                const SizedBox(width: 4),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('${change >= 0 ? '+' : ''}${fmt(change)}',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold,
                          color: trendColor)),
                  Text('${changePct >= 0 ? '+' : ''}${changePct.toStringAsFixed(1)}%',
                      style: TextStyle(fontSize: 11, color: trendColor)),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  /// Returns true if a higher value is generally "better" for this metric.
  static bool _isHigherBetter(String metric) {
    switch (metric) {
      case MetricType.hrvRmssdMs:
      case MetricType.steps:
      case MetricType.sleepDurationHr:
      case MetricType.sleepDeepMin:
      case MetricType.sleepRemMin:
      case MetricType.spo2Pct:
      case MetricType.activeCalories:
      case MetricType.workoutDurationMin:
      case MetricType.workoutCalories:
      case MetricType.workoutDistanceM:
        return true;
      default:
        return false; // weight, body fat, resting HR, breathing rate — lower is better
    }
  }
}

// ── Chart ────────────────────────────────────────────────────────────────────

class _MetricChart extends StatefulWidget {
  final List<HealthMetric> data;
  final String             metric;
  final UnitPrefs          units;
  const _MetricChart({required this.data, required this.metric, required this.units});

  @override
  State<_MetricChart> createState() => _MetricChartState();
}

class _MetricChartState extends State<_MetricChart> {
  double _convert(double v) => widget.units.displayValue(v, widget.metric);

  /// Calculate 7-day simple moving average
  List<FlSpot> _movingAverage() {
    final data = widget.data;
    if (data.length < 7) return [];

    final spots = <FlSpot>[];
    for (int i = 6; i < data.length; i++) {
      double sum = 0;
      for (int j = i - 6; j <= i; j++) {
        sum += _convert(data[j].value);
      }
      spots.add(FlSpot(i.toDouble(), sum / 7));
    }
    return spots;
  }

  @override
  Widget build(BuildContext context) {
    final data  = widget.data;
    final spots = data.asMap().entries.map((e) =>
        FlSpot(e.key.toDouble(), _convert(e.value.value))).toList();
    final maSpots = _movingAverage();

    final minY = data.map((d) => _convert(d.value)).reduce((a, b) => a < b ? a : b);
    final maxY = data.map((d) => _convert(d.value)).reduce((a, b) => a > b ? a : b);
    final pad  = (maxY - minY) * 0.12 + 0.5;

    return LineChart(LineChartData(
      minY: minY - pad,
      maxY: maxY + pad,
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        getDrawingHorizontalLine: (_) =>
            FlLine(color: Colors.grey.shade200, strokeWidth: 0.8),
      ),
      titlesData: FlTitlesData(
        bottomTitles: AxisTitles(sideTitles: SideTitles(
          showTitles: true,
          interval: (data.length / 5).ceilToDouble().clamp(1, 9999),
          getTitlesWidget: (v, _) {
            final i = v.toInt();
            if (i < 0 || i >= data.length) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                data[i].date.substring(5), // MM-DD
                style: TextStyle(fontSize: 10, color: Colors.grey[600]),
              ),
            );
          },
        )),
        leftTitles: AxisTitles(sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 44,
          getTitlesWidget: (v, _) => Text(
            v.toStringAsFixed(v.abs() < 10 ? 1 : 0),
            style: TextStyle(fontSize: 10, color: Colors.grey[600]),
          ),
        )),
        topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      borderData: FlBorderData(
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade300),
          left:   BorderSide(color: Colors.grey.shade300),
        ),
      ),
      lineTouchData: LineTouchData(
        enabled: true,
        touchTooltipData: LineTouchTooltipData(
          getTooltipItems: (touchedSpots) {
            return touchedSpots.map((spot) {
              final i = spot.spotIndex;
              // Only show tooltip for the main data line (index 0)
              if (spot.barIndex != 0) return null;
              if (i < 0 || i >= data.length) return null;
              final d = data[i];
              final dispVal  = _convert(d.value);
              final dispUnit = widget.units.displayUnit(widget.metric, d.unit);
              return LineTooltipItem(
                '${d.date}\n${dispVal.toStringAsFixed(1)} $dispUnit',
                const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              );
            }).toList();
          },
        ),
      ),
      lineBarsData: [
        // Main data line
        LineChartBarData(
          spots:        spots,
          isCurved:     true,
          curveSmoothness: 0.25,
          color:        const Color(0xFF2E7D32),
          barWidth:     2.5,
          isStrokeCapRound: true,
          dotData: FlDotData(
            show: data.length <= 30,
            getDotPainter: (spot, xPercentage, bar, index) =>
                FlDotCirclePainter(
                  radius: 3,
                  color: Colors.white,
                  strokeWidth: 2,
                  strokeColor: const Color(0xFF2E7D32),
                ),
          ),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                const Color(0xFF2E7D32).withOpacity(0.15),
                const Color(0xFF2E7D32).withOpacity(0.02),
              ],
            ),
          ),
        ),
        // 7-day moving average line
        if (maSpots.isNotEmpty)
          LineChartBarData(
            spots:    maSpots,
            isCurved: true,
            curveSmoothness: 0.35,
            color:    Colors.orange.shade700,
            barWidth: 1.8,
            isStrokeCapRound: true,
            dotData:  const FlDotData(show: false),
            dashArray: [6, 4],
          ),
      ],
    ));
  }
}

// ── Stats row ────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  final List<HealthMetric> data;
  final String metric;
  final UnitPrefs units;
  const _StatsRow({required this.data, required this.metric, required this.units});

  @override
  Widget build(BuildContext context) {
    final vals   = data.map((d) => units.displayValue(d.value, metric)).toList();
    final avg    = vals.reduce((a, b) => a + b) / vals.length;
    final minVal = vals.reduce((a, b) => a < b ? a : b);
    final maxVal = vals.reduce((a, b) => a > b ? a : b);
    final unit   = units.displayUnit(metric, data.first.unit);

    String fmt(double v) => v.abs() >= 1000
        ? NumberFormat.compact().format(v)
        : v % 1 == 0 ? v.toInt().toString()
                      : v.toStringAsFixed(1);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(
          color: Colors.black.withOpacity(0.05),
          blurRadius: 4,
          offset: const Offset(0, -1),
        )],
      ),
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _Stat(label: 'Avg',    value: '${fmt(avg)} $unit',    color: const Color(0xFF1B5E20)),
          _Stat(label: 'Min',    value: '${fmt(minVal)} $unit', color: Colors.blue[700]!),
          _Stat(label: 'Max',    value: '${fmt(maxVal)} $unit', color: Colors.red[700]!),
          _Stat(label: 'Points', value: '${data.length}',       color: Colors.grey[700]!),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final Color  color;
  const _Stat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Text(value, style: TextStyle(
          fontWeight: FontWeight.bold, fontSize: 15, color: color)),
      const SizedBox(height: 2),
      Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
    ]);
  }
}
