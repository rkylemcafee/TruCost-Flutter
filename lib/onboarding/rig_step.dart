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
  final _truckPaymentCtrl = TextEditingController();

  // Trailer
  String _trailerType = 'flatbed';
  final _trailerNumCtrl = TextEditingController();
  String _trailerCostMode = 'owned';
  final _trailerPriceCtrl = TextEditingController(text: '40000');
  final _trailerDeprecCtrl = TextEditingController(text: '20');
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

      // Save truck
      await _supabase.from('units').insert({
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
        'monthly_payment': _truckCostMode == 'financed'
            ? double.tryParse(_truckPaymentCtrl.text)
            : null,
      });

      // Save trailer
      await _supabase.from('units').insert({
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
        'monthly_payment': _trailerCostMode == 'financed'
            ? double.tryParse(_trailerPaymentCtrl.text)
            : null,
      });

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
    _truckPaymentCtrl.dispose();
    _trailerNumCtrl.dispose();
    _trailerPriceCtrl.dispose();
    _trailerDeprecCtrl.dispose();
    _trailerPaymentCtrl.dispose();
    super.dispose();
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
          ] else ...[
            TextField(
              controller: _truckPaymentCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Monthly Payment (\$)',
                  border: OutlineInputBorder()),
            ),
          ],

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
