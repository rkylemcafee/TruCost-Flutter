import 'package:supabase_flutter/supabase_flutter.dart';

class CopilotContextManager {
  final SupabaseClient _supabase;

  String driverName = 'driver';
  String copilotName = 'Bob';
  String copilotAvatar = 'initial';
  int memoryDays = 1;
  final List<Map<String, String>> priorContext = [];

  CopilotContextManager({SupabaseClient? supabase})
      : _supabase = supabase ?? Supabase.instance.client;

  Future<void> loadNames() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;
      final p = await _supabase
          .from('profiles')
          .select('preferred_name, copilot_name, copilot_avatar, copilot_memory_days')
          .eq('user_id', user.id)
          .single();
      driverName = p['preferred_name'] ?? 'driver';
      copilotName = p['copilot_name'] ?? 'Bob';
      copilotAvatar = (p['copilot_avatar'] ?? 'initial').toString();
      memoryDays = (p['copilot_memory_days'] ?? 1) as int;
    } catch (_) {}
  }

  Future<void> loadPriorContext({String? excludeSessionId}) async {
    priorContext.clear();
    if (memoryDays <= 0) return;
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;
      final since = DateTime.now()
          .toUtc()
          .subtract(Duration(days: memoryDays))
          .toIso8601String();
      var query = _supabase
          .from('copilot_messages')
          .select('role, content, created_at')
          .eq('user_id', user.id)
          .gte('created_at', since);
      if (excludeSessionId != null && excludeSessionId.isNotEmpty) {
        query = query.neq('session_id', excludeSessionId);
      }
      final data = await query.order('created_at', ascending: true);

      final all = <Map<String, String>>[];
      for (final m in data as List) {
        final role = (m['role'] ?? '').toString();
        final content = (m['content'] ?? '').toString();
        if (content.isEmpty) continue;
        if (role != 'user' && role != 'assistant') continue;
        all.add({'role': role, 'content': content});
      }
      final trimmed = all.length > 30 ? all.sublist(all.length - 30) : all;
      priorContext
        ..clear()
        ..addAll(trimmed);
    } catch (_) {}
  }

  List<Map<String, String>> buildOutgoingHistory(List<Map<String, String>> currentMessages) {
    return [
      ...priorContext,
      if (currentMessages.length > 1) ...currentMessages.sublist(0, currentMessages.length - 1),
    ];
  }
}
