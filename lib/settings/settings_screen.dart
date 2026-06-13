import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'rig_tab.dart';

/// Tabbed settings — the way back into everything onboarding set up.
///   • Preferences: co-pilot name, your name, take-home target, password
///   • Business: carrier cut, overhead, fuel, MPG, speeds, annual hours
///
/// Goes in: lib/settings/settings_screen.dart

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tab;
  final _supabase = Supabase.instance.client;

  // Preferences
  final _copilotNameCtrl = TextEditingController();
  final _driverNameCtrl = TextEditingController();
  final _hourlyRateCtrl = TextEditingController();
  final _newPasswordCtrl = TextEditingController();

  // Business
  final _carrierCutCtrl = TextEditingController();
  final _overheadCtrl = TextEditingController();
  final _fuelPriceCtrl = TextEditingController();
  final _emptyMpgCtrl = TextEditingController();
  final _loadedMpgCtrl = TextEditingController();
  final _speedEmptyCtrl = TextEditingController();
  final _speedLoadedCtrl = TextEditingController();
  final _annualHoursCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _settingPw = false;
  bool _obscurePw = true;
  String? _splashUrl;
  bool _uploadingPhoto = false;

  static const List<String> _presets = ['TruCost Co-Pilot', 'Dave', 'Charlie'];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _tab.addListener(() {
      if (mounted) setState(() {});
    });
    _load();
  }

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
  }

  String _numStr(dynamic v) {
    if (v == null) return '';
    final d = v is num ? v.toDouble() : double.tryParse(v.toString());
    if (d == null) return v.toString();
    if (d == d.roundToDouble()) return d.toInt().toString();
    return d.toString();
  }

  Future<void> _load() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;
      final p = await _supabase
          .from('profiles')
          .select(
              'copilot_name, preferred_name, hourly_rate, carrier_cut_pct, overhead_pct, '
              'fuel_price_default, empty_mpg, loaded_mpg, speed_empty, speed_loaded, annual_work_hours, splash_photo_url')
          .eq('user_id', user.id)
          .maybeSingle();

      _copilotNameCtrl.text = (p?['copilot_name'] ?? '').toString();
      _driverNameCtrl.text = (p?['preferred_name'] ?? '').toString();
      _hourlyRateCtrl.text = _numStr(p?['hourly_rate']);
      _carrierCutCtrl.text = _numStr(p?['carrier_cut_pct']);
      _overheadCtrl.text = _numStr(p?['overhead_pct']);
      _fuelPriceCtrl.text = _numStr(p?['fuel_price_default']);
      _emptyMpgCtrl.text = _numStr(p?['empty_mpg']);
      _loadedMpgCtrl.text = _numStr(p?['loaded_mpg']);
      _speedEmptyCtrl.text = _numStr(p?['speed_empty']);
      _speedLoadedCtrl.text = _numStr(p?['speed_loaded']);
      _annualHoursCtrl.text = _numStr(p?['annual_work_hours']);
      _splashUrl = p?['splash_photo_url']?.toString();
    } catch (e) {
      _toast('Could not load settings: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final updates = <String, dynamic>{};
      final cn = _copilotNameCtrl.text.trim();
      updates['copilot_name'] = cn.isEmpty ? 'Co-Pilot' : cn;
      final dn = _driverNameCtrl.text.trim();
      updates['preferred_name'] = dn.isEmpty ? null : dn;

      void addNum(String key, TextEditingController c) {
        final v = double.tryParse(c.text.trim());
        if (v != null) updates[key] = v;
      }

      addNum('hourly_rate', _hourlyRateCtrl);
      addNum('carrier_cut_pct', _carrierCutCtrl);
      addNum('overhead_pct', _overheadCtrl);
      addNum('fuel_price_default', _fuelPriceCtrl);
      addNum('empty_mpg', _emptyMpgCtrl);
      addNum('loaded_mpg', _loadedMpgCtrl);
      addNum('speed_empty', _speedEmptyCtrl);
      addNum('speed_loaded', _speedLoadedCtrl);
      addNum('annual_work_hours', _annualHoursCtrl);

      await _supabase.from('profiles').update(updates).eq('user_id', user.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: const Text('Saved'), backgroundColor: Colors.green[700]),
        );
      }
    } catch (e) {
      _toast('Save failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setPassword() async {
    final pw = _newPasswordCtrl.text;
    if (pw.length < 6) {
      _toast('Use at least 6 characters.');
      return;
    }
    setState(() => _settingPw = true);
    try {
      await _supabase.auth.updateUser(UserAttributes(password: pw));
      _newPasswordCtrl.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Password set — use it to sign in next time.'),
            backgroundColor: Colors.green[700],
          ),
        );
      }
    } on AuthException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('Could not set password: $e');
    } finally {
      if (mounted) setState(() => _settingPw = false);
    }
  }

  @override
  void dispose() {
    _tab.dispose();
    _copilotNameCtrl.dispose();
    _driverNameCtrl.dispose();
    _hourlyRateCtrl.dispose();
    _newPasswordCtrl.dispose();
    _carrierCutCtrl.dispose();
    _overheadCtrl.dispose();
    _fuelPriceCtrl.dispose();
    _emptyMpgCtrl.dispose();
    _loadedMpgCtrl.dispose();
    _speedEmptyCtrl.dispose();
    _speedLoadedCtrl.dispose();
    _annualHoursCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Setup & Settings'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'Preferences'),
            Tab(text: 'Business'),
            Tab(text: 'Rig'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tab,
              children: [_preferencesTab(), _businessTab(), const RigTab()],
            ),
      bottomNavigationBar: (_loading || _tab.index == 2)
          ? null
          : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.blueGrey[700],
                        foregroundColor: Colors.white,
                      ),
                      child: _saving
                          ? const SizedBox(
                              height: 20, width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Save Changes', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                ),
              ),
    );
  }

  Future<void> _pickSplashPhoto() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 80,
      );
      if (picked == null) return;
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      setState(() => _uploadingPhoto = true);
      final bytes = await picked.readAsBytes();
      final path = '${user.id}/splash.jpg';
      await _supabase.storage.from('rig-photos').uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(upsert: true, contentType: 'image/jpeg'),
          );
      // Same path each time, so bust the cache with a version tag.
      final url =
          '${_supabase.storage.from('rig-photos').getPublicUrl(path)}?v=${DateTime.now().millisecondsSinceEpoch}';
      await _supabase.from('profiles').update({'splash_photo_url': url}).eq('user_id', user.id);
      if (mounted) {
        setState(() {
          _splashUrl = url;
          _uploadingPhoto = false;
        });
        _toast('Home photo updated  it shows on your home screen.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _uploadingPhoto = false);
        _toast('Could not set photo: $e');
      }
    }
  }

  Future<void> _removeSplashPhoto() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;
      await _supabase.from('profiles').update({'splash_photo_url': null}).eq('user_id', user.id);
      try {
        await _supabase.storage.from('rig-photos').remove(['${user.id}/splash.jpg']);
      } catch (_) {}
      if (mounted) setState(() => _splashUrl = null);
    } catch (e) {
      _toast('Could not remove photo: $e');
    }
  }

  Widget _buildHomePhoto() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_splashUrl != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.network(
              _splashUrl!,
              height: 160,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                height: 160,
                color: Colors.grey[200],
                child: const Center(child: Text('Photo unavailable')),
              ),
            ),
          ),
        if (_splashUrl != null) const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _uploadingPhoto ? null : _pickSplashPhoto,
                icon: _uploadingPhoto
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.photo_library, size: 18),
                label: Text(_splashUrl != null ? 'Change photo' : 'Choose photo'),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
              ),
            ),
            if (_splashUrl != null) ...[
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Remove photo',
                onPressed: _uploadingPhoto ? null : _removeSplashPhoto,
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _preferencesTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text("Your co-pilot's name",
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        const Text("Call him by this and he'll answer. Tap one or type your own.",
            style: TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: _presets
              .map((name) => ActionChip(
                    label: Text(name),
                    onPressed: () => setState(() => _copilotNameCtrl.text = name),
                  ))
              .toList(),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _copilotNameCtrl,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Co-Pilot name',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 20),
        const Text('What should he call you?',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        TextField(
          controller: _driverNameCtrl,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Your name',
            hintText: 'e.g. Kyle',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 20),
        const Text('Take-home target',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        const Text('What you want to clear per hour, before taxes. Drives the TAKE IT / PASS call.',
            style: TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 8),
        _numberField(_hourlyRateCtrl, 'Target per hour', prefix: '\$ ', suffix: '/hr'),
        const SizedBox(height: 8),
        const Divider(),
        const SizedBox(height: 12),
        const Text('Home photo',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        const Text('The picture behind your home screen  your rig, your family, whatever. Syncs to every device.',
            style: TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 10),
        _buildHomePhoto(),
        const SizedBox(height: 8),
        const Divider(),
        const SizedBox(height: 12),
        const Text('Password',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        const Text('Set one so you can sign in on any device without an email code.',
            style: TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 10),
        TextField(
          controller: _newPasswordCtrl,
          obscureText: _obscurePw,
          decoration: InputDecoration(
            labelText: 'New password',
            border: const OutlineInputBorder(),
            isDense: true,
            suffixIcon: IconButton(
              icon: Icon(_obscurePw ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _obscurePw = !_obscurePw),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: _settingPw ? null : _setPassword,
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            child: _settingPw
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Set Password', style: TextStyle(fontSize: 16)),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _businessTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Your Deal',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
        const SizedBox(height: 4),
        const Text('Changed your carrier or your overhead? Update it here.',
            style: TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _numberField(_carrierCutCtrl, 'Carrier cut', suffix: '%')),
            const SizedBox(width: 12),
            Expanded(child: _numberField(_overheadCtrl, 'Overhead', suffix: '%')),
          ],
        ),
        const SizedBox(height: 24),
        const Text('Your Defaults',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
        const SizedBox(height: 4),
        const Text('These pre-fill every load you run.',
            style: TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 12),
        _numberField(_fuelPriceCtrl, 'Fuel price', prefix: '\$ ', suffix: '/gal'),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _numberField(_emptyMpgCtrl, 'Empty MPG')),
            const SizedBox(width: 12),
            Expanded(child: _numberField(_loadedMpgCtrl, 'Loaded MPG')),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _numberField(_speedEmptyCtrl, 'Empty speed', suffix: 'mph')),
            const SizedBox(width: 12),
            Expanded(child: _numberField(_speedLoadedCtrl, 'Loaded speed', suffix: 'mph')),
          ],
        ),
        const SizedBox(height: 12),
        _numberField(_annualHoursCtrl, 'Annual working hours', suffix: 'hrs/yr'),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _numberField(TextEditingController ctrl, String label, {String? prefix, String? suffix}) {
    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        prefixText: prefix,
        suffixText: suffix,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }
}
