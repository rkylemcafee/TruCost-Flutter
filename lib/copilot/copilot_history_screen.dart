import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:share_plus/share_plus.dart';

class CopilotHistoryScreen extends StatefulWidget {
  const CopilotHistoryScreen({super.key});
  @override
  State<CopilotHistoryScreen> createState() => _CopilotHistoryScreenState();
}

class _CopilotHistoryScreenState extends State<CopilotHistoryScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _sessions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    setState(() => _loading = true);
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final data = await _supabase
          .from('copilot_messages')
          .select()
          .eq('user_id', user.id)
          .order('created_at', ascending: true);

      final Map<String, List<Map<String, dynamic>>> bySession = {};
      for (final msg in data as List) {
        final sid = msg['session_id'] as String;
        bySession.putIfAbsent(sid, () => []).add(Map<String, dynamic>.from(msg));
      }

      final sessions = bySession.entries.map((e) {
        final messages = e.value;
        final firstUser = messages.firstWhere(
          (m) => m['role'] == 'user',
          orElse: () => messages.first,
        );
        return {
          'session_id': e.key,
          'first_message': firstUser['content'] ?? '(empty)',
          'last_time': messages.last['created_at'],
          'count': messages.length,
          'messages': messages,
        };
      }).toList();

      sessions.sort((a, b) => (b['last_time'] as String).compareTo(a['last_time'] as String));

      setState(() {
        _sessions = sessions;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  String _fmtDate(String iso) {
    final dt = DateTime.parse(iso).toLocal();
    final mo = dt.month.toString().padLeft(2, '0');
    final dy = dt.day.toString().padLeft(2, '0');
    final hr = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final mn = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$mo/$dy $hr:$mn $ampm';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Conversation History')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _sessions.isEmpty
              ? const Center(child: Text('No past conversations yet'))
              : RefreshIndicator(
                  onRefresh: _loadSessions,
                  child: ListView.separated(
                    itemCount: _sessions.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final s = _sessions[i];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.blueGrey[100],
                          child: const Icon(Icons.smart_toy, color: Colors.blueGrey),
                        ),
                        title: Text(
                          s['first_message'] as String,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text('${_fmtDate(s['last_time'] as String)} · ${s['count']} messages'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => _TranscriptScreen(session: s),
                        )),
                      );
                    },
                  ),
                ),
    );
  }
}

class _TranscriptScreen extends StatelessWidget {
  final Map<String, dynamic> session;
  const _TranscriptScreen({required this.session});

  String _buildShareText() {
    final messages = session['messages'] as List;
    final firstDate = DateTime.parse(messages.first['created_at'] as String).toLocal();
    final dateStr = '${firstDate.month}/${firstDate.day}/${firstDate.year}';

    final buffer = StringBuffer();
    buffer.writeln('Conversation with Co-Pilot');
    buffer.writeln('Date: $dateStr');
    buffer.writeln('');

    for (final m in messages) {
      final dt = DateTime.parse(m['created_at'] as String).toLocal();
      final hr = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      final mn = dt.minute.toString().padLeft(2, '0');
      final ampm = dt.hour >= 12 ? 'PM' : 'AM';
      final time = '$hr:$mn $ampm';
      final speaker = m['role'] == 'user' ? 'You' : 'Co-Pilot';
      buffer.writeln('[$time] $speaker:');
      buffer.writeln(m['content']?.toString() ?? '');
      buffer.writeln('');
    }

    return buffer.toString();
  }

  Future<void> _share(BuildContext context) async {
    final text = _buildShareText();
    final box = context.findRenderObject() as RenderBox?;
    await Share.share(
      text,
      subject: 'TruCost Co-Pilot Conversation',
      sharePositionOrigin: box != null ? box.localToGlobal(Offset.zero) & box.size : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final messages = session['messages'] as List;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transcript'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () => _share(context),
            tooltip: 'Share transcript',
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: messages.length,
        itemBuilder: (ctx, i) {
          final m = messages[i];
          final isUser = m['role'] == 'user';
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
                      m['content']?.toString() ?? '',
                      style: TextStyle(color: isUser ? Colors.white : Colors.black87, fontSize: 15),
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
        },
      ),
    );
  }
}
