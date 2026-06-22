import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:url_launcher/url_launcher.dart';

import 'copilot_audio_service.dart';
import 'copilot_context_manager.dart';
import '../help/help_content.dart';

class CopilotVoiceController extends ChangeNotifier {
  final SupabaseClient _supabase;
  final CopilotAudioService audio = CopilotAudioService();
  final CopilotContextManager context = CopilotContextManager();

  final TextEditingController textController = TextEditingController();
  final List<Map<String, String>> messages = [];

  bool isThinking = false;
  bool voiceOn = false;
  bool listening = false;
  bool handsFree = false;
  bool speaking = false;
  bool turnHandled = false;
  bool parkedAck = false;

  String get driverName => context.driverName;
  String get copilotName => context.copilotName;
  String get copilotAvatar => context.copilotAvatar;

  String sessionId = const Uuid().v4();

  Future<bool?> Function()? onShowParkedReminder;
  Future<bool?> Function()? onShowResumeDialog;
  VoidCallback? onScrollToBottomRequested;

  CopilotVoiceController({SupabaseClient? supabase})
      : _supabase = supabase ?? Supabase.instance.client;

  Future<void> initialize() async {
    await context.loadNames();
    await audio.setup(
      onSpeakingStart: () { speaking = true; if (handsFree) audio.resetIdle(_autoStopHandsFree); notifyListeners(); },
      onSpeakingComplete: () { speaking = false; if (handsFree && !isThinking) { audio.resetIdle(_autoStopHandsFree); audio.scheduleRelisten(_startListening); } notifyListeners(); },
      onSpeakingCancel: () { speaking = false; notifyListeners(); },
      onSttError: (e) { debugPrint('STT error: $e'); _onSessionEnded(); },
      onSttStatus: (s) { debugPrint('STT status: $s'); if (s == 'done' || s == 'notListening') _onSessionEnded(); },
    );
    await audio.loadVoiceFromProfile(_supabase);
    notifyListeners();
  }

  Future<void> reloadPreferences() async {
    await context.loadNames();
    await audio.loadVoiceFromProfile(_supabase);
    notifyListeners();
  }

  Future<void> send() async {
    if (isThinking) return;
    final text = textController.text.trim();
    if (text.isEmpty) return;

    textController.clear();
    FocusManager.instance.primaryFocus?.unfocus();
    if (handsFree) audio.resetIdle(_autoStopHandsFree);

    messages.add({'role': 'user', 'content': text});
    isThinking = true;
    notifyListeners();
    onScrollToBottomRequested?.call();

    try {
      final outgoingHistory = context.buildOutgoingHistory(messages);

      final response = await _supabase.functions.invoke('copilot', body: {
        'message': text,
        'history': outgoingHistory,
        'driverName': context.driverName,
        'copilotName': context.copilotName,
        'session_id': sessionId,
        'appGuide': helpGuideForEvan(),
      });

      final data = response.data;
      String reply = data is Map ? (data['reply'] ?? 'No response') : data.toString();

      Uri? emailUri;
      if (data is Map && data['actions'] != null) {
        for (final action in (data['actions'] as List)) {
          if (action['type'] == 'email') {
            final email = action['email'] ?? '';
            final subject = Uri.encodeComponent(action['subject'] ?? '');
            final body = Uri.encodeComponent(action['body'] ?? '');
            final uri = Uri.parse('mailto:$email?subject=$subject&body=$body');
            if (await canLaunchUrl(uri)) {
              emailUri = uri;
            } else {
              reply = "I can't send that email — I don't see any email set up on your phone.";
            }
          }
        }
      }

      messages.add({'role': 'assistant', 'content': reply});
      isThinking = false;
      notifyListeners();
      if (handsFree) audio.resetIdle(_autoStopHandsFree);
      onScrollToBottomRequested?.call();

      if (voiceOn) {
        speaking = true;
        await audio.stopListening();
        await Future.delayed(const Duration(milliseconds: 200));
        await audio.speak(reply);
      } else if (handsFree) {
        audio.scheduleRelisten(_startListening);
      }

      if (data is Map && data['actions'] != null) {
        for (final action in (data['actions'] as List)) {
          if (action['type'] == 'sms') {
            final phone = action['phone'] ?? '';
            final body = Uri.encodeComponent(action['body'] ?? '');
            final uri = Uri.parse('sms:$phone?body=$body');
            if (await canLaunchUrl(uri)) await launchUrl(uri);
          }
          if (action['type'] == 'call') {
            final phone = action['phone'] ?? '';
            final uri = Uri.parse('tel:$phone');
            if (await canLaunchUrl(uri)) await launchUrl(uri);
          }
          if (action['type'] == 'email' && emailUri != null) {
            await launchUrl(emailUri);
          }
        }
      }
    } catch (e) {
      speaking = false;
      messages.add({'role': 'assistant', 'content': 'Sorry, something went wrong: $e'});
      isThinking = false;
      notifyListeners();
      onScrollToBottomRequested?.call();
      if (handsFree) audio.scheduleRelisten(_startListening);
    }
  }

  Future<void> toggleHandsFree() async {
    if (handsFree) {
      audio.cancelIdle();
      handsFree = false;
      await audio.stopListening();
      await audio.stopSpeaking();
      listening = false;
      notifyListeners();
      return;
    }

    if (!parkedAck) {
      final ok = await (onShowParkedReminder?.call() ?? Future.value(true));
      if (ok != true) return;
      parkedAck = true;
      notifyListeners();
    }

    handsFree = true;
    voiceOn = true;
    notifyListeners();
    audio.resetIdle(_autoStopHandsFree);
    await _startListening();
  }

  void toggleVoice() {
    voiceOn = !voiceOn;
    if (!voiceOn) audio.stopSpeaking();
    notifyListeners();
  }

  void clearConversation() {
    messages.clear();
    sessionId = const Uuid().v4();
    notifyListeners();
  }

  Future<void> _startListening() async {
    turnHandled = false; // new listen session — let THIS turn's transcript send
    await audio.startListening(
      onResult: (recognized, isFinal) {
        textController.text = recognized;
        if (recognized.trim().isNotEmpty) audio.resetIdle(_autoStopHandsFree);
        if (isFinal) {
          listening = false;
          notifyListeners();
          _handleFinalTranscript(recognized);
        }
      },
      onSessionEnded: _onSessionEnded,
      handsFree: handsFree,
      isThinking: isThinking,
      resetIdle: () => audio.resetIdle(_autoStopHandsFree),
      scheduleRelisten: () => audio.scheduleRelisten(_startListening),
    );
    listening = audio.isListening;
    notifyListeners();
  }

  void _onSessionEnded() {
    if (speaking) return;
    if (listening) { listening = false; notifyListeners(); }
    if (!handsFree) return;
    if (isThinking) return;
    final pending = textController.text.trim();
    if (pending.isNotEmpty) {
      _handleFinalTranscript(pending);
    } else {
      audio.scheduleRelisten(_startListening);
    }
  }

  void _handleFinalTranscript(String raw) {
    if (turnHandled) return;
    final words = raw.trim();
    if (words.isEmpty) {
      if (handsFree) audio.scheduleRelisten(_startListening);
      return;
    }
    turnHandled = true;
    audio.resetIdle(_autoStopHandsFree);
    send();
  }

  Future<void> _autoStopHandsFree() async {
    if (!handsFree) return;
    handsFree = false;
    await audio.stopListening();
    await audio.stopSpeaking();
    listening = false;
    notifyListeners();
    final resume = await (onShowResumeDialog?.call() ?? Future.value(false));
    if (resume == true) await toggleHandsFree();
  }

  @override
  void dispose() {
    handsFree = false;
    audio.cancelIdle();
    audio.stopSpeaking();
    audio.stopListening();
    textController.dispose();
    super.dispose();
  }
}
