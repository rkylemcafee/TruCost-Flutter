import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:audio_session/audio_session.dart';
import 'copilot_history_screen.dart';
import 'voice_settings_screen.dart';

class CopilotScreen extends StatefulWidget {
  const CopilotScreen({super.key});
  @override
  State<CopilotScreen> createState() => _CopilotScreenState();
}

class _CopilotScreenState extends State<CopilotScreen> {
  final _supabase = Supabase.instance.client;
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final FlutterTts _tts = FlutterTts();
  final SpeechToText _stt = SpeechToText();
  AudioSession? _audioSession;

  bool _isThinking = false;
  bool _voiceOn = false;
  bool _sttReady = false;
  bool _listening = false;
  bool _handsFree = false; // conversation mode: keep the mic cycling
  bool _starting = false;  // guard against double-starting the recognizer
  bool _speaking = false;  // TTS owns the audio — suppress relisten while true
  bool _turnHandled = false; // this listen session's transcript already sent?
  bool _parkedAck = false; // shown the "be parked" reminder this session?
  bool _resumeDialogOpen = false; // sleep popup currently showing?

  Timer? _idleTimer; // auto-shuts hands-free off after 90s of silence

  final List<Map<String, String>> _messages = [];
  String _driverName = 'driver';
  String _copilotName = 'Co-Pilot';
  String _sessionId = const Uuid().v4();

  // Hands-free turns itself off after this much quiet (nobody talking).
  static const Duration _idleTimeout = Duration(seconds: 90);

  @override
  void initState() {
    super.initState();
    _loadNames();
    _setupAudio();
  }

  Future<void> _setupAudio() async {
    _audioSession = await AudioSession.instance;
    await _audioSession!.configure(AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
      avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.defaultToSpeaker |
          AVAudioSessionCategoryOptions.allowBluetooth,
      avAudioSessionMode: AVAudioSessionMode.defaultMode,
      avAudioSessionRouteSharingPolicy: AVAudioSessionRouteSharingPolicy.defaultPolicy,
      avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
      androidAudioAttributes: const AndroidAudioAttributes(
        contentType: AndroidAudioContentType.speech,
        usage: AndroidAudioUsage.assistant,
      ),
      androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
      androidWillPauseWhenDucked: true,
    ));
    await _audioSession!.setActive(true);
    await _setupTts();
    await _setupStt();
  }

  Future<void> _setupTts() async {
    await _tts.setLanguage("en-US");
    await _tts.setSpeechRate(0.5);
    await _tts.setPitch(1.0);

    _tts.setStartHandler(() {
      _speaking = true;
      if (_handsFree) _resetIdle();
    });
    _tts.setCompletionHandler(() {
      _speaking = false;
      // Bob finished his turn cleanly — NOW it's safe to open the mic.
      if (_handsFree && mounted && !_isThinking) {
        _resetIdle();
        _scheduleRelisten();
      }
    });
    _tts.setCancelHandler(() {
      // Cancels are deliberate (we stopped TTS to listen, or hands-free
      // was toggled off). Just clear the flag — do NOT auto-relisten here,
      // or stopping TTS to start the mic would immediately stop the mic.
      _speaking = false;
    });

    try {
      final user = _supabase.auth.currentUser;
      if (user != null) {
        final p = await _supabase
            .from('profiles')
            .select('copilot_voice_name, copilot_voice_locale')
            .eq('user_id', user.id)
            .single();
        final name = (p['copilot_voice_name'] ?? '').toString();
        final locale = (p['copilot_voice_locale'] ?? '').toString();
        if (name.isNotEmpty && locale.isNotEmpty) {
          await _tts.setVoice({"name": name, "locale": locale});
          return;
        }
      }
    } catch (_) {/* fall through to defaults */}

    try {
      await _tts.setVoice({"name": "Daniel", "locale": "en-GB"});
    } catch (_) {
      try {
        await _tts.setVoice({"name": "Fred", "locale": "en-US"});
      } catch (_) {}
    }
  }

 Future<void> _setupStt() async {
    _sttReady = await _stt.initialize(
      onError: (e) {
        debugPrint('STT error: $e');
        _onSessionEnded();
      },
      onStatus: (s) {
        debugPrint('STT status: $s');
        if (s == 'done' || s == 'notListening') {
          _onSessionEnded();
        }
      },
    );
    debugPrint('STT initialize → available: $_sttReady');
    if (mounted) setState(() {});
  }

  // Android frequently ends a listen session WITHOUT firing a final result —
  // it just goes "done" or throws error_no_match. So whenever a session ends,
  // if we captured any words, treat the last partial as final and send it.
  // Only fires while hands-free is still on, so toggling off won't send a stray message.
  void _onSessionEnded() {
    if (!mounted) return;
    // If Bob is speaking, this 'done'/'notListening' came from us stopping the
    // recognizer so TTS could play. Ignore it — the TTS completion handler will
    // reopen the mic when Bob is actually finished.
    if (_speaking) return;
    if (_listening) setState(() => _listening = false);
    if (!_handsFree) return;
    // A turn is already being processed/sent — don't relisten or double-send.
    if (_isThinking) return;
    final pending = _textCtrl.text.trim();
    if (pending.isNotEmpty) {
      _handleFinalTranscript(pending);
    } else {
      _scheduleRelisten();
    }
  }

  Future<void> _openVoiceSettings() async {
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => const VoiceSettingsScreen(),
    ));
    if (changed == true) {
      await _setupTts();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Voice updated.')),
        );
      }
    }
  }

  // ── Hands-free conversation mode ───────────────────────────
  Future<void> _toggleHandsFree() async {
    if (_handsFree) {
      _idleTimer?.cancel();
      setState(() => _handsFree = false);
      await _stt.stop();
      await _tts.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }

    if (!_parkedAck) {
      final ok = await _showParkedReminder();
      if (ok != true) return;
      _parkedAck = true;
    }

    setState(() {
      _handsFree = true;
      _voiceOn = true;
    });
    _resetIdle();
    await _startListening();
  }

  Future<bool?> _showParkedReminder() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Before You Go Hands-Free'),
        content: const Text(
          'Only use hands-free conversation while stopped or parked.\n\n'
          'Keep your eyes on the road and your hands on the wheel when driving.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("I'm Parked"),
          ),
        ],
      ),
    );
  }

  void _resetIdle() {
    _idleTimer?.cancel();
    if (!_handsFree) return;
    _idleTimer = Timer(_idleTimeout, _autoStopHandsFree);
  }

  Future<void> _autoStopHandsFree() async {
    if (!_handsFree) return;
    setState(() => _handsFree = false);
    await _stt.stop();
    await _tts.stop();
    if (mounted) setState(() => _listening = false);
    if (mounted) _showResumeDialog();
  }

  // Big center-screen popup so the sleep state is impossible to miss.
  Future<void> _showResumeDialog() async {
    if (_resumeDialogOpen) return;
    _resumeDialogOpen = true;
    final resume = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text('$_copilotName went to sleep'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Hands-free turned off after 90 seconds of quiet.\n\n'
              'Tap the button to start talking again.',
              style: TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 64,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.pop(ctx, true),
                icon: const Icon(Icons.mic, size: 28),
                label: const Text('Keep Talking',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueGrey[700],
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("I'm Done"),
          ),
        ],
      ),
    );
    _resumeDialogOpen = false;
    if (resume == true) {
      await _toggleHandsFree(); // parked already acked → just re-arms + listens
    }
  }

  void _scheduleRelisten() {
    if (!_handsFree) return;
    Future.delayed(const Duration(milliseconds: 600), () {
      if (_handsFree && mounted && !_isThinking && !_listening && !_starting) {
        _startListening();
      }
    });
  }

  Future<void> _startListening() async {
    if (!_sttReady) {
      await _setupStt();
      if (!_sttReady) return;
    }
    if (_listening || _isThinking || _starting) return;
    _starting = true;
    try {
      await _tts.stop();
      try {
        await _audioSession?.setActive(true);
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) {
        _starting = false;
        return;
      }
      setState(() => _listening = true);
      _turnHandled = false; // fresh session — a new transcript may be consumed
      await _stt.listen(
        onResult: (result) {
          debugPrint('STT result: "${result.recognizedWords}" '
              'final=${result.finalResult}');
          setState(() => _textCtrl.text = result.recognizedWords);
          if (result.recognizedWords.trim().isNotEmpty) _resetIdle();
          if (result.finalResult) {
            setState(() => _listening = false);
            _handleFinalTranscript(result.recognizedWords);
          }
        },
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 4),
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: false,
          listenMode: ListenMode.dictation,
        ),
      );
    } catch (e) {
      debugPrint('STT listen threw: $e');
    } finally {
      _starting = false;
    }
  }

  void _handleFinalTranscript(String raw) {
    // STT delivers the final transcript through two paths on some devices: the
    // 'done' status (→ _onSessionEnded) and the final onResult. On this
    // hardware the 'done' path can fire, run the whole LLM round-trip, and
    // start speaking BEFORE the late final=true result arrives — so _isThinking
    // is already false again and can't dedupe. Instead we tie the dedupe to the
    // listen session: whichever trigger lands first consumes it; the duplicate
    // is ignored until _startListening opens a fresh session.
    if (_turnHandled) return;
    final words = raw.trim();
    if (words.isEmpty) {
      if (_handsFree) _scheduleRelisten();
      return;
    }
    _turnHandled = true;
    _resetIdle();
    _send();
  }

  Future<void> _loadNames() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;
      final p = await _supabase.from('profiles').select('preferred_name, copilot_name').eq('user_id', user.id).single();
      setState(() {
        _driverName = p['preferred_name'] ?? 'driver';
        _copilotName = p['copilot_name'] ?? 'Co-Pilot';
      });
    } catch (_) {}
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    if (_isThinking) return; // a turn is already in flight — no double-send
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;

    _textCtrl.clear();
    FocusScope.of(context).unfocus();
    if (_handsFree) _resetIdle();

    setState(() {
      _messages.add({'role': 'user', 'content': text});
      _isThinking = true;
    });
    _scrollToBottom();

    try {
      final response = await _supabase.functions.invoke(
        'copilot',
        body: {
          'message': text,
          'history': _messages.length > 1
              ? _messages.sublist(0, _messages.length - 1)
              : [],
          'driverName': _driverName,
          'copilotName': _copilotName,
          'session_id': _sessionId,
        },
      );

      final data = response.data;
      final reply = data is Map ? (data['reply'] ?? 'No response') : data.toString();

      setState(() {
        _messages.add({'role': 'assistant', 'content': reply});
        _isThinking = false;
      });
      if (_handsFree) _resetIdle();
      _scrollToBottom();

      if (_voiceOn) {
        // Claim the audio for Bob BEFORE stopping the mic. Stopping STT fires
        // onStatus(done/notListening), which routes to _onSessionEnded — the
        // _speaking guard there makes it a no-op so the mic won't reopen and
        // interrupt the reply. The TTS completion handler reopens the mic.
        _speaking = true;
        await _stt.stop();
        await Future.delayed(const Duration(milliseconds: 200));
        await _tts.speak(reply);
      } else if (_handsFree) {
        _scheduleRelisten();
      }

      if (data is Map && data['actions'] != null) {
        final actions = data['actions'] as List;
        for (final action in actions) {
          if (action['type'] == 'sms') {
            final phone = action['phone'] ?? '';
            final body = Uri.encodeComponent(action['body'] ?? '');
            final uri = Uri.parse('sms:$phone?body=$body');
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri);
            }
          }
          if (action['type'] == 'call') {
            final phone = action['phone'] ?? '';
            final uri = Uri.parse('tel:$phone');
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri);
            }
          }
        }
      }
    } catch (e) {
      _speaking = false;
      setState(() {
        _messages.add({'role': 'assistant', 'content': 'Sorry, something went wrong: $e'});
        _isThinking = false;
      });
      _scrollToBottom();
      if (_handsFree) _scheduleRelisten();
    }
  }

  @override
  void dispose() {
    _handsFree = false;
    _idleTimer?.cancel();
    _tts.stop();
    _stt.stop();
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_copilotName),
        actions: [
          IconButton(
            icon: Icon(_voiceOn ? Icons.volume_up : Icons.volume_off),
            onPressed: () => setState(() {
              _voiceOn = !_voiceOn;
              if (!_voiceOn) _tts.stop();
            }),
            tooltip: 'Voice on/off',
          ),
          IconButton(
            icon: const Icon(Icons.record_voice_over),
            onPressed: _openVoiceSettings,
            tooltip: 'Choose voice',
          ),
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const CopilotHistoryScreen(),
            )),
            tooltip: 'History',
          ),
          if (_messages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.add_comment_outlined),
              onPressed: () => setState(() {
                _messages.clear();
                _sessionId = const Uuid().v4();
              }),
              tooltip: 'New conversation',
            ),
        ],
      ),
      body: Column(
        children: [
          if (_handsFree) _parkedReminderBar(),
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.smart_toy, size: 64, color: Colors.blueGrey[200]),
                        const SizedBox(height: 16),
                        Text('Ask $_copilotName about any load',
                            style: TextStyle(fontSize: 16, color: Colors.grey[500])),
                        const SizedBox(height: 8),
                        Text('"Got offered 3 grand for Miami to Atlanta.\nIs it worth it?"',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 14, color: Colors.grey[400], fontStyle: FontStyle.italic)),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length + (_isThinking ? 1 : 0),
                    itemBuilder: (ctx, i) {
                      if (i == _messages.length && _isThinking) {
                        return _buildThinking();
                      }
                      return _buildMessage(_messages[i]);
                    },
                  ),
          ),
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey[200]!)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _textCtrl,
            textCapitalization: TextCapitalization.sentences,
            minLines: 1,
            maxLines: 4,
            style: const TextStyle(fontSize: 17),
            decoration: InputDecoration(
              hintText: 'Ask $_copilotName about a load...',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
            onSubmitted: (_) => _send(),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(flex: 2, child: _talkButton()),
              const SizedBox(width: 12),
              Expanded(flex: 1, child: _sendButton()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _talkButton() {
    Color color;
    String label;
    IconData icon;
    if (_handsFree) {
      if (_isThinking) {
        color = Colors.amber[800]!;
        label = 'Thinking…';
        icon = Icons.hourglass_top;
      } else if (_listening) {
        color = Colors.red;
        label = 'Listening…';
        icon = Icons.mic;
      } else {
        color = Colors.green[600]!;
        label = "$_copilotName's turn…";
        icon = Icons.volume_up;
      }
    } else {
      color = Colors.blueGrey[600]!;
      label = 'Tap to Talk';
      icon = Icons.mic_none;
    }

    return GestureDetector(
      onTap: _toggleHandsFree,
      child: Container(
        height: 72,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 30),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sendButton() {
    return GestureDetector(
      onTap: _isThinking ? null : _send,
      child: Container(
        height: 72,
        decoration: BoxDecoration(
          color: _isThinking ? Colors.grey[400] : Colors.blueGrey[800],
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Center(
          child: Icon(Icons.send, color: Colors.white, size: 30),
        ),
      ),
    );
  }

  Widget _parkedReminderBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.green[50],
      child: Row(
        children: [
          Icon(Icons.local_parking, color: Colors.green[700], size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Hands-free on — use only while parked. Auto-off after 90 seconds of quiet.',
              style: TextStyle(fontSize: 12.5, color: Colors.green[900]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessage(Map<String, String> msg) {
    final isUser = msg['role'] == 'user';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.blueGrey[100],
              child: const Icon(Icons.smart_toy, size: 18, color: Colors.blueGrey),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser ? Colors.blueGrey[700] : Colors.grey[100],
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                msg['content'] ?? '',
                style: TextStyle(
                  fontSize: 15,
                  color: isUser ? Colors.white : Colors.black87,
                ),
              ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.blueGrey[700],
              child: const Icon(Icons.person, size: 18, color: Colors.white),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildThinking() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: Colors.blueGrey[100],
            child: const Icon(Icons.smart_toy, size: 18, color: Colors.blueGrey),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blueGrey[400])),
                const SizedBox(width: 8),
                Text('Thinking...', style: TextStyle(color: Colors.grey[500], fontStyle: FontStyle.italic)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
