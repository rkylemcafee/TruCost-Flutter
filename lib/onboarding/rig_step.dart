import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

/// Step 3: Add one truck, one trailer, and an optional rig photo.
/// More units can be added later from Settings.
///
/// Goes in: lib/onboarding/rig_step.dart

class RigStep extends StatefulWidget {
  final VoidCallback onNext;
  const RigStep({super.key, required this.onNext});

  @override
  State<RigStep> createState() => _RigStepState();
}

class _RigStepState extends State<RigStep> {
  final _supabase = Supabase.instance.client;

  // Truck
  final _truckNumCtrl = TextEditingController();
  String _truckCostMode = 'owned';
  final _truckPriceCtrl = TextEditingController(text: '140000');
  final _truckDeprecCtrl = TextEditingController(text: '20');
  final _truckResidualCtrl = TextEditingController(text: '56000'); // ~40% of 140k
  final _truckPaymentCtrl = TextEditingController();
  // MPG / speed / sleeper live on the truck (the iron), not the profile.
  final _truckEmptyMpgCtrl = TextEditingController(text: '8');
  final _truckLoadedMpgCtrl = TextEditingController(text: '6');
  final _truckSpeedEmptyCtrl = TextEditingController(text: '60');
  final _truckSpeedLoadedCtrl = TextEditingController(text: '55');
  bool _truckHasSleeper = true;

  // Trailer
  String _trailerType = 'flatbed';
  final _trailerNumCtrl = TextEditingController();
  String _trailerCostMode = 'owned';
  final _trailerPriceCtrl = TextEditingController(text: '40000');
  final _trailerDeprecCtrl = TextEditingController(text: '20');
  final _trailerResidualCtrl = TextEditingController(text: '24000'); // ~60% of 40k
  final _trailerPaymentCtrl = TextEditingController();

  // Photo
  File? _rigPhoto;
  bool _loading = false;

  // ── Photo handling ──
  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );
      if (picked == null) return;

      final appDir = await getApplicationDocumentsDirectory();
      final savedPath = '${appDir.path}/rig_photo.jpg';
      final savedFile = await File(picked.path).copy(savedPath);
      setState(() => _rigPhoto = savedFile);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load photo: $e')),
        );
      }
    }
  }

  void _showPhotoOptions() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take a Photo'),
              onTap: () {
                Navigator.pop(ctx);
                _pickPhoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.pop(ctx);
                _pickPhoto(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Save ──
  Future<void> _save() async {
    setState(() => _loading = true);
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final truckNum = _truckNumCtrl.text.trim();
      final trailerNum = _trailerNumCtrl.text.trim();

      // Guard against duplicate unit numbers for this operator. A fleet can't
      // have two trucks (or two trailers) wearing the same number.
      final existing = await _supabase
          .from('units')
          .select('unit_number, unit_type')
          .eq('user_id', user.id)
          .filter('deleted_at', 'is', null);
      bool dup(String num, String type) => existing.any((u) =>
          (u['unit_number'] ?? '').toString().trim() == num &&
          u['unit_type'] == type &&
          num.isNotEmpty);
      if (dup(truckNum, 'truck')) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Truck $truckNum already exists.')));
        }
        setState(() => _loading = false);
        return;
      }
      if (dup(trailerNum, 'trailer')) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Trailer $trailerNum already exists.')));
        }
        setState(() => _loading = false);
        return;
      }

      // This onboarding rig becomes THE active rig — clear any previously
      // active units first so we never end up with several marked active.
      await _supabase
          .from('units')
          .update({'is_active': false})
          .eq('user_id', user.id);

      // Save truck
      final truckRow = await _supabase.from('units').insert({
        'user_id': user.id,
        'unit_type': 'truck',
        'unit_number': _truckNumCtrl.text.trim(),
        'cost_mode': _truckCostMode,
        'purchase_price': _truckCostMode == 'owned'
            ? double.tryParse(_truckPriceCtrl.text)
            : null,
        'depreciation_pct': _truckCostMode == 'owned'
            ? double.tryParse(_truckDeprecCtrl.text)
            : null,
        'residual_value': _truckCostMode == 'owned'
            ? double.tryParse(_truckResidualCtrl.text)
            : null,
        'monthly_payment': _truckCostMode == 'financed'
            ? double.tryParse(_truckPaymentCtrl.text)
            : null,
        // MPG / speed / sleeper — the truck's own numbers
        'empty_mpg': double.tryParse(_truckEmptyMpgCtrl.text),
        'loaded_mpg': double.tryParse(_truckLoadedMpgCtrl.text),
        'speed_empty': double.tryParse(_truckSpeedEmptyCtrl.text),
        'speed_loaded': double.tryParse(_truckSpeedLoadedCtrl.text),
        'has_sleeper_berth': _truckHasSleeper,
        'is_active': true,
      }).select('id').single();

      // Save trailer
      final trailerRow = await _supabase.from('units').insert({
        'user_id': user.id,
        'unit_type': 'trailer',
        'trailer_subtype': _trailerType,
        'unit_number': _trailerNumCtrl.text.trim(),
        'cost_mode': _trailerCostMode,
        'purchase_price': _trailerCostMode == 'owned'
            ? double.tryParse(_trailerPriceCtrl.text)
            : null,
        'depreciation_pct': _trailerCostMode == 'owned'
            ? double.tryParse(_trailerDeprecCtrl.text)
            : null,
        'residual_value': _trailerCostMode == 'owned'
            ? double.tryParse(_trailerResidualCtrl.text)
            : null,
        'monthly_payment': _trailerCostMode == 'financed'
            ? double.tryParse(_trailerPaymentCtrl.text)
            : null,
        'is_active': true,
      }).select('id').single();

      // Mark these as the operator's active rig.
      await _supabase.from('profiles').update({
        'active_truck_id': truckRow['id'],
        'active_trailer_id': trailerRow['id'],
      }).eq('user_id', user.id);

      widget.onNext();
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _truckNumCtrl.dispose();
    _truckPriceCtrl.dispose();
    _truckDeprecCtrl.dispose();
    _truckResidualCtrl.dispose();
    _truckPaymentCtrl.dispose();
    _truckEmptyMpgCtrl.dispose();
    _truckLoadedMpgCtrl.dispose();
    _truckSpeedEmptyCtrl.dispose();
    _truckSpeedLoadedCtrl.dispose();
    _trailerNumCtrl.dispose();
    _trailerPriceCtrl.dispose();
    _trailerDeprecCtrl.dispose();
    _trailerResidualCtrl.dispose();
    _trailerPaymentCtrl.dispose();
    super.dispose();
  }

  // Residual auto-tracks the purchase price: 40% for the truck, 60% for the
  // trailer. Recomputes whenever the price changes; user can still type over it.
  void _recalcTruckResidual() {
    final price = double.tryParse(_truckPriceCtrl.text) ?? 0;
    _truckResidualCtrl.text = (price * 0.40).round().toString();
  }

  void _recalcTrailerResidual() {
    final price = double.tryParse(_trailerPriceCtrl.text) ?? 0;
    _trailerResidualCtrl.text = (price * 0.60).round().toString();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Your Rig',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('Add more trucks and trailers later in Settings.',
              style: TextStyle(fontSize: 13, color: Colors.grey)),
          const SizedBox(height: 24),

          // ═══ TRUCK ═══
          const Text('Truck',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(
            controller: _truckNumCtrl,
            decoration: const InputDecoration(
              labelText: 'Truck Number',
              hintText: 'e.g. 7241',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'owned', label: Text('Owned')),
              ButtonSegment(value: 'financed', label: Text('Financed')),
            ],
            selected: {_truckCostMode},
            onSelectionChanged: (v) =>
                setState(() => _truckCostMode = v.first),
          ),
          const SizedBox(height: 12),
          if (_truckCostMode == 'owned') ...[
            TextField(
              controller: _truckPriceCtrl,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(_recalcTruckResidual),
              decoration: const InputDecoration(
                  labelText: 'Purchase Price (\$)',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _truckDeprecCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Annual Depreciation (%)',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _truckResidualCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Residual Value (\$)',
                  helperText: 'What it\'s worth at the end — only the rest is depreciated',
                  border: OutlineInputBorder()),
            ),
          ] else ...[
            TextField(
              controller: _truckPaymentCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Monthly Payment (\$)',
                  border: OutlineInputBorder()),
            ),
          ],

          const SizedBox(height: 16),
          // ── Truck performance: MPG / speed / sleeper (the truck's own numbers) ──
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _truckEmptyMpgCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Empty MPG', border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _truckLoadedMpgCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Loaded MPG', border: OutlineInputBorder()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _truckSpeedEmptyCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Empty Speed', suffixText: 'mph', border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _truckSpeedLoadedCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Loaded Speed', suffixText: 'mph', border: OutlineInputBorder()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SwitchListTile(
            title: const Text('Sleeper berth'),
            subtitle: const Text('Off = you pay for hotels on overnight runs'),
            value: _truckHasSleeper,
            onChanged: (v) => setState(() => _truckHasSleeper = v),
            contentPadding: EdgeInsets.zero,
          ),

          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),

          // ═══ TRAILER ═══
          const Text('Trailer',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _trailerType,
            decoration: const InputDecoration(
                labelText: 'Trailer Type', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'flatbed', child: Text('Flatbed')),
              DropdownMenuItem(value: 'step_deck', child: Text('Step Deck')),
              DropdownMenuItem(
                  value: 'double_drop', child: Text('Double Drop')),
              DropdownMenuItem(value: 'dry_van', child: Text('Dry Van')),
              DropdownMenuItem(value: 'reefer', child: Text('Reefer')),
            ],
            onChanged: (v) => setState(() => _trailerType = v ?? 'flatbed'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _trailerNumCtrl,
            decoration: const InputDecoration(
              labelText: 'Trailer Number',
              hintText: 'e.g. T-100',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'owned', label: Text('Owned')),
              ButtonSegment(value: 'financed', label: Text('Financed')),
            ],
            selected: {_trailerCostMode},
            onSelectionChanged: (v) =>
                setState(() => _trailerCostMode = v.first),
          ),
          const SizedBox(height: 12),
          if (_trailerCostMode == 'owned') ...[
            TextField(
              controller: _trailerPriceCtrl,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(_recalcTrailerResidual),
              decoration: const InputDecoration(
                  labelText: 'Purchase Price (\$)',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _trailerDeprecCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Annual Depreciation (%)',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _trailerResidualCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Residual Value (\$)',
                  helperText: 'What it\'s worth at the end — only the rest is depreciated',
                  border: OutlineInputBorder()),
            ),
          ] else ...[
            TextField(
              controller: _trailerPaymentCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Monthly Payment (\$)',
                  border: OutlineInputBorder()),
            ),
          ],

          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),

          // ═══ RIG PHOTO ═══
          const Text('Rig Photo',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text(
            'Add a photo of your rig — it becomes your app splash screen.',
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          if (_rigPhoto != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(_rigPhoto!, height: 200, fit: BoxFit.cover),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _showPhotoOptions,
              child: const Text('Change Photo'),
            ),
          ] else ...[
            OutlinedButton.icon(
              onPressed: _showPhotoOptions,
              icon: const Icon(Icons.camera_alt),
              label: const Text('Add Rig Photo'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ],
          Text('Optional — you can add this later.',
              style: TextStyle(fontSize: 12, color: Colors.grey[500])),

          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: _loading ? null : _save,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: _loading
                ? const SizedBox(
                    height: 20, width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Next', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }
}
