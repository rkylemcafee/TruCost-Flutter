import 'package:flutter/material.dart';
import '../help/help_content.dart';

import 'copilot_avatar.dart';
import 'copilot_history_screen.dart';
import 'copilot_voice_controller.dart';
import 'voice_settings_screen.dart';

class CopilotScreen extends StatefulWidget {
  const CopilotScreen({super.key});
  @override
  State<CopilotScreen> createState() => _CopilotScreenState();
}

class _CopilotScreenState extends State<CopilotScreen> {
  late final CopilotVoiceController _c;
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _c = CopilotVoiceController();
    _c.addListener(_onChanged);
    _c.onShowParkedReminder = _showParkedReminder;
    _c.onShowResumeDialog = _showResumeDialog;
    _c.onScrollToBottomRequested = _scrollToBottom;
    _c.initialize();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<bool?> _showParkedReminder() => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Before You Go Hands-Free'),
          content: const Text(
            'Only use hands-free conversation while stopped or parked.\n\n'
            'Keep your eyes on the road and your hands on the wheel when driving.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("I'm Parked")),
          ],
        ),
      );

  Future<bool?> _showResumeDialog() => showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Text('${_c.copilotName} went to sleep'),
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
                  label: const Text('Keep Talking', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueGrey[700],
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
            ],
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("I'm Done"))],
        ),
      );

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollCtrl.hasClients && mounted) {
        _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _openVoiceSettings() async {
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const VoiceSettingsScreen()));
    if (changed == true) {
      await _c.reloadPreferences();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Co-Pilot settings updated.')));
      }
    }
  }

  void _newConversation() => _c.clearConversation();

  @override
  void dispose() {
    _c.removeListener(_onChanged);
    _c.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_c.copilotName),
        actions: [
          const HelpButton(HelpScreens.copilot),
          IconButton(icon: Icon(_c.voiceOn ? Icons.volume_up : Icons.volume_off), onPressed: _c.toggleVoice, tooltip: 'Voice on/off'),
          IconButton(icon: const Icon(Icons.record_voice_over), onPressed: _openVoiceSettings, tooltip: 'Choose voice'),
          IconButton(icon: const Icon(Icons.history), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CopilotHistoryScreen())), tooltip: 'History'),
          if (_c.messages.isNotEmpty)
            IconButton(icon: const Icon(Icons.add_comment_outlined), onPressed: _newConversation, tooltip: 'New conversation'),
        ],
      ),
      body: Column(
        children: [
          if (_c.handsFree) _parkedReminderBar(),
          Expanded(
            child: _c.messages.isEmpty
                ? _emptyState()
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.all(16),
                    itemCount: _c.messages.length + (_c.isThinking ? 1 : 0),
                    itemBuilder: (ctx, i) => i == _c.messages.length && _c.isThinking ? _buildThinking() : _buildMessage(_c.messages[i]),
                  ),
          ),
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _emptyState() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CopilotAvatar(name: _c.copilotName, avatarKey: _c.copilotAvatar, size: 64),
            const SizedBox(height: 16),
            Text('Ask ${_c.copilotName} about any load', style: TextStyle(fontSize: 16, color: Colors.grey[500])),
            const SizedBox(height: 8),
            Text('"Got offered 3 grand for Miami to Atlanta.\nIs it worth it?"', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: Colors.grey[400], fontStyle: FontStyle.italic)),
          ],
        ),
      );

  Widget _parkedReminderBar() => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: Colors.green[50],
        child: Row(children: [
          Icon(Icons.local_parking, color: Colors.green[700], size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text('Hands-free on — use only while parked. Auto-off after 90 seconds of quiet.', style: TextStyle(fontSize: 12.5, color: Colors.green[900]))),
        ]),
      );

  Widget _buildMessage(Map<String, String> msg) {
    final isUser = msg['role'] == 'user';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[CopilotAvatar(name: _c.copilotName, avatarKey: _c.copilotAvatar, size: 32), const SizedBox(width: 8)],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: isUser ? Colors.blueGrey[700] : Colors.grey[100], borderRadius: BorderRadius.circular(16)),
              child: Text(msg['content'] ?? '', style: TextStyle(fontSize: 15, color: isUser ? Colors.white : Colors.black87)),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 8),
            CircleAvatar(radius: 16, backgroundColor: Colors.blueGrey[700], child: const Icon(Icons.person, size: 18, color: Colors.white)),
          ],
        ],
      ),
    );
  }

  Widget _buildThinking() => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          CopilotAvatar(name: _c.copilotName, avatarKey: _c.copilotAvatar, size: 32),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(16)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blueGrey[400])),
              const SizedBox(width: 8),
              Text('Thinking...', style: TextStyle(color: Colors.grey[500], fontStyle: FontStyle.italic)),
            ]),
          ),
        ]),
      );

  Widget _buildInputArea() => Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
        decoration: BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Colors.grey[200]!))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _c.textController,
            textCapitalization: TextCapitalization.sentences,
            minLines: 1,
            maxLines: 4,
            style: const TextStyle(fontSize: 17),
            decoration: InputDecoration(
              hintText: 'Ask ${_c.copilotName} about a load...',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
            onSubmitted: (_) => _c.send(),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(flex: 2, child: _talkButton()),
            const SizedBox(width: 12),
            Expanded(flex: 1, child: _sendButton()),
          ]),
        ]),
      );

  Widget _talkButton() {
    Color color;
    String label;
    IconData icon;
    if (_c.handsFree) {
      if (_c.isThinking) {
        color = Colors.amber[800]!;
        label = 'Thinking…';
        icon = Icons.hourglass_top;
      } else if (_c.listening) {
        color = Colors.red;
        label = 'Listening…';
        icon = Icons.mic;
      } else {
        color = Colors.green[600]!;
        label = "${_c.copilotName}'s turn…";
        icon = Icons.volume_up;
      }
    } else {
      color = Colors.blueGrey[600]!;
      label = 'Tap to Talk';
      icon = Icons.mic_none;
    }
    return GestureDetector(
      onTap: _c.toggleHandsFree,
      child: Container(
        height: 72,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(18)),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: Colors.white, size: 30),
          const SizedBox(width: 10),
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700))),
        ]),
      ),
    );
  }

  Widget _sendButton() => GestureDetector(
        onTap: _c.isThinking ? null : _c.send,
        child: Container(
          height: 72,
          decoration: BoxDecoration(color: _c.isThinking ? Colors.grey[400] : Colors.blueGrey[800], borderRadius: BorderRadius.circular(18)),
          child: const Center(child: Icon(Icons.send, color: Colors.white, size: 30)),
        ),
      );
}
