import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:audio_session/audio_session.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef ResultCallback = void Function(String recognizedWords, bool isFinal);
typedef SessionEndedCallback = void Function();

class CopilotAudioService {
  final FlutterTts tts = FlutterTts();
  final SpeechToText stt = SpeechToText();
  AudioSession? _audioSession;

  bool _isListening = false;
  bool _isStarting = false;

  Future<void> setup({
    required VoidCallback onSpeakingStart,
    required VoidCallback onSpeakingComplete,
    required VoidCallback onSpeakingCancel,
    required void Function(String error) onSttError,
    required void Function(String status) onSttStatus,
  }) async {
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

    await tts.setLanguage("en-US");
    await tts.setSpeechRate(0.5);
    await tts.setPitch(1.0);

    tts.setStartHandler(onSpeakingStart);
    tts.setCompletionHandler(onSpeakingComplete);
    tts.setCancelHandler(onSpeakingCancel);

    try {
      await tts.getVoices;
    } catch (_) {}

    // Default voices set by caller after profile load if needed

    stt.initialize(
      onError: (e) => onSttError(e.toString()),
      onStatus: (s) => onSttStatus(s),
    );
  }

  Future<void> loadCustomVoice(String name, String locale) async {
    if (name.isNotEmpty && locale.isNotEmpty) {
      try {
        await tts.setVoice({"name": name, "locale": locale});
        return;
      } catch (_) {}
    }
    try {
      await tts.setVoice({"name": "Daniel", "locale": "en-GB"});
    } catch (_) {
      try {
        await tts.setVoice({"name": "Fred", "locale": "en-US"});
      } catch (_) {}
    }
  }

  Future<void> loadVoiceFromProfile(SupabaseClient supabase) async {
    try {
      final user = supabase.auth.currentUser;
      if (user != null) {
        final p = await supabase
            .from('profiles')
            .select('copilot_voice_name, copilot_voice_locale')
            .eq('user_id', user.id)
            .single();
        final name = (p['copilot_voice_name'] ?? '').toString();
        final locale = (p['copilot_voice_locale'] ?? '').toString();
        if (name.isNotEmpty && locale.isNotEmpty) {
          await tts.setVoice({"name": name, "locale": locale});
          return;
        }
      }
    } catch (_) {}
    await loadCustomVoice('', '');
  }

  Future<void> speak(String text) async {
    await tts.speak(text);
  }

  Future<void> stopSpeaking() async {
    await tts.stop();
  }

  Future<void> stopListening() async {
    await stt.stop();
  }

  Future<void> startListening({
    required ResultCallback onResult,
    required SessionEndedCallback onSessionEnded,
    required bool handsFree,
    required bool isThinking,
    required VoidCallback resetIdle,
    required VoidCallback scheduleRelisten,
  }) async {
    if (_isListening || isThinking || _isStarting) return;
    _isStarting = true;
    try {
      await stopSpeaking();
      try {
        await stt.cancel();
      } catch (_) {}
      try {
        await _audioSession?.setActive(true);
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 350));

      _isListening = true;
      await stt.listen(
        onResult: (result) {
          onResult(result.recognizedWords, result.finalResult);
          if (result.recognizedWords.trim().isNotEmpty) resetIdle();
          if (result.finalResult) {
            _isListening = false;
            onSessionEnded();
          }
        },
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 6),
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: false,
          listenMode: ListenMode.dictation,
        ),
      );
    } catch (e) {
      debugPrint('STT listen threw: $e');
    } finally {
      _isStarting = false;
    }
  }

  bool get isListening => _isListening;

  void markListeningStopped() {
    _isListening = false;
  }

  Future<void> cancelStt() async {
    try {
      await stt.cancel();
    } catch (_) {}
  }

  // Hands-free orchestration helpers (idle, schedule, auto stop)
  Timer? _idleTimer;
  static const Duration idleTimeout = Duration(seconds: 90);

  void resetIdle(VoidCallback autoStop) {
    _idleTimer?.cancel();
    _idleTimer = Timer(idleTimeout, autoStop);
  }

  void cancelIdle() {
    _idleTimer?.cancel();
  }

  void scheduleRelisten(VoidCallback startListening) {
    Future.delayed(const Duration(milliseconds: 600), () {
      startListening();
    });
  }
}
