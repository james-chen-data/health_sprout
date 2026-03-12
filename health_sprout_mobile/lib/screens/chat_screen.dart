import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../ai/gemini_service.dart';

enum ChatMode { bodyCoach, sproutAdvisor }

class ChatScreen extends StatefulWidget {
  final ChatMode mode;
  const ChatScreen({super.key, required this.mode});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final GeminiService        _gemini    = GeminiService();
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController      _scrollCtrl = ScrollController();
  final List<ChatMessage>     _history   = [];

  String? _apiKey;
  String  _systemPrompt = '';
  bool    _loading      = false;
  bool    _initializing = true;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    // Load API key
    _apiKey = await _gemini.getSavedApiKey();

    // Build system prompt with fresh DB data injected
    if (widget.mode == ChatMode.bodyCoach) {
      _systemPrompt = await _gemini.buildBodyCoachPrompt();
    } else {
      _systemPrompt = _gemini.buildSproutAdvisorPrompt();
    }

    setState(() { _initializing = false; });

    if (_apiKey == null || _apiKey!.isEmpty) {
      _showApiKeyDialog();
      return;
    }

    // Send opening message
    await _sendOpeningMessage();
  }

  Future<void> _sendOpeningMessage() async {
    final opening = widget.mode == ChatMode.bodyCoach
        ? 'Greet the user warmly. If health data is present in your context, '
          'briefly acknowledge it. Then ask what body recomposition goal they '
          'want to work toward, giving a few examples.'
        : 'Introduce yourself warmly as a Sprouts & Microgreens Growing Advisor. '
          'Ask what health outcomes they hope to support, giving a few examples.';

    await _sendMessage(opening, showInUi: false);
  }

  Future<void> _sendMessage(String text, {bool showInUi = true}) async {
    if (_apiKey == null || text.trim().isEmpty) return;

    if (showInUi) {
      setState(() {
        _history.add(ChatMessage(text: text, isUser: true));
        _loading = true;
      });
      _scrollToBottom();
    } else {
      setState(() { _loading = true; });
    }

    try {
      final reply = await _gemini.sendMessage(
        apiKey:       _apiKey!,
        systemPrompt: _systemPrompt,
        history:      List.from(_history),
        userMessage:  text,
      );

      setState(() {
        _history.add(ChatMessage(text: reply, isUser: false));
        _loading = false;
      });
      _scrollToBottom();
    } catch (e) {
      setState(() {
        _history.add(ChatMessage(
            text: '⚠️ Error: ${e.toString().substring(0, 120)}',
            isUser: false));
        _loading = false;
      });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve:    Curves.easeOut,
        );
      }
    });
  }

  void _showApiKeyDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Gemini API Key Required'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
              'Get a free key at aistudio.google.com/apikey\n'
              'then paste it below:'),
          const SizedBox(height: 12),
          TextField(
            controller:  ctrl,
            decoration:  const InputDecoration(
                hintText: 'AIza...', border: OutlineInputBorder()),
            obscureText: true,
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () async {
              final key = ctrl.text.trim();
              if (key.isEmpty) return;
              final ok = await _gemini.testApiKey(key);
              if (ok) {
                await _gemini.saveApiKey(key);
                setState(() { _apiKey = key; });
                if (context.mounted) Navigator.pop(context);
                await _sendOpeningMessage();
              } else {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Invalid key — check and try again')),
                  );
                }
              }
            },
            child: const Text('Save & Connect'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.mode == ChatMode.bodyCoach
        ? '💪 Body Recomposition Coach'
        : '🌱 Sprout Advisor';
    final color = widget.mode == ChatMode.bodyCoach
        ? const Color(0xFF1565C0)
        : const Color(0xFF2E7D32);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: color,
        foregroundColor: Colors.white,
        title: Text(title),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Start new conversation',
            onPressed: () => setState(() {
              _history.clear();
              _sendOpeningMessage();
            }),
          ),
        ],
      ),
      body: _initializing
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [

              // ── Message list ────────────────────────────────────────────
              Expanded(
                child: ListView.builder(
                  controller:  _scrollCtrl,
                  padding:     const EdgeInsets.all(12),
                  itemCount:   _history.length + (_loading ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (i == _history.length) {
                      return const _TypingIndicator();
                    }
                    return _MessageBubble(
                        message: _history[i], accentColor: color);
                  },
                ),
              ),

              // ── Input bar ───────────────────────────────────────────────
              _InputBar(
                controller: _inputCtrl,
                loading:    _loading,
                accentColor: color,
                onSend: (text) {
                  _inputCtrl.clear();
                  _sendMessage(text);
                },
              ),
            ]),
    );
  }
}

// ── Message bubble ───────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final Color       accentColor;
  const _MessageBubble({required this.message, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin:  const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.82),
        decoration: BoxDecoration(
          color: isUser ? accentColor : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(
              color: Colors.black12, blurRadius: 3, offset: const Offset(0, 1))],
        ),
        child: Text(
          message.text,
          style: TextStyle(
            color:  isUser ? Colors.white : Colors.black87,
            fontSize: 15,
            height: 1.4,
          ),
        ),
      ),
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  @override
  Widget build(BuildContext context) {
    return const Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: SizedBox(
          width: 40, height: 20,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _Dot(delay: 0),
              _Dot(delay: 150),
              _Dot(delay: 300),
            ],
          ),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final int delay;
  const _Dot({required this.delay});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8, height: 8,
      decoration: BoxDecoration(
          color: Colors.grey[400], shape: BoxShape.circle),
    );
  }
}

// ── Input bar ────────────────────────────────────────────────────────────────

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool   loading;
  final Color  accentColor;
  final void Function(String) onSend;

  const _InputBar({
    required this.controller,
    required this.loading,
    required this.accentColor,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:    const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(
            color: Colors.black12, blurRadius: 4, offset: const Offset(0, -1))],
      ),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: controller,
            enabled:    !loading,
            maxLines:   null,
            textInputAction: TextInputAction.send,
            onSubmitted: loading ? null : onSend,
            decoration: InputDecoration(
              hintText:    'Type a message…',
              filled:      true,
              fillColor:   Colors.grey[100],
              border:      OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide:   BorderSide.none),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),
        ),
        const SizedBox(width: 8),
        CircleAvatar(
          backgroundColor: loading ? Colors.grey : accentColor,
          child: IconButton(
            icon:     const Icon(Icons.send, color: Colors.white, size: 20),
            onPressed: loading
                ? null
                : () {
                    final t = controller.text.trim();
                    if (t.isNotEmpty) onSend(t);
                  },
          ),
        ),
      ]),
    );
  }
}
