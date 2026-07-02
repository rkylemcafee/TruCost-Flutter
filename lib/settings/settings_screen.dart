import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import '../help/help_content.dart';
import 'rig_tab.dart';
import '../common/state_picker_screen.dart';

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
  final _annualHoursCtrl = TextEditingController();
  final _cargoInsCtrl = TextEditingController();
  final _hotelRateCtrl = TextEditingController();
  final _fscRateCtrl = TextEditingController();
  final _fscReceivedCtrl = TextEditingController();
  final _insRateCtrl = TextEditingController();
  bool _teamOperation = false;
  List<String> _runStates = <String>[];

  // Optional device + contact (profiles.device_* / profiles.phone)
  bool _deviceIphone = false;
  bool _deviceAndroidPhone = false;
  bool _deviceIpad = false;
  bool _deviceAndroidTablet = false;
  final _phoneCtrl = TextEditingController();

  // Authority info for trip-sheet headers.
  final _operatorNameCtrl = TextEditingController();
  final _mcCtrl = TextEditingController();
  final _dotCtrl = TextEditingController();
  final _carrierCtrl = TextEditingController();

  bool _carrierFuelCard = false; // carrier covers fuel (card/advance), deducted on settlement

  bool _loading = true;
  bool _saving = false;
  bool _settingPw = false;
  bool _obscurePw = true;
  String? _splashUrl;
  bool _uploadingPhoto = false;

  static const List<String> _presets = ['Gigi', 'TruCost Co-Pilot', 'Dave', 'Charlie'];

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
              'annual_work_hours, splash_photo_url, '
              'operator_name, mc_number, dot_number, carrier_name, carrier_fuel_card, '
              'cargo_insurance, team_operation, hotel_rate, run_states, '
              'device_iphone, device_android_phone, device_ipad, device_android_tablet, phone, '
              'fsc_rate, fsc_pct_received, carrier_insurance_pct')
          .eq('user_id', user.id)
          .maybeSingle();

      _copilotNameCtrl.text = (p?['copilot_name'] ?? '').toString();
      _driverNameCtrl.text = (p?['preferred_name'] ?? '').toString();
      _hourlyRateCtrl.text = _numStr(p?['hourly_rate']);
      _carrierCutCtrl.text = _numStr(p?['carrier_cut_pct']);
      _overheadCtrl.text = _numStr(p?['overhead_pct']);
      _annualHoursCtrl.text = _numStr(p?['annual_work_hours']);
      _splashUrl = p?['splash_photo_url']?.toString();
      _operatorNameCtrl.text = (p?['operator_name'] ?? '').toString();
      _mcCtrl.text = (p?['mc_number'] ?? '').toString();
      _dotCtrl.text = (p?['dot_number'] ?? '').toString();
      _carrierCtrl.text = (p?['carrier_name'] ?? '').toString();
      _carrierFuelCard = p?['carrier_fuel_card'] == true;
      _cargoInsCtrl.text = _numStr(p?['cargo_insurance']);
      _hotelRateCtrl.text = _numStr(p?['hotel_rate']);
      _fscRateCtrl.text = _numStr(p?['fsc_rate'] ?? 6);
      _fscReceivedCtrl.text = _numStr(p?['fsc_pct_received'] ?? 100);
      _insRateCtrl.text = _numStr(p?['carrier_insurance_pct'] ?? 3);
      _teamOperation = p?['team_operation'] == true;
      _runStates = (p?['run_states'] as List?)?.cast<String>() ?? <String>[];
      _deviceIphone = p?['device_iphone'] == true;
      _deviceAndroidPhone = p?['device_android_phone'] == true;
      _deviceIpad = p?['device_ipad'] == true;
      _deviceAndroidTablet = p?['device_android_tablet'] == true;
      _phoneCtrl.text = (p?['phone'] ?? '').toString();
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
      updates['copilot_name'] = cn.isEmpty ? 'Gigi' : cn;
      final dn = _driverNameCtrl.text.trim();
      updates['preferred_name'] = dn.isEmpty ? null : dn;

      void addNum(String key, TextEditingController c) {
        final v = double.tryParse(c.text.trim());
        if (v != null) updates[key] = v;
      }

      addNum('hourly_rate', _hourlyRateCtrl);
      addNum('carrier_cut_pct', _carrierCutCtrl);
      addNum('overhead_pct', _overheadCtrl);
      addNum('annual_work_hours', _annualHoursCtrl);

      void addText(String key, TextEditingController c) {
        final v = c.text.trim();
        updates[key] = v.isEmpty ? null : v;
      }

      addText('operator_name', _operatorNameCtrl);
      addText('mc_number', _mcCtrl);
      addText('dot_number', _dotCtrl);
      addText('carrier_name', _carrierCtrl);
      updates['carrier_fuel_card'] = _carrierFuelCard;
      addNum('cargo_insurance', _cargoInsCtrl);
      addNum('hotel_rate', _hotelRateCtrl);
      addNum('fsc_rate', _fscRateCtrl);
      addNum('fsc_pct_received', _fscReceivedCtrl);
      addNum('carrier_insurance_pct', _insRateCtrl);
      updates['team_operation'] = _teamOperation;
      updates['run_states'] = _runStates;
      updates['device_iphone'] = _deviceIphone;
      updates['device_android_phone'] = _deviceAndroidPhone;
      updates['device_ipad'] = _deviceIpad;
      updates['device_android_tablet'] = _deviceAndroidTablet;
      final ph = _phoneCtrl.text.trim();
      updates['phone'] = ph.isEmpty ? null : ph;

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
    _annualHoursCtrl.dispose();
    _cargoInsCtrl.dispose();
    _hotelRateCtrl.dispose();
    _operatorNameCtrl.dispose();
    _mcCtrl.dispose();
    _dotCtrl.dispose();
    _carrierCtrl.dispose();
    _phoneCtrl.dispose();
    _fscRateCtrl.dispose();
    _fscReceivedCtrl.dispose();
    _insRateCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // Tap outside a field to dismiss the keyboard. The numeric keypad has no
      // Done button, so without this the Save button can stay hidden behind it.
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        // Body shrinks above the keyboard on every device; the Save bar lives
        // INSIDE that body (see below), so it floats just above the keyboard
        // instead of being buried behind it.
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          title: const Text('Setup & Settings'),
          actions: const [HelpButton(HelpScreens.settings)],
          bottom: TabBar(
            controller: _tab,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            indicatorWeight: 3,
            labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15),
            tabs: const [
              Tab(text: 'Preferences'),
              Tab(text: 'Business'),
              Tab(text: 'Rig'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Expanded(
                    child: TabBarView(
                      controller: _tab,
                      children: [_preferencesTab(), _businessTab(), const RigTab()],
                    ),
                  ),
                  // Rig tab (index 2) saves per-unit in its own dialogs, so it
                  // has no Save bar. On the other tabs the bar sits at the
                  // bottom of the body and rides above the keyboard.
                  if (_tab.index != 2) _saveBar(),
                ],
              ),
      ),
    );
  }

  Widget _saveBar() {
    return SafeArea(
      top: false, // guard only the bottom (home indicator / rounded corners)
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(top: BorderSide(color: Colors.grey.shade300)),
        ),
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
        const Text("Call her by this and she'll answer. Tap one or type your own.",
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
        const Text('What should she call you?',
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
        const Text('Authority (for trip sheets)',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        const Text('Printed on the header of every trip sheet. Fill in what applies to you.',
            style: TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 10),
        TextField(
          controller: _operatorNameCtrl,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Your name / business',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _mcCtrl,
                decoration: const InputDecoration(
                  labelText: 'MC #',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _dotCtrl,
                decoration: const InputDecoration(
                  labelText: 'DOT #',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _carrierCtrl,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Leased to (carrier)',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
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
        const SizedBox(height: 4),
        SwitchListTile(
          title: const Text('Carrier fuel card / advance'),
          subtitle: const Text('If on, fuel bought this way is deducted from your settlement'),
          value: _carrierFuelCard,
          onChanged: (v) => setState(() => _carrierFuelCard = v),
          contentPadding: EdgeInsets.zero,
        ),
        const SizedBox(height: 12),
        const Text('Fuel surcharge',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        const Text(
            'FSC is passed through — your carrier doesn\'t take a cut of it, and it '
            'counts as income toward your hourly. Most carriers run about 6%.',
            style: TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _numberField(_fscRateCtrl, 'FSC (% of gross)', suffix: '%')),
            const SizedBox(width: 12),
            Expanded(child: _numberField(_fscReceivedCtrl, 'You keep', suffix: '%')),
          ],
        ),
        const SizedBox(height: 16),
        const Text('Carrier insurance',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        const Text(
            'Some carriers take a slice of your gross for insurance — it comes off '
            'the top before your cut, and you keep none of it. Often 3–4%. Leave 0 '
            'if your carrier doesn\'t, or if you run your own authority.',
            style: TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 12),
        _numberField(_insRateCtrl, 'Carrier insurance (% of gross)', suffix: '%'),
        const SizedBox(height: 24),
        const Text('Your Time',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
        const SizedBox(height: 4),
        const Text('Hours you work in a year — this sets your target hourly rate.',
            style: TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 12),
        _numberField(_annualHoursCtrl, 'Annual working hours', suffix: 'hrs/yr'),
        const SizedBox(height: 10),
        const Text('MPG and road speed live on your truck — set them under the Rig tab.',
            style: TextStyle(fontSize: 11, color: Colors.grey)),

        const SizedBox(height: 24),
        const Text('Coverage & How You Run',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
        const SizedBox(height: 4),
        const Text('Used to match you to the right agents and to price overnights.',
            style: TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 12),
        _numberField(_cargoInsCtrl, 'Cargo insurance you carry', prefix: '\$'),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          _insChip('100K', 100000),
          _insChip('500K', 500000),
          _insChip('1M', 1000000),
        ]),
        const SizedBox(height: 12),
        SwitchListTile(
          title: const Text('Team operation'),
          subtitle: const Text('You run with a co-driver'),
          value: _teamOperation,
          onChanged: (v) => setState(() => _teamOperation = v),
          contentPadding: EdgeInsets.zero,
        ),
        const SizedBox(height: 8),
        _numberField(_hotelRateCtrl, 'Hotel rate (overnight, no sleeper)', prefix: '\$', suffix: '/night'),
        const SizedBox(height: 12),
        InkWell(
          onTap: _pickRunStates,
          child: InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Where you like to run',
              border: OutlineInputBorder(),
              isDense: true,
              suffixIcon: Icon(Icons.map_outlined, size: 20),
            ),
            child: Text(_runStatesLabel(),
                style: TextStyle(
                  fontSize: 14,
                  color: _runStates.isEmpty ? Colors.grey[500] : Colors.black87,
                )),
          ),
        ),
        const SizedBox(height: 24),
        const Text('Your Device & Contact',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
        const SizedBox(height: 4),
        const Text('Optional — helps us test on the right hardware and reach you about the beta.',
            style: TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 4),
        CheckboxListTile(
          title: const Text('iPhone'),
          value: _deviceIphone,
          onChanged: (v) => setState(() => _deviceIphone = v ?? false),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          dense: true,
        ),
        CheckboxListTile(
          title: const Text('Android phone'),
          value: _deviceAndroidPhone,
          onChanged: (v) => setState(() => _deviceAndroidPhone = v ?? false),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          dense: true,
        ),
        CheckboxListTile(
          title: const Text('iPad'),
          value: _deviceIpad,
          onChanged: (v) => setState(() => _deviceIpad = v ?? false),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          dense: true,
        ),
        CheckboxListTile(
          title: const Text('Android tablet'),
          value: _deviceAndroidTablet,
          onChanged: (v) => setState(() => _deviceAndroidTablet = v ?? false),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          dense: true,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _phoneCtrl,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Phone (optional)',
            helperText: 'So we can reach you about the beta.',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  String _runStatesLabel() {
    if (_runStates.isEmpty) return 'None set — tap to choose';
    if (_runStates.length >= kUsStates.length) return 'All 48 states';
    return _runStates.join(', ');
  }

  Widget _insChip(String label, int value) {
    return ActionChip(
      label: Text('\$$label'),
      onPressed: () => setState(() => _cargoInsCtrl.text = value.toString()),
    );
  }

  Future<void> _pickRunStates() async {
    final result = await Navigator.push<List<String>>(
      context,
      MaterialPageRoute(
        builder: (_) => StatePickerScreen(initial: _runStates, title: 'Where You Run'),
      ),
    );
    if (result != null) setState(() => _runStates = result);
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
