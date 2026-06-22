import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'copilot_avatar.dart';

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
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _driverCtrl = TextEditingController();

  List<Map<String, String>> _allVoices = [];
  List<Map<String, String>> _shown = [];

  String? _selectedName;
  String? _selectedLocale;
  String? _previewingName; // which voice is currently speaking
  bool _englishOnly = true;
  bool _loading = true;
  bool _saving = false;
  bool _noHqVoices = false; // true when no Enhanced/Premium voices are installed
  String _copilotName = 'Co-Pilot';
  int _memoryDays = 1; // 0 = no memory; how far back the co-pilot recalls
  String _copilotAvatar = 'initial'; // 'initial' or a face key (f1..f3/m1..m3)

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
            .select('copilot_name, preferred_name, copilot_avatar, copilot_memory_days, copilot_voice_name, copilot_voice_locale')
            .eq('user_id', user.id)
            .single();
        _copilotName = (p['copilot_name'] ?? 'Bob').toString();
        _nameCtrl.text = _copilotName;
        _driverCtrl.text = (p['preferred_name'] ?? '').toString();
        _copilotAvatar = (p['copilot_avatar'] ?? 'initial').toString();
        _memoryDays = (p['copilot_memory_days'] ?? 1) as int;
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
    if (_nameCtrl.text.trim().isEmpty) _nameCtrl.text = 'Bob';

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
            final quality = (v['quality'] ?? '').toString();
            voices.add({'name': name, 'locale': locale, 'quality': quality});
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

  // Apple's Enhanced and Premium voices sound human; the default/compact ones sound robotic.
  bool _isHq(Map<String, String> v) {
    final q = (v['quality'] ?? '').toLowerCase();
    return q == 'enhanced' || q == 'premium';
  }

  // English always; Spanish too when the "English only" switch is off.
  bool _localeOk(Map<String, String> v) {
    final loc = v['locale']!.toLowerCase();
    final isEn = loc.startsWith('en');
    final isEs = loc.startsWith('es');
    return _englishOnly ? isEn : (isEn || isEs);
  }

  void _applyFilter() {
    final hq = _allVoices.where((v) => _localeOk(v) && _isHq(v)).toList();
    if (hq.isNotEmpty) {
      _shown = hq;
      _noHqVoices = false;
    } else {
      // No Enhanced/Premium installed for these languages — don't strand the driver
      // with an empty list; show what's available and nudge them to download better ones.
      _shown = _allVoices.where(_localeOk).toList();
      _noHqVoices = true;
    }
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
    setState(() => _saving = true);
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('Not signed in');

      final copilotName =
          _nameCtrl.text.trim().isEmpty ? 'Bob' : _nameCtrl.text.trim();
      final driverName = _driverCtrl.text.trim();

      final update = <String, dynamic>{
        'copilot_name': copilotName,
        'preferred_name': driverName.isEmpty ? null : driverName,
        'copilot_avatar': _copilotAvatar,
        'copilot_memory_days': _memoryDays,
      };
      // Only touch the voice fields if a voice is actually selected.
      if (_selectedName != null && _selectedLocale != null) {
        update['copilot_voice_name'] = _selectedName;
        update['copilot_voice_locale'] = _selectedLocale;
      }

      await _supabase.from('profiles').update(update).eq('user_id', user.id);

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
    _nameCtrl.dispose();
    _driverCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canSave = !_saving;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Co-Pilot Settings'),
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
                // Whole page scrolls as one unit, so the name/face/memory block
                // slides up out of the way and every voice gets room to show.
                Expanded(
                  child: ListView(
                    children: [
                      _identityCard(),
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
                              'Showing only Apple Enhanced and Premium voices — the default ones sound robotic. All are free and already on your phone.',
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
                      if (_noHqVoices)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: Text(
                            'No Enhanced or Premium voices are installed yet, so all available voices are shown. '
                            'To get the good ones: iOS Settings > Accessibility > Spoken Content > Voices, '
                            'pick a voice, and tap the cloud to download its Enhanced or Premium version.',
                            style: TextStyle(fontSize: 12, color: Colors.orange[800]),
                          ),
                        ),
                      if (_shown.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: Text('No voices found on this device.')),
                        )
                      else
                        ..._shown.map((v) => Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: _voiceTile(v),
                            )),
                    ],
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
                        label: Text(_saving ? 'Saving...' : 'Save'),
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

  Widget _identityCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Co-pilot name',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          TextField(
            controller: _nameCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              hintText: 'e.g. Bob',
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
          ),
          const SizedBox(height: 14),
          const Text('Your name (what your co-pilot calls you)',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          TextField(
            controller: _driverCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              hintText: 'e.g. Kyle',
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
          ),
          const SizedBox(height: 18),
          const Text('Co-pilot face',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          SizedBox(
            height: 64,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final key in const ['initial', 'f1', 'f2', 'f3', 'f4', 'm1', 'm2', 'm3', 'm4'])
                  _avatarOption(key),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const Text('Memory',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(
            _memoryDays == 0
                ? 'Starts every chat fresh — no memory of past conversations.'
                : 'Remembers the last ${_memoryDays == 1 ? 'day' : '$_memoryDays days'} of conversations.',
            style: TextStyle(fontSize: 12.5, color: Colors.grey[600]),
          ),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: _memoryDays.toDouble(),
                  min: 0,
                  max: 7,
                  divisions: 7,
                  label: _memoryDays == 0 ? 'Off' : '$_memoryDays d',
                  activeColor: Colors.blueGrey[700],
                  onChanged: (v) => setState(() => _memoryDays = v.round()),
                ),
              ),
              SizedBox(
                width: 44,
                child: Text(
                  _memoryDays == 0 ? 'Off' : '${_memoryDays}d',
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Divider(),
        ],
      ),
    );
  }

  Widget _avatarOption(String key) {
    final selected = key == _copilotAvatar;
    final nameForInitial =
        _nameCtrl.text.trim().isEmpty ? 'Bob' : _nameCtrl.text.trim();
    return GestureDetector(
      onTap: () => setState(() => _copilotAvatar = key),
      child: Container(
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.all(2.5),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? Colors.blueGrey[700]! : Colors.transparent,
            width: 2.5,
          ),
        ),
        child: CopilotAvatar(
          name: nameForInitial,
          avatarKey: key,
          size: 52,
        ),
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
