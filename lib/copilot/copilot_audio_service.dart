import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:audio_session/audio_session.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../common/voice_helper.dart';

typedef ResultCallback = void Function(String recognizedWords, bool isFinal);
typedef SessionEndedCallback = void Function();

class CopilotAudioService {
  final FlutterTts tts = FlutterTts();
  final SpeechToText stt = SpeechToText();
  AudioSession? _audioSession;

  bool _isListening = false;
  bool _isStarting = false;

  // iOS flutter_tts sometimes never fires its completion handler (especially
  // after longer utterances), which strands the hands-free loop on "assistant's
  // turn". We keep our own reference to the completion callback and a safety
  // timer so the turn ALWAYS hands back, callback or not.
  VoidCallback? _onSpeakingComplete;
  Timer? _speakWatchdog;
  bool _speakHandled = false;

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

    _onSpeakingComplete = onSpeakingComplete;
    tts.setStartHandler(onSpeakingStart);
    // Route the engine's completion through our guard so a duplicate (engine
    // fires AND watchdog fires) only triggers the relisten once.
    tts.setCompletionHandler(() => _fireSpeakComplete());
    tts.setCancelHandler(onSpeakingCancel);

    try {
      await tts.getVoices;
    } catch (_) {}

    // Default voices set by caller after profile load if needed

    await stt.initialize(
      onError: (e) {
        _isListening = false; // recognizer stopped on error — release the latch
        onSttError(e.toString());
      },
      onStatus: (s) {
        // iOS/Android often end a turn with a status ('done'/'notListening')
        // and NO finalResult. Clear _isListening here too, or the guard in
        // startListening() stays latched and the mic goes deaf after that turn.
        if (s == 'done' || s == 'notListening') _isListening = false;
        onSttStatus(s);
      },
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
    String savedName = '';
    String savedLocale = '';
    try {
      final user = supabase.auth.currentUser;
      if (user != null) {
        final p = await supabase
            .from('profiles')
            .select('copilot_voice_name, copilot_voice_locale')
            .eq('user_id', user.id)
            .maybeSingle();
        savedName = (p?['copilot_voice_name'] ?? '').toString();
        savedLocale = (p?['copilot_voice_locale'] ?? '').toString();
      }
    } catch (_) {}

    // Honor the driver's saved voice if it's installed on THIS device;
    // otherwise auto-pick the best installed English voice. No saved choice
    // also lands on best — so everyone gets the best voice they have, instead
    // of a hardcoded default that may not even be downloaded.
    final applied = await VoiceHelper.applySavedOrBest(
      tts,
      savedName: savedName.isEmpty ? null : savedName,
      lang: 'en',
    );

    // Last-ditch fallback if the device somehow lists no English voices.
    if (applied == null) {
      await loadCustomVoice(savedName, savedLocale);
    }
  }

  // Fire the completion callback exactly once per utterance, whether it comes
  // from the real engine handler or our safety watchdog.
  void _fireSpeakComplete() {
    if (_speakHandled) return;
    _speakHandled = true;
    _speakWatchdog?.cancel();
    _speakWatchdog = null;
    _onSpeakingComplete?.call();
  }

  Future<void> speak(String text) async {
    _speakHandled = false;
    _speakWatchdog?.cancel();

    // Estimate how long this utterance should take, then add headroom. At
    // setSpeechRate(0.5) iOS speaks ~13-15 chars/sec; we budget conservatively
    // (~11 chars/sec) plus a 4s floor so short replies still get a real window.
    final estMs = (text.length / 11.0 * 1000).round();
    final budget = Duration(milliseconds: (estMs + 4000).clamp(4000, 60000));

    // If the engine's completion handler never fires (a known iOS flutter_tts
    // problem), this watchdog fires it for us so the mic reopens.
    _speakWatchdog = Timer(budget, () {
      debugPrint('TTS watchdog fired — engine completion never came; handing turn back.');
      _fireSpeakComplete();
    });

    try {
      await tts.speak(text);
    } catch (e) {
      debugPrint('tts.speak threw: $e');
      _fireSpeakComplete(); // don't strand the loop on a speak failure
    }
  }

  Future<void> stopSpeaking() async {
    _speakWatchdog?.cancel();
    _speakWatchdog = null;
    _speakHandled = true; // we're deliberately stopping; don't let watchdog re-fire
    await tts.stop();
  }

  Future<void> stopListening() async {
    await stt.stop();
    _isListening = false;
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
      _isListening = false; // failed to start — don't leave the flag latched
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
