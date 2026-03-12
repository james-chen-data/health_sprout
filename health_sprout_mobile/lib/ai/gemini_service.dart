import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../db/database.dart';

/// Gemini AI service — sends DB-sourced health summaries to the AI.
///
/// Key design principle: the AI never holds metric values in its context.
/// Before every coaching session, we query the DB for exact numbers and
/// inject them as a structured block. This eliminates hallucination on data.
class GeminiService {
  static const String _prefKeyApiKey = 'gemini_api_key';
  static const String _model         = 'gemini-2.5-flash';
  static const String _baseUrl       =
      'https://generativelanguage.googleapis.com/v1beta/models';

  final HealthDatabase _db = HealthDatabase();

  // ── API key management ─────────────────────────────────────────────────

  Future<String?> getSavedApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefKeyApiKey);
  }

  Future<void> saveApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyApiKey, key);
  }

  Future<bool> testApiKey(String key) async {
    try {
      final url = Uri.parse('$_baseUrl/$_model:generateContent?key=$key');
      final resp = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [{'parts': [{'text': 'Say exactly: CONNECTED'}]}],
        }),
      );
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ── Chat ───────────────────────────────────────────────────────────────

  /// Send a single message to Gemini with full conversation history.
  /// Health data is always read fresh from the DB before each session start.
  Future<String> sendMessage({
    required String apiKey,
    required String systemPrompt,
    required List<ChatMessage> history,
    required String userMessage,
  }) async {
    final url = Uri.parse('$_baseUrl/$_model:generateContent?key=$apiKey');

    // Build contents list from history + new message
    final contents = <Map<String, dynamic>>[];
    for (final msg in history) {
      contents.add({
        'role': msg.isUser ? 'user' : 'model',
        'parts': [{'text': msg.text}],
      });
    }
    contents.add({
      'role': 'user',
      'parts': [{'text': userMessage}],
    });

    final body = jsonEncode({
      'system_instruction': {
        'parts': [{'text': systemPrompt}],
      },
      'contents': contents,
      'generationConfig': {
        'temperature':     0.7,
        'maxOutputTokens': 2048,
      },
    });

    final resp = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: body,
    );

    if (resp.statusCode == 200) {
      final json = jsonDecode(resp.body);
      return json['candidates']?[0]?['content']?['parts']?[0]?['text']
          as String? ?? 'No response received.';
    } else {
      throw GeminiException(resp.statusCode, resp.body);
    }
  }

  // ── System prompts with DB-injected health data ────────────────────────

  /// Build the Body Recomposition Coach system prompt.
  /// Fetches a fresh DB summary so the AI works with exact numbers.
  Future<String> buildBodyCoachPrompt() async {
    final dbSummary = await _db.buildAiSummary(days: 90);
    return '''
You are an expert personal fitness coach and body recomposition specialist.
Your approach is science-based, personalized, encouraging, realistic, and safety-first.
Always recommend consulting a doctor before starting a new exercise program,
especially for anyone with a medical history (post-CABG, heart conditions, etc.).

IMPORTANT — HEALTH DATA ACCURACY:
The health metrics below come directly from a SQLite database synced from the
user's Health Connect device data (Fitbit, smart scale, etc.). These are real
measured values. Use them precisely — do not round, estimate, or infer values
not shown. When the user asks about their data, always cite the exact value
and date from the data below.

$dbSummary

CAPABILITIES — You can answer questions like:
- "What is my body fat / weight / resting HR today?" → cite the latest value
- "How has my sleep been trending?" → use 7d/30d change data + daily log
- "Why did my HRV drop?" → correlate with sleep, steps, resting HR changes
- "Analyze my trends" → do a cross-metric analysis across all available data
- "Give me a workout plan" → use weight, body fat, HR, HRV to personalize it

CROSS-METRIC ANALYSIS GUIDELINES:
When the user asks about trends or insights, analyze correlations between metrics:
- Lower sleep duration/quality often correlates with higher resting HR and lower HRV
- Consistent high step counts + good sleep usually correlate with improving body composition
- Sudden resting HR spikes may indicate overtraining, stress, or poor recovery
- HRV trending up = improving recovery capacity; trending down = fatigue/stress
- Body fat decreasing while weight is stable = positive recomposition (muscle gain + fat loss)
Use the RECENT DAILY LOG section to spot day-to-day patterns and correlations.

COACHING STAGES (follow in order for new users):

STAGE 1 — GOAL SETTING
Ask what body recomposition goal they want to work toward.

STAGE 2 — DEMOGRAPHICS
Collect: age, gender, current activity level, injuries or medical conditions.
(Height and weight may already be in the health data above.)

STAGE 3 — LIFESTYLE PROFILE
Ask about diet type, meals per day, protein supplements, sleep quality.

STAGE 4 — PERSONALIZED PLAN
Generate a 7-day workout + nutrition framework appropriate for their goal,
experience level, and limitations. Reference their actual health metrics
(e.g., "Your resting HR of X bpm and HRV of Y ms suggest good recovery capacity").

After delivering the plan, ask: "Would you like me to adjust anything?"

If the user skips the coaching stages and asks a direct question about their data,
answer it immediately with specific numbers and trend analysis.

STYLE: Warm, encouraging, realistic. Safety first for any cardiac history.
Keep responses concise — no more than 3-4 paragraphs per reply unless detailed
plan is requested.
''';
  }

  /// Build the Sprout Advisor system prompt (no health data needed).
  String buildSproutAdvisorPrompt() => '''
You are a knowledgeable, friendly Sprouts & Microgreens Growing Advisor.
You help users grow the best sprouts and microgreens for their personal health goals.

Work through four stages:
STAGE 1 — UNDERSTAND HEALTH GOALS
STAGE 2 — RECOMMEND TOP 3 VARIETIES
STAGE 3 — SEEDS & EQUIPMENT (vendors, costs)
STAGE 4 — STEP-BY-STEP GROWING INSTRUCTIONS

Be warm and encouraging. If they mention medical context (post-surgery, medications),
ask if they are on blood thinners — some microgreens are high in Vitamin K.
''';
}

class ChatMessage {
  final String text;
  final bool   isUser;
  final DateTime timestamp;

  ChatMessage({
    required this.text,
    required this.isUser,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

class GeminiException implements Exception {
  final int    statusCode;
  final String body;
  GeminiException(this.statusCode, this.body);

  @override
  String toString() => 'GeminiException($statusCode): $body';
}
