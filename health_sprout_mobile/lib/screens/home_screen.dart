import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../db/database.dart';
import '../health/health_service.dart';
import '../models/health_metric.dart';
import '../models/unit_prefs.dart';
import 'metrics_screen.dart';
import 'chat_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final HealthDatabase _db      = HealthDatabase();
  final HealthService  _health  = HealthService();

  Map<String, HealthMetric> _latest   = {};
  bool      _syncing   = false;
  String    _syncStatus = '';
  int       _totalRows  = 0;
  UnitPrefs _units      = UnitPrefs();

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    final latest = await _db.getLatestAll();
    final count  = await _db.countRows();
    final units  = await UnitPrefs.load();
    if (mounted) {
      setState(() {
        _latest    = latest;
        _totalRows = count;
        _units     = units;
      });
    }
  }

  Future<void> _showDebugData() async {
    final dump = await _health.debugHealthData(lookbackHours: 36);
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Debug: Raw Health Data'),
        content: SingleChildScrollView(
          child: SelectableText(
            dump,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _syncHealthConnect() async {
    setState(() { _syncing = true; _syncStatus = 'Requesting permissions…'; });

    final granted = await _health.requestPermissions();
    if (!granted) {
      setState(() {
        _syncing    = false;
        _syncStatus = 'Permission denied — grant Health Connect access in Settings.';
      });
      return;
    }

    setState(() { _syncStatus = 'Syncing 6 months of data…'; });
    final result = await _health.syncToDatabase(days: 180);
    await _loadDashboard();

    setState(() {
      _syncing    = false;
      _syncStatus = '✓ Synced ${result.saved} data points';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F9F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
        title: const Text('🌿 Health Sprout',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report_outlined),
            tooltip: 'Debug health data sources',
            onPressed: _showDebugData,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()))
                .then((_) => _loadDashboard()),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadDashboard,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // ── Sync card ───────────────────────────────────────────────
              _SyncCard(
                syncing:    _syncing,
                status:     _syncStatus,
                totalRows:  _totalRows,
                onSync:     _syncHealthConnect,
              ),

              const SizedBox(height: 20),

              // ── Latest metrics grid ─────────────────────────────────────
              if (_latest.isNotEmpty) ...[
                const Text('Latest Readings',
                    style: TextStyle(fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1B5E20))),
                const SizedBox(height: 12),
                _MetricsGrid(latest: _latest, units: _units),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.push(context,
                      MaterialPageRoute(
                          builder: (_) => const MetricsScreen())),
                  child: const Text('View full history →'),
                ),
              ] else ...[
                const _EmptyState(),
              ],

              const SizedBox(height: 24),

              // ── AI modules ─────────────────────────────────────────────
              const Text('AI Advisors',
                  style: TextStyle(fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1B5E20))),
              const SizedBox(height: 12),

              _AdvisorCard(
                icon:     '💪',
                title:    'Body Recomposition Coach',
                subtitle: 'Personalized workout plan based on your health data',
                color:    const Color(0xFF1565C0),
                onTap:    () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => const ChatScreen(mode: ChatMode.bodyCoach))),
              ),
              const SizedBox(height: 12),
              _AdvisorCard(
                icon:     '🌱',
                title:    'Sprout & Microgreens Advisor',
                subtitle: 'Find the best sprouts for your health goals',
                color:    const Color(0xFF2E7D32),
                onTap:    () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => const ChatScreen(mode: ChatMode.sproutAdvisor))),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Sub-widgets ──────────────────────────────────────────────────────────────

class _SyncCard extends StatelessWidget {
  final bool   syncing;
  final String status;
  final int    totalRows;
  final VoidCallback onSync;

  const _SyncCard({
    required this.syncing,
    required this.status,
    required this.totalRows,
    required this.onSync,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.sync, color: Color(0xFF2E7D32)),
              const SizedBox(width: 8),
              const Text('Health Connect',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const Spacer(),
              if (totalRows > 0)
                Text('$totalRows readings in DB',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12)),
            ]),
            if (status.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(status, style: TextStyle(color: Colors.grey[700], fontSize: 13)),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32),
                  foregroundColor: Colors.white,
                ),
                onPressed: syncing ? null : onSync,
                icon: syncing
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.download_rounded),
                label: Text(syncing ? 'Syncing…' : 'Sync Health Connect Data'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricsGrid extends StatelessWidget {
  final Map<String, HealthMetric> latest;
  final UnitPrefs units;

  const _MetricsGrid({required this.latest, required this.units});

  static const _priority = [
    MetricType.weightKg,
    MetricType.bodyFatPct,
    MetricType.restingHrBpm,
    MetricType.sleepingHrBpm,
    MetricType.hrvRmssdMs,
    MetricType.sleepDurationHr,
    MetricType.spo2Pct,
    MetricType.steps,
    MetricType.breathingRate,
    MetricType.bmrKcal,
    MetricType.workoutDurationMin,
    MetricType.workoutCalories,
    MetricType.workoutDistanceM,
  ];

  @override
  Widget build(BuildContext context) {
    final items = _priority
        .where((k) => latest.containsKey(k))
        .map((k) => latest[k]!)
        .toList();

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount:    2,
        mainAxisSpacing:   10,
        crossAxisSpacing:  10,
        childAspectRatio:  1.6,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) => _MetricTile(metric: items[i], units: units),
    );
  }
}

class _MetricTile extends StatelessWidget {
  final HealthMetric metric;
  final UnitPrefs units;
  const _MetricTile({required this.metric, required this.units});

  @override
  Widget build(BuildContext context) {
    final label     = MetricType.labels[metric.metric] ?? metric.metric;
    final dispVal   = units.displayValue(metric.value, metric.metric);
    final dispUnit  = units.displayUnit(metric.metric, metric.unit);
    final val       = dispVal % 1 == 0
        ? dispVal.toInt().toString()
        : dispVal.toStringAsFixed(1);

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment:  MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('$val ',
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.bold,
                        color: Color(0xFF1B5E20))),
                Text(dispUnit,
                    style: TextStyle(fontSize: 12, color: Colors.grey[500])),
              ],
            ),
            Text(metric.date,
                style: TextStyle(fontSize: 10, color: Colors.grey[400])),
          ],
        ),
      ),
    );
  }
}

class _AdvisorCard extends StatelessWidget {
  final String   icon;
  final String   title;
  final String   subtitle;
  final Color    color;
  final VoidCallback onTap;

  const _AdvisorCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Text(icon, style: const TextStyle(fontSize: 32)),
            const SizedBox(width: 16),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(fontSize: 16,
                        fontWeight: FontWeight.bold, color: color)),
                const SizedBox(height: 4),
                Text(subtitle,
                    style: TextStyle(fontSize: 13, color: Colors.grey[600])),
              ],
            )),
            Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey[400]),
          ]),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(children: [
          const Text('📊', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          Text('No health data yet',
              style: TextStyle(fontSize: 16, color: Colors.grey[600])),
          const SizedBox(height: 6),
          Text('Tap "Sync Health Connect Data" to get started',
              style: TextStyle(fontSize: 13, color: Colors.grey[500])),
        ]),
      ),
    );
  }
}

// Silence unused import warning for intl
String _formatDate(DateTime d) => DateFormat('MMM d').format(d);
