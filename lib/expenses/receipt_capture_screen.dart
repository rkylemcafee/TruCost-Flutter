import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';

/// Snap or pick a receipt photo → scan it with the categorize-receipt
/// edge function → review/fix the fields → save to the expenses table
/// and upload the image to the receipts bucket.
///
/// Goes in: lib/expenses/receipt_capture_screen.dart

class ReceiptCaptureScreen extends StatefulWidget {
  const ReceiptCaptureScreen({super.key});
  @override
  State<ReceiptCaptureScreen> createState() => _ReceiptCaptureScreenState();
}

class _ReceiptCaptureScreenState extends State<ReceiptCaptureScreen> {
  final _supabase = Supabase.instance.client;

  File? _image;
  bool _scanning = false;
  bool _saving = false;
  bool _scanned = false;
  Map<String, dynamic>? _raw;

  final _vendorCtrl = TextEditingController();
  final _dateCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _taxCtrl = TextEditingController();
  final _paymentCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  List<String> _categories = ['Other'];
  String _category = 'Other';

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      // RLS already limits this to global defaults + the driver's own.
      final rows = await _supabase
          .from('expense_categories')
          .select('name')
          .eq('is_active', true)
          .order('sort_order');
      final names = (rows as List).map((r) => r['name'].toString()).toList();
      if (names.isNotEmpty && mounted) {
        setState(() => _categories = names);
      }
    } catch (_) {
      // keep the fallback list
    }
  }

  // ── Pick / take a photo ────────────────────────────────────
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
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 2200,
        imageQuality: 85,
      );
      if (picked == null) return;
      setState(() {
        _image = File(picked.path);
        _scanned = false;
        _raw = null;
      });
    } catch (e) {
      _toast('Could not load photo: $e');
    }
  }

  // ── Scan via the edge function ─────────────────────────────
  Future<void> _scan() async {
    if (_image == null) return;
    setState(() => _scanning = true);
    try {
      final bytes = await _image!.readAsBytes();
      final b64 = base64Encode(bytes);

      final res = await _supabase.functions.invoke(
        'categorize-receipt',
        body: {'image_base64': b64, 'media_type': 'image/jpeg'},
      );

      final data = res.data;
      if (data is Map && data['error'] == null) {
        _applyParsed(Map<String, dynamic>.from(data));
        setState(() => _scanned = true);
      } else {
        _toast(data is Map ? (data['error'] ?? 'Could not read receipt').toString() : 'Could not read receipt');
      }
    } catch (e) {
      _toast('Scan failed: $e');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  void _applyParsed(Map<String, dynamic> data) {
    _raw = data;
    _vendorCtrl.text = (data['vendor'] ?? '').toString();
    _dateCtrl.text = (data['expense_date'] ?? '').toString();
    _amountCtrl.text = data['amount'] != null ? data['amount'].toString() : '';
    _taxCtrl.text = data['tax_amount'] != null ? data['tax_amount'].toString() : '';
    _paymentCtrl.text = (data['payment_method'] ?? '').toString();
    final cat = (data['category'] ?? 'Other').toString();
    _category = _categories.contains(cat) ? cat : 'Other';
  }

  // ── Save ───────────────────────────────────────────────────
  Future<void> _save() async {
    final amount = double.tryParse(_amountCtrl.text.trim());
    if (amount == null) {
      _toast('Enter a valid amount before saving.');
      return;
    }
    setState(() => _saving = true);
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('Not signed in');

      String? receiptPath;
      if (_image != null) {
        final filename = '${user.id}/${DateTime.now().millisecondsSinceEpoch}.jpg';
        final bytes = await _image!.readAsBytes();
        await _supabase.storage.from('receipts').uploadBinary(
              filename,
              bytes,
              fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
            );
        receiptPath = filename;
      }

      final dateText = _dateCtrl.text.trim();

      await _supabase.from('expenses').insert({
        'user_id': user.id,
        'category': _category,
        'vendor': _vendorCtrl.text.trim().isEmpty ? null : _vendorCtrl.text.trim(),
        'expense_date': dateText.isEmpty ? null : dateText,
        'amount': amount,
        'tax_amount': double.tryParse(_taxCtrl.text.trim()),
        'payment_method': _paymentCtrl.text.trim().isEmpty ? null : _paymentCtrl.text.trim(),
        'receipt_url': receiptPath,
        'notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        'raw_json': _raw,
        'status': 'confirmed',
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved $_category expense'), backgroundColor: Colors.green[700]),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      _toast('Save failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickDate() async {
    DateTime initial = DateTime.now();
    final parsed = DateTime.tryParse(_dateCtrl.text.trim());
    if (parsed != null) initial = parsed;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2015),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) {
      _dateCtrl.text =
          '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    }
  }

  void _toast(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  void dispose() {
    _vendorCtrl.dispose();
    _dateCtrl.dispose();
    _amountCtrl.dispose();
    _taxCtrl.dispose();
    _paymentCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Receipt')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_image == null)
            _emptyState()
          else ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(_image!, height: 220, width: double.infinity, fit: BoxFit.cover),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                onPressed: _showPhotoOptions,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Use a different photo'),
              ),
            ),
            const SizedBox(height: 8),
            if (!_scanned)
              ElevatedButton.icon(
                onPressed: _scanning ? null : _scan,
                icon: _scanning
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.document_scanner),
                label: Text(_scanning ? 'Reading receipt…' : 'Scan Receipt'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.blueGrey[700],
                  foregroundColor: Colors.white,
                ),
              ),
            if (_scanned) _reviewCard(),
          ],
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.only(top: 48),
      child: Column(
        children: [
          Icon(Icons.receipt_long, size: 72, color: Colors.blueGrey[200]),
          const SizedBox(height: 16),
          Text('Snap a receipt and let $_copilotHint read it',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey[600])),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _showPhotoOptions,
            icon: const Icon(Icons.add_a_photo),
            label: const Text('Add Receipt Photo'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              backgroundColor: Colors.blueGrey[700],
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  // The copilot's name isn't loaded here; keep it generic.
  String get _copilotHint => 'TruCost';

  Widget _reviewCard() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green[600], size: 20),
              const SizedBox(width: 8),
              const Text('Review & Fix', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const Spacer(),
              if (_raw?['confidence'] != null)
                Text('confidence: ${_raw!['confidence']}',
                    style: TextStyle(fontSize: 11, color: Colors.grey[500])),
            ],
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _categories.contains(_category) ? _category : 'Other',
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Category',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: _categories
                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                .toList(),
            onChanged: (v) => setState(() => _category = v ?? 'Other'),
          ),
          const SizedBox(height: 12),
          _field(_vendorCtrl, 'Vendor'),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _pickDate,
            child: AbsorbPointer(
              child: _field(_dateCtrl, 'Date (YYYY-MM-DD)', suffix: const Icon(Icons.calendar_today, size: 18)),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _field(_amountCtrl, 'Amount', prefix: '\$ ', number: true)),
              const SizedBox(width: 12),
              Expanded(child: _field(_taxCtrl, 'Tax', prefix: '\$ ', number: true)),
            ],
          ),
          const SizedBox(height: 12),
          _field(_paymentCtrl, 'Payment Method'),
          const SizedBox(height: 12),
          _field(_notesCtrl, 'Notes'),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save),
            label: Text(_saving ? 'Saving…' : 'Save Expense'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: Colors.green[700],
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label,
      {String? prefix, Widget? suffix, bool number = false}) {
    return TextField(
      controller: ctrl,
      keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
      textCapitalization: number ? TextCapitalization.none : TextCapitalization.words,
      decoration: InputDecoration(
        labelText: label,
        prefixText: prefix,
        suffixIcon: suffix,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }
}
