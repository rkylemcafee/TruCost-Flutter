import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Lets the driver browse every on-device voice, preview it, and save their
/// pick to their profile. No API calls — uses the free native iOS/Android
/// voices already on the phone.
///
/// Goes in: lib/copilot/voice_settings_screen.dart
///
/// Returns `true` via Navigator.pop when a new voice was saved, so the caller
/// can re-apply it immediately.

class VoiceSettingsScreen extends StatefulWidget {
  const VoiceSettingsScreen({super.key});

  @override
  State<VoiceSettingsScreen> createState() => _VoiceSettingsScreenState();
}

class _VoiceSettingsScreenState extends State<VoiceSettingsScreen> {
  final _supabase = Supabase.instance.client;
  final FlutterTts _tts = FlutterTts();

  List<Map<String, String>> _allVoices = [];
  List<Map<String, String>> _shown = [];

  String? _selectedName;
  String? _selectedLocale;
  String? _previewingName; // which voice is currently speaking
  bool _englishOnly = true;
  bool _loading = true;
  bool _saving = false;
  String _copilotName = 'Co-Pilot';

  // What the driver hears when previewing — keep it on-brand and short.
  String get _sample =>
      "Hey, that load to Miami pays three grand. "
      "After your cut and fuel, you clear about eleven hundred. I'd grab it.";

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.5);
    await _tts.setPitch(1.0);
    _tts.setCompletionHandler(() {
      if (mounted) setState(() => _previewingName = null);
    });

    // Load the driver's current saved voice + co-pilot name.
    try {
      final user = _supabase.auth.currentUser;
      if (user != null) {
        final p = await _supabase
            .from('profiles')
            .select('copilot_name, copilot_voice_name, copilot_voice_locale')
            .eq('user_id', user.id)
            .single();
        _copilotName = (p['copilot_name'] ?? 'Co-Pilot').toString();
        final savedName = (p['copilot_voice_name'] ?? '').toString();
        final savedLocale = (p['copilot_voice_locale'] ?? '').toString();
        if (savedName.isNotEmpty && savedLocale.isNotEmpty) {
          _selectedName = savedName;
          _selectedLocale = savedLocale;
        }
      }
    } catch (_) {
      // no saved prefs yet — fine
    }

    // Pull every voice the device exposes.
    try {
      final raw = await _tts.getVoices;
      final List<Map<String, String>> voices = [];
      final seen = <String>{};
      if (raw is List) {
        for (final v in raw) {
          if (v is Map) {
            final name = (v['name'] ?? '').toString();
            final locale = (v['locale'] ?? '').toString();
            if (name.isEmpty || locale.isEmpty) continue;
            final key = '$name|$locale';
            if (seen.contains(key)) continue;
            seen.add(key);
            voices.add({'name': name, 'locale': locale});
          }
        }
      }

      voices.sort((a, b) {
        // English voices first, then alphabetical by display name.
        final aEn = a['locale']!.toLowerCase().startsWith('en') ? 0 : 1;
        final bEn = b['locale']!.toLowerCase().startsWith('en') ? 0 : 1;
        if (aEn != bEn) return aEn.compareTo(bEn);
        return _pretty(a['name']!).toLowerCase().compareTo(_pretty(b['name']!).toLowerCase());
      });

      _allVoices = voices;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load voices: $e')),
        );
      }
    }

    _applyFilter();
    if (mounted) setState(() => _loading = false);
  }

  void _applyFilter() {
    _shown = _englishOnly
        ? _allVoices.where((v) => v['locale']!.toLowerCase().startsWith('en')).toList()
        : _allVoices;
  }

  // Android voice names are ugly ("en-us-x-sfg#female_1-local"). iOS names are
  // already human ("Samantha", "Daniel"). Clean up the ugly ones.
  String _pretty(String name) {
    if (!name.contains('#') && !name.contains('-x-') && !name.contains('_')) {
      return name;
    }
    final genderMatch = RegExp(r'(female|male)', caseSensitive: false).firstMatch(name);
    final numMatch = RegExp(r'[_#](\d+)').firstMatch(name);
    final gender = genderMatch != null
        ? '${genderMatch.group(1)![0].toUpperCase()}${genderMatch.group(1)!.substring(1).toLowerCase()}'
        : 'Voice';
    final num = numMatch != null ? ' ${numMatch.group(1)}' : '';
    return '$gender$num';
  }

  Future<void> _preview(Map<String, String> v) async {
    // Tapping the same one while it's talking = stop.
    if (_previewingName == v['name']) {
      await _tts.stop();
      if (mounted) setState(() => _previewingName = null);
      return;
    }
    await _tts.stop();
    setState(() => _previewingName = v['name']);
    try {
      await _tts.setVoice({'name': v['name']!, 'locale': v['locale']!});
      await _tts.speak(_sample);
    } catch (e) {
      if (mounted) {
        setState(() => _previewingName = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not play that voice: $e')),
        );
      }
    }
  }

  void _select(Map<String, String> v) {
    setState(() {
      _selectedName = v['name'];
      _selectedLocale = v['locale'];
    });
  }

  Future<void> _save() async {
    if (_selectedName == null || _selectedLocale == null) return;
    setState(() => _saving = true);
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('Not signed in');

      await _supabase.from('profiles').update({
        'copilot_voice_name': _selectedName,
        'copilot_voice_locale': _selectedLocale,
      }).eq('user_id', user.id);

      await _tts.stop();
      if (mounted) Navigator.pop(context, true); // signal caller to re-apply
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _selectedName != null && !_saving;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Co-Pilot Voice'),
        actions: [
          Row(
            children: [
              const Text('English only', style: TextStyle(fontSize: 12)),
              Switch(
                value: _englishOnly,
                onChanged: (v) => setState(() {
                  _englishOnly = v;
                  _applyFilter();
                }),
              ),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  color: Colors.blueGrey[50],
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Pick how $_copilotName sounds',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(
                        'Tap ▶ to hear a voice. Tap the row to choose it. '
                        'All voices are free and live on your phone — no data, no monthly cost.',
                        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('${_shown.length} voice${_shown.length != 1 ? 's' : ''} available',
                        style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                  ),
                ),
                Expanded(
                  child: _shown.isEmpty
                      ? const Center(child: Text('No voices found on this device.'))
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: _shown.length,
                          itemBuilder: (ctx, i) => _voiceTile(_shown[i]),
                        ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: canSave ? _save : null,
                        icon: _saving
                            ? const SizedBox(
                                width: 18, height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.check),
                        label: Text(_saving ? 'Saving...' : 'Use This Voice'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: Colors.blueGrey[700],
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.grey[300],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _voiceTile(Map<String, String> v) {
    final isSelected = v['name'] == _selectedName && v['locale'] == _selectedLocale;
    final isPlaying = v['name'] == _previewingName;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: isSelected ? Colors.blueGrey[50] : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: isSelected ? Colors.blueGrey : Colors.transparent,
          width: isSelected ? 1.5 : 0,
        ),
      ),
      child: ListTile(
        leading: IconButton(
          icon: Icon(isPlaying ? Icons.stop_circle : Icons.play_circle_fill,
              color: Colors.blueGrey[600], size: 34),
          onPressed: () => _preview(v),
          tooltip: isPlaying ? 'Stop' : 'Preview',
        ),
        title: Text(_pretty(v['name']!),
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(v['locale']!, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
        trailing: isSelected
            ? const Icon(Icons.check_circle, color: Colors.green)
            : const Icon(Icons.radio_button_unchecked, color: Colors.grey),
        onTap: () => _select(v),
      ),
    );
  }
}
