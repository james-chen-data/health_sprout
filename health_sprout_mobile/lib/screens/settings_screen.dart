import 'package:flutter/material.dart';
import '../ai/gemini_service.dart';
import '../db/database.dart';
import '../models/unit_prefs.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final GeminiService  _gemini = GeminiService();
  final HealthDatabase _db     = HealthDatabase();
  final TextEditingController _keyCtrl = TextEditingController();

  bool      _testing   = false;
  String    _keyStatus = '';
  int       _dbRows    = 0;
  UnitPrefs _units     = UnitPrefs();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final key   = await _gemini.getSavedApiKey();
    final rows  = await _db.countRows();
    final units = await UnitPrefs.load();
    setState(() {
      _keyCtrl.text = key ?? '';
      _dbRows       = rows;
      _keyStatus    = key != null && key.isNotEmpty ? '✓ Key saved' : '';
      _units        = units;
    });
  }

  Future<void> _testAndSave() async {
    final key = _keyCtrl.text.trim();
    if (key.isEmpty) return;

    setState(() { _testing = true; _keyStatus = 'Testing…'; });
    final ok = await _gemini.testApiKey(key);

    if (ok) {
      await _gemini.saveApiKey(key);
      setState(() { _keyStatus = '✓ Connected & saved'; });
    } else {
      setState(() { _keyStatus = '❌ Invalid key'; });
    }
    setState(() { _testing = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
        title: const Text('Settings'),
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [

        // ── Unit Preferences ─────────────────────────────────────────────
        const Text('Display Units',
            style: TextStyle(fontWeight: FontWeight.bold,
                fontSize: 16, color: Color(0xFF1B5E20))),
        const SizedBox(height: 12),

        // Weight unit toggle
        Row(children: [
          const Expanded(child: Text('Weight', style: TextStyle(fontSize: 15))),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'lbs', label: Text('lbs')),
              ButtonSegment(value: 'kg',  label: Text('kg')),
            ],
            selected: {_units.weightUnit},
            onSelectionChanged: (val) async {
              setState(() { _units.weightUnit = val.first; });
              await _units.save();
            },
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
            ),
          ),
        ]),
        const SizedBox(height: 8),

        // Length unit toggle
        Row(children: [
          const Expanded(child: Text('Height', style: TextStyle(fontSize: 15))),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'in', label: Text('in')),
              ButtonSegment(value: 'cm', label: Text('cm')),
            ],
            selected: {_units.lengthUnit},
            onSelectionChanged: (val) async {
              setState(() { _units.lengthUnit = val.first; });
              await _units.save();
            },
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
            ),
          ),
        ]),

        const Divider(height: 32),

        // ── Gemini API Key ─────────────────────────────────────────────────
        const Text('Gemini API Key',
            style: TextStyle(fontWeight: FontWeight.bold,
                fontSize: 16, color: Color(0xFF1B5E20))),
        const SizedBox(height: 4),
        const Text(
            'Get a free key at aistudio.google.com/apikey',
            style: TextStyle(color: Colors.grey, fontSize: 13)),
        const SizedBox(height: 8),
        TextField(
          controller:  _keyCtrl,
          obscureText: true,
          decoration:  const InputDecoration(
            hintText: 'AIza…',
            border:   OutlineInputBorder(),
            isDense:  true,
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32),
                  foregroundColor: Colors.white),
              onPressed: _testing ? null : _testAndSave,
              child: Text(_testing ? 'Testing…' : 'Test & Save Key'),
            ),
          ),
          if (_keyStatus.isNotEmpty) ...[
            const SizedBox(width: 12),
            Text(_keyStatus,
                style: TextStyle(
                    color: _keyStatus.startsWith('✓')
                        ? Colors.green : Colors.red,
                    fontSize: 13)),
          ],
        ]),

        const Divider(height: 32),

        // ── Database info ──────────────────────────────────────────────────
        const Text('Local Database',
            style: TextStyle(fontWeight: FontWeight.bold,
                fontSize: 16, color: Color(0xFF1B5E20))),
        const SizedBox(height: 8),
        Text('$_dbRows health readings stored on this device',
            style: TextStyle(color: Colors.grey[600])),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon:  const Icon(Icons.delete_outline, color: Colors.red),
          label: const Text('Clear all data',
              style: TextStyle(color: Colors.red)),
          onPressed: () => _confirmClear(context),
        ),

        const Divider(height: 32),

        // ── About ──────────────────────────────────────────────────────────
        const Text('About',
            style: TextStyle(fontWeight: FontWeight.bold,
                fontSize: 16, color: Color(0xFF1B5E20))),
        const SizedBox(height: 8),
        const Text(
            'Health Sprout v1.1\n'
            'Powered by Google Gemini & Health Connect\n'
            'Health data is stored locally on your device only.',
            style: TextStyle(color: Colors.grey, fontSize: 13)),
      ]),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clear all health data?'),
        content: const Text(
            'This will delete all locally stored health metrics. '
            'This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed == true) {
      await _db.clearAll();
      await _load();
    }
  }
}
