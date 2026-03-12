import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../db/database.dart';
import '../models/health_metric.dart';

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

  static const _metricOptions = [
    MetricType.weightKg,
    MetricType.restingHrBpm,
    MetricType.hrvRmssdMs,
    MetricType.sleepDurationHr,
    MetricType.bodyFatPct,
    MetricType.spo2Pct,
    MetricType.steps,
    MetricType.breathingRate,
    MetricType.bmrKcal,
    MetricType.sleepDeepMin,
    MetricType.sleepRemMin,
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() { _loading = true; });
    final data = await _db.getMetricHistory(
        _selectedMetric, days: _selectedDays);
    setState(() { _data = data; _loading = false; });
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

            // Metric picker
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

            // Days picker
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

        // ── Chart ──────────────────────────────────────────────────────────
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _data.isEmpty
                  ? _emptyView()
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 16, 16),
                      child: _MetricChart(
                          data:   _data,
                          metric: _selectedMetric),
                    ),
        ),

        // ── Stats row ──────────────────────────────────────────────────────
        if (_data.isNotEmpty) _StatsRow(data: _data),
      ]),
    );
  }

  Widget _emptyView() => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Text('📊', style: TextStyle(fontSize: 48)),
      const SizedBox(height: 8),
      Text('No ${MetricType.labels[_selectedMetric] ?? _selectedMetric} data',
          style: TextStyle(color: Colors.grey[600])),
      const SizedBox(height: 4),
      Text('Sync Health Connect from the home screen',
          style: TextStyle(color: Colors.grey[500], fontSize: 13)),
    ]),
  );
}

// ── Chart ────────────────────────────────────────────────────────────────────

class _MetricChart extends StatelessWidget {
  final List<HealthMetric> data;
  final String             metric;
  const _MetricChart({required this.data, required this.metric});

  @override
  Widget build(BuildContext context) {
    final spots = data.asMap().entries.map((e) =>
        FlSpot(e.key.toDouble(), e.value.value)).toList();

    final minY = data.map((d) => d.value).reduce((a, b) => a < b ? a : b);
    final maxY = data.map((d) => d.value).reduce((a, b) => a > b ? a : b);
    final pad  = (maxY - minY) * 0.1 + 1;

    return LineChart(LineChartData(
      minY: minY - pad,
      maxY: maxY + pad,
      gridData:      FlGridData(show: true,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: Colors.grey.shade200, strokeWidth: 1)),
      titlesData:    FlTitlesData(
        bottomTitles: AxisTitles(sideTitles: SideTitles(
          showTitles: true,
          interval:   (data.length / 5).ceilToDouble().clamp(1, 9999),
          getTitlesWidget: (v, _) {
            final i = v.toInt();
            if (i < 0 || i >= data.length) return const SizedBox.shrink();
            return Text(
              data[i].date.substring(5), // MM-DD
              style: const TextStyle(fontSize: 9),
            );
          },
        )),
        leftTitles: AxisTitles(sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 40,
          getTitlesWidget: (v, _) => Text(
            v.toStringAsFixed(v % 1 == 0 ? 0 : 1),
            style: const TextStyle(fontSize: 10),
          ),
        )),
        topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      borderData: FlBorderData(
          border: Border.all(color: Colors.grey.shade300)),
      lineBarsData: [LineChartBarData(
        spots:         spots,
        isCurved:      true,
        color:         const Color(0xFF2E7D32),
        barWidth:      2.5,
        dotData:       FlDotData(show: data.length < 30),
        belowBarData:  BarAreaData(
          show:  true,
          color: const Color(0xFF2E7D32).withOpacity(0.08),
        ),
      )],
    ));
  }
}

// ── Stats row ────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  final List<HealthMetric> data;
  const _StatsRow({required this.data});

  @override
  Widget build(BuildContext context) {
    final vals   = data.map((d) => d.value).toList();
    final avg    = vals.reduce((a, b) => a + b) / vals.length;
    final minVal = vals.reduce((a, b) => a < b ? a : b);
    final maxVal = vals.reduce((a, b) => a > b ? a : b);
    final unit   = data.first.unit;

    String fmt(double v) => v % 1 == 0 ? v.toInt().toString()
                                        : v.toStringAsFixed(1);

    return Container(
      color:   Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _Stat(label: 'Avg',    value: '${fmt(avg)} $unit'),
          _Stat(label: 'Min',    value: '${fmt(minVal)} $unit'),
          _Stat(label: 'Max',    value: '${fmt(maxVal)} $unit'),
          _Stat(label: 'Points', value: '${data.length}'),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Text(value, style: const TextStyle(
          fontWeight: FontWeight.bold, fontSize: 15,
          color: Color(0xFF1B5E20))),
      Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
    ]);
  }
}
