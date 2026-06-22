import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../help/help_content.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';

/// Capture any load-related document, not just receipts. The driver picks
/// what it is first — Receipt, Rate Confirmation, BOL, POD, Oversize Permit,
/// or Other — then snaps it.
///
///  - RECEIPT runs the scan-and-extract flow (categorize-receipt) and saves
///    to the expenses table.
///  - Everything else just attaches to the load as proof: it saves to
///    trip_documents with an optional reference number + note.
///
/// Storage model (same for every type):
///  - The photo saves to the PHONE at save time — the permanent record. Two
///    places: an organized per-load folder (Documents/TruCost/<load>/...,
///    browsable in the Files app) and a copy in the "TruCost" Photos album
///    (the backstop that survives an app reinstall).
///  - A working copy goes to the Supabase 'receipts' bucket so reports can be
///    built, but the cloud only keeps images for the 3 most recent loads
///    (enforce-doc-retention purges the rest). The numbers/text stay forever.
///
/// Goes in: lib/expenses/receipt_capture_screen.dart

enum DocType { receipt, ratecon, bol, pod, permit, other }

extension DocTypeInfo on DocType {
  String get label {
    switch (this) {
      case DocType.receipt:
        return 'Receipt';
      case DocType.ratecon:
        return 'Rate Confirmation';
      case DocType.bol:
        return 'Bill of Lading';
      case DocType.pod:
        return 'Proof of Delivery';
      case DocType.permit:
        return 'Oversize Permit';
      case DocType.other:
        return 'Other Document';
    }
  }

  String get shortLabel {
    switch (this) {
      case DocType.receipt:
        return 'Receipt';
      case DocType.ratecon:
        return 'Rate Con';
      case DocType.bol:
        return 'BOL';
      case DocType.pod:
        return 'POD';
      case DocType.permit:
        return 'Permit';
      case DocType.other:
        return 'Other';
    }
  }

  String get dbValue {
    switch (this) {
      case DocType.receipt:
        return 'receipt';
      case DocType.ratecon:
        return 'ratecon';
      case DocType.bol:
        return 'bol';
      case DocType.pod:
        return 'pod';
      case DocType.permit:
        return 'permit';
      case DocType.other:
        return 'other';
    }
  }

  String get filePrefix {
    switch (this) {
      case DocType.receipt:
        return 'receipt';
      case DocType.ratecon:
        return 'ratecon';
      case DocType.bol:
        return 'bol';
      case DocType.pod:
        return 'pod';
      case DocType.permit:
        return 'permit';
      case DocType.other:
        return 'doc';
    }
  }

  bool get isReceipt => this == DocType.receipt;

  // BOL / POD / Rate Con / Permit are inherently load documents.
  bool get loadRequired =>
      this == DocType.ratecon ||
      this == DocType.bol ||
      this == DocType.pod ||
      this == DocType.permit;
}

class ReceiptCaptureScreen extends StatefulWidget {
  const ReceiptCaptureScreen({super.key});
  @override
  State<ReceiptCaptureScreen> createState() => _ReceiptCaptureScreenState();
}

class _ReceiptCaptureScreenState extends State<ReceiptCaptureScreen> {
  final _supabase = Supabase.instance.client;

  DocType _docType = DocType.receipt;

  File? _image;
  bool _scanning = false;
  bool _saving = false;
  bool _scanned = false;
  bool _manual = false; // typed-in, no photo
  Map<String, dynamic>? _raw;

  final _vendorCtrl = TextEditingController();
  final _dateCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _taxCtrl = TextEditingController();
  final _paymentCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _refCtrl = TextEditingController(); // reference / PRO number for docs
  final _gallonsCtrl = TextEditingController(); // gallons on fuel receipts
  String? _purchaseState; // US state where fuel was bought (IFTA), from dropdown

  static const List<String> _usStates = [
    'AL','AK','AZ','AR','CA','CO','CT','DE','FL','GA','HI','ID','IL','IN','IA',
    'KS','KY','LA','ME','MD','MA','MI','MN','MS','MO','MT','NE','NV','NH','NJ',
    'NM','NY','NC','ND','OH','OK','OR','PA','RI','SC','SD','TN','TX','UT','VT',
    'VA','WA','WV','WI','WY','DC',
  ];

  List<String> _categories = ['Other'];
  String _category = 'Other';
  bool _reimbursable = true; // default: most receipts bill back; fuel is the exception

  // Carrier fuel card / advance: if this fuel was bought on the carrier's card,
  // the carrier deducts it from the settlement. Default comes from the profile;
  // overridable per fuel receipt (e.g. paid cash for a discount).
  bool _profileCarrierCard = false;
  bool _onCarrierCard = false;

  // Cash advance from the carrier (a lump they front and take back out of the
  // settlement). Entered manually or as a photo of the advance slip. When on,
  // this receipt IS the advance — deducted from the settlement, not a cost.
  bool _isAdvance = false;

  // Booked loads to link this document to.
  List<Map<String, dynamic>> _trips = [];
  String? _tripId;

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _loadTrips();
    _loadCarrierCardDefault();
  }

  Future<void> _loadCarrierCardDefault() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;
      final p = await _supabase
          .from('profiles')
          .select('carrier_fuel_card')
          .eq('user_id', user.id)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        _profileCarrierCard = p?['carrier_fuel_card'] == true;
        _onCarrierCard = _profileCarrierCard;
      });
    } catch (_) {
      // Non-fatal — default stays false.
    }
  }

  Future<void> _loadTrips() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;
      // Only real booked loads belong here, not quotes. A load counts as
      // booked when its stage is won/completed, or its operational status
      // has been flipped to 'booked' (same rule as the Saved Trips
      // "Booked" filter). Newest load on top.
      final rows = await _supabase
          .from('trips')
          .select('id, trip_name, origin, destination, trip_date')
          .eq('user_id', user.id)
          .or('stage.in.(won,completed),status.eq.booked')
          .order('trip_date', ascending: false)
          .limit(40);
      if (mounted) setState(() => _trips = List<Map<String, dynamic>>.from(rows));
    } catch (_) {
      // no loads yet is fine
    }
  }

  String _tripLabel(Map<String, dynamic> t) {
    final name = (t['trip_name'] ?? '').toString().trim();
    if (name.isNotEmpty) return name;
    final o = (t['origin'] ?? '?').toString();
    final d = (t['destination'] ?? '?').toString();
    return '$o \u2192 $d';
  }

  Future<void> _loadCategories() async {
    try {
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

      // Crop before saving/scanning. A tight crop cuts out the background.
      final cropped = await ImageCropper().cropImage(
        sourcePath: picked.path,
        compressFormat: ImageCompressFormat.jpg,
        compressQuality: 90,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop Document',
            toolbarColor: Colors.blueGrey[700],
            toolbarWidgetColor: Colors.white,
            lockAspectRatio: false,
          ),
          IOSUiSettings(
            title: 'Crop Document',
            aspectRatioLockEnabled: false,
          ),
        ],
      );

      final path = cropped?.path ?? picked.path;
      setState(() {
        _image = File(path);
        _scanned = false;
        _raw = null;
      });
    } catch (e) {
      _toast('Could not load photo: $e');
    }
  }

  // ── Scan via the edge function (receipts only) ─────────────
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
    _gallonsCtrl.text = data['gallons'] != null ? data['gallons'].toString() : '';
    final scannedState = (data['state'] ?? '').toString().toUpperCase().trim();
    if (_usStates.contains(scannedState)) _purchaseState = scannedState;
    final cat = (data['category'] ?? 'Other').toString();
    _category = _categories.contains(cat) ? cat : 'Other';
    _reimbursable = !_isFuel; // fuel is the operating-cost exception
    if (_isFuel) _onCarrierCard = _profileCarrierCard;
  }

  // Fuel receipts get a gallons field (for actual MPG + fuel reconciliation).
  bool get _isFuel {
    final c = _category.toLowerCase();
    return c.contains('fuel') || c.contains('diesel');
  }

  // ── Shared: save photo to phone + upload working copy to cloud ──
  String? _resolveLoadName() {
    if (_tripId == null) return null;
    final t = _trips.firstWhere(
      (e) => e['id'].toString() == _tripId,
      orElse: () => <String, dynamic>{},
    );
    return t.isNotEmpty ? _tripLabel(t) : null;
  }

  Future<String?> _uploadToCloud(String userId) async {
    if (_image == null) return null;
    final filename = '$userId/${DateTime.now().millisecondsSinceEpoch}.jpg';
    final bytes = await _image!.readAsBytes();
    await _supabase.storage.from('receipts').uploadBinary(
          filename,
          bytes,
          fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
        );
    return filename;
  }

  /// Saves the photo to the phone — the permanent record. Two places: an
  /// organized per-load folder in the app's Documents directory, and a copy
  /// in the "TruCost" Photos album. Runs before the cloud copy can be purged.
  /// Returns false only if the folder write (the primary copy) fails.
  Future<bool> _saveToPhone(String? loadName) async {
    if (_image == null) return false;
    bool ok = false;

    try {
      final docs = await getApplicationDocumentsDirectory();
      final folder = _safeName(
        (loadName != null && loadName.trim().isNotEmpty) ? loadName : 'General',
      );
      final dir = Directory('${docs.path}/TruCost/$folder');
      await dir.create(recursive: true);
      await _image!.copy('${dir.path}/${_docFileName()}');
      ok = true;
    } catch (e) {
      _toast('Couldn\'t save to your phone: $e');
    }

    try {
      await Gal.putImage(_image!.path, album: 'TruCost');
    } on GalException catch (_) {
      // no Photos permission; folder copy still exists
    } catch (_) {}

    return ok;
  }

  String _safeName(String s) {
    final cleaned = s
        .replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cleaned.isEmpty ? 'Load' : cleaned;
  }

  /// A self-describing filename, e.g. receipt-pilot-2026-06-12-48213.jpg or
  /// pod-2026-06-12-48213.jpg.
  String _docFileName() {
    final date = _dateCtrl.text.trim().isNotEmpty ? _dateCtrl.text.trim() : _todayStr();
    final s = DateTime.now().millisecondsSinceEpoch.toString();
    final suffix = s.substring(s.length - 5);
    if (_docType.isReceipt) {
      final v = _safeName(_vendorCtrl.text.trim()).toLowerCase().replaceAll(' ', '-');
      final vendor = v.isEmpty ? 'receipt' : v;
      return 'receipt-$vendor-$date-$suffix.jpg';
    }
    return '${_docType.filePrefix}-$date-$suffix.jpg';
  }

  String _todayStr() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  // ── Save a RECEIPT (expense) ───────────────────────────────
  Future<void> _save() async {
    final amount = double.tryParse(_amountCtrl.text.trim());
    if (amount == null) {
      _toast(_isAdvance ? 'Enter the advance amount before saving.' : 'Enter a valid amount before saving.');
      return;
    }
    if (_isAdvance && _tripId == null) {
      _toast('Pick the load this advance is against.');
      return;
    }
    setState(() => _saving = true);
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('Not signed in');

      final loadName = _resolveLoadName();
      final phoneSaveOk = _image != null ? await _saveToPhone(loadName) : true;
      final receiptPath = await _uploadToCloud(user.id);

      final dateText = _dateCtrl.text.trim();

      await _supabase.from('expenses').insert({
        'user_id': user.id,
        'category': _isAdvance ? 'Cash Advance' : _category,
        'vendor': _isAdvance
            ? 'Carrier advance'
            : (_vendorCtrl.text.trim().isEmpty ? null : _vendorCtrl.text.trim()),
        'expense_date': dateText.isEmpty ? null : dateText,
        'amount': amount,
        'tax_amount': _isAdvance ? null : double.tryParse(_taxCtrl.text.trim()),
        'payment_method': _isAdvance
            ? null
            : (_paymentCtrl.text.trim().isEmpty ? null : _paymentCtrl.text.trim()),
        'gallons': (_isFuel && !_isAdvance) ? double.tryParse(_gallonsCtrl.text.trim()) : null,
        'purchase_state': (_isFuel && !_isAdvance) ? _purchaseState : null,
        'reimbursable': _isAdvance ? false : _reimbursable,
        'carrier_fuel_card': (_isFuel && !_isAdvance) ? _onCarrierCard : false,
        'is_advance': _isAdvance,
        'receipt_url': receiptPath,
        'trip_id': _tripId,
        'notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        'raw_json': _raw,
        'status': 'confirmed',
      });

      if (receiptPath != null && _tripId != null) {
        try {
          await _supabase.functions.invoke('enforce-doc-retention');
        } catch (_) {}
      }

      _finishSaved(phoneSaveOk, _isAdvance ? 'Saved cash advance' : 'Saved $_category expense');
    } catch (e) {
      _toast('Save failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Save a NON-RECEIPT document (attach to load) ───────────
  Future<void> _saveDocument() async {
    if (_image == null) {
      _toast('Add a photo first.');
      return;
    }
    if (_docType.loadRequired && _tripId == null) {
      _toast('Pick the load this ${_docType.label.toLowerCase()} belongs to.');
      return;
    }
    setState(() => _saving = true);
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('Not signed in');

      final loadName = _resolveLoadName();
      final phoneSaveOk = await _saveToPhone(loadName);
      final path = await _uploadToCloud(user.id);

      await _supabase.from('trip_documents').insert({
        'user_id': user.id,
        'trip_id': _tripId,
        'doc_type': _docType.dbValue,
        'storage_path': path,
        'reference': _refCtrl.text.trim().isEmpty ? null : _refCtrl.text.trim(),
        'notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      });

      if (path != null && _tripId != null) {
        try {
          await _supabase.functions.invoke('enforce-doc-retention');
        } catch (_) {}
      }

      _finishSaved(phoneSaveOk, 'Saved ${_docType.label}');
    } catch (e) {
      _toast('Save failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _finishSaved(bool phoneSaveOk, String okMsg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(phoneSaveOk ? okMsg : 'Saved \u2014 but couldn\'t add the photo to your phone'),
        backgroundColor: phoneSaveOk ? Colors.green[700] : Colors.orange[800],
      ),
    );
    Navigator.pop(context, true);
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
    _refCtrl.dispose();
    _gallonsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Document'), actions: const [HelpButton(HelpScreens.receipts)]),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _typeSelector(),
          const SizedBox(height: 16),
          if (_image == null && !_manual)
            _emptyState()
          else ...[
            if (_image != null) ...[
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
            ] else ...[
              Center(
                child: TextButton.icon(
                  onPressed: _showPhotoOptions,
                  icon: const Icon(Icons.add_a_photo, size: 18),
                  label: const Text('Add a photo (optional)'),
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (_docType.isReceipt) ...[
              if (_image != null && !_scanned && !_manual)
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
              if (_scanned || _manual) _reviewCard(),
            ] else
              _attachCard(),
          ],
        ],
      ),
    );
  }

  Widget _typeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('What are you scanning?',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey[700])),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: DocType.values.map((d) {
            final sel = _docType == d;
            return ChoiceChip(
              label: Text(d.shortLabel),
              selected: sel,
              selectedColor: Colors.blueGrey[700],
              labelStyle: TextStyle(color: sel ? Colors.white : Colors.black87),
              onSelected: (_) => setState(() {
                _docType = d;
                _scanned = false;
              }),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: Column(
        children: [
          Icon(_docType.isReceipt ? Icons.receipt_long : Icons.description,
              size: 72, color: Colors.blueGrey[200]),
          const SizedBox(height: 16),
          Text('Add a photo of your ${_docType.label.toLowerCase()}',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey[600])),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _showPhotoOptions,
            icon: const Icon(Icons.add_a_photo),
            label: const Text('Add Photo'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              backgroundColor: Colors.blueGrey[700],
              foregroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => setState(() {
              _manual = true;
              _docType = DocType.receipt;
              _isAdvance = false;
            }),
            child: const Text('Enter manually (no photo)'),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: Divider(color: Colors.grey[300])),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('or', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
            ),
            Expanded(child: Divider(color: Colors.grey[300])),
          ]),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => setState(() {
              _manual = true;
              _docType = DocType.receipt;
              _isAdvance = true;
            }),
            icon: Icon(Icons.payments_outlined, color: Colors.orange[800]),
            label: Text('Log a cash advance',
                style: TextStyle(color: Colors.orange[800], fontWeight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              side: BorderSide(color: Colors.orange[800]!),
            ),
          ),
          const SizedBox(height: 6),
          Text('Carrier fronted you cash — deducted from your settlement',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: Colors.grey[500])),
        ],
      ),
    );
  }

  // Shared load picker. allowNone shows the "no load" option (receipts/other).
  Widget _loadPicker({required bool allowNone}) {
    return DropdownButtonFormField<String?>(
      value: _tripId,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: allowNone ? 'Link to load (optional)' : 'Which load? (required)',
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      items: [
        if (allowNone)
          const DropdownMenuItem<String?>(
            value: null,
            child: Text('No load \u2014 general expense'),
          ),
        ..._trips.map((t) => DropdownMenuItem<String?>(
              value: t['id'].toString(),
              child: Text(_tripLabel(t), overflow: TextOverflow.ellipsis),
            )),
      ],
      onChanged: (v) => setState(() => _tripId = v),
    );
  }

  Widget _cardShell({required List<Widget> children}) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }

  Widget _storageNote() {
    return Text(
      'Saved to this phone under Files \u2192 TruCost \u2192 this load (and a copy in '
      'your TruCost photo album). The cloud keeps images for your 3 most recent '
      'loads, then clears them \u2014 the numbers are always kept.',
      style: TextStyle(fontSize: 11, color: Colors.grey[500], height: 1.3),
      textAlign: TextAlign.center,
    );
  }

  // Non-receipt documents: attach to a load with optional reference + note.
  Widget _attachCard() {
    return _cardShell(children: [
      Row(
        children: [
          Icon(Icons.attach_file, color: Colors.blueGrey[600], size: 20),
          const SizedBox(width: 8),
          Text('Save ${_docType.label}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
      const SizedBox(height: 16),
      _loadPicker(allowNone: !_docType.loadRequired),
      const SizedBox(height: 12),
      _field(_refCtrl, 'Reference / PRO # (optional)'),
      const SizedBox(height: 12),
      _field(_notesCtrl, 'Note (optional)'),
      const SizedBox(height: 20),
      ElevatedButton.icon(
        onPressed: _saving ? null : _saveDocument,
        icon: _saving
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.save),
        label: Text(_saving ? 'Saving…' : 'Save ${_docType.label}'),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          backgroundColor: Colors.green[700],
          foregroundColor: Colors.white,
        ),
      ),
      const SizedBox(height: 12),
      _storageNote(),
    ]);
  }

  // Receipt review/fix card.
  Widget _reviewCard() {
    return _cardShell(children: [
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
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: const Text('This is a cash advance',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        subtitle: Text(
          _isAdvance
              ? 'The advance amount is deducted from your settlement'
              : 'Turn on if the carrier fronted you cash (deducted from your check)',
          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
        ),
        value: _isAdvance,
        activeColor: Colors.orange[800],
        onChanged: (v) => setState(() => _isAdvance = v),
      ),
      const SizedBox(height: 12),
      if (!_isAdvance) ...[
        DropdownButtonFormField<String>(
          value: _categories.contains(_category) ? _category : 'Other',
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Category',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
          onChanged: (v) => setState(() {
            _category = v ?? 'Other';
            _reimbursable = !_isFuel;
            if (_isFuel) _onCarrierCard = _profileCarrierCard;
          }),
        ),
        const SizedBox(height: 12),
      ],
      _loadPicker(allowNone: !_isAdvance),
      const SizedBox(height: 12),
      if (!_isAdvance) ...[
        _field(_vendorCtrl, 'Vendor'),
        const SizedBox(height: 12),
      ],
      GestureDetector(
        onTap: _pickDate,
        child: AbsorbPointer(
          child: _field(_dateCtrl, 'Date (YYYY-MM-DD)', suffix: const Icon(Icons.calendar_today, size: 18)),
        ),
      ),
      const SizedBox(height: 12),
      if (_isAdvance)
        _field(_amountCtrl, 'Advance amount', prefix: '\$ ', number: true)
      else
        Row(
          children: [
            Expanded(child: _field(_amountCtrl, 'Amount', prefix: '\$ ', number: true)),
            const SizedBox(width: 12),
            Expanded(child: _field(_taxCtrl, 'Tax', prefix: '\$ ', number: true)),
          ],
        ),
      const SizedBox(height: 12),
      if (_isFuel && !_isAdvance) ...[
        Row(
          children: [
            Expanded(flex: 2, child: _field(_gallonsCtrl, 'Gallons', number: true)),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _purchaseState,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'State',
                  hintText: 'Select',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: _usStates
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (v) => setState(() => _purchaseState = v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('On carrier fuel card', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          subtitle: Text(
            _onCarrierCard
                ? 'Deducted from your settlement check'
                : 'You paid — your cost, not on the settlement',
            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
          ),
          value: _onCarrierCard,
          activeColor: Colors.orange[800],
          onChanged: (v) => setState(() => _onCarrierCard = v),
        ),
        const SizedBox(height: 12),
      ],
      if (!_isAdvance) ...[
        _field(_paymentCtrl, 'Payment Method'),
        const SizedBox(height: 12),
      ],
      _field(_notesCtrl, 'Notes'),
      const SizedBox(height: 8),
      if (!_isAdvance)
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Reimbursable', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          subtitle: Text(
            _reimbursable ? 'Adds to your settlement check' : 'Your cost — kept for taxes, not billed back',
            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
          ),
          value: _reimbursable,
          activeColor: Colors.green[700],
          onChanged: (v) => setState(() => _reimbursable = v),
        ),
      const SizedBox(height: 12),
      ElevatedButton.icon(
        onPressed: _saving ? null : _save,
        icon: _saving
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.save),
        label: Text(_saving ? 'Saving…' : (_isAdvance ? 'Save Advance' : 'Save Expense')),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          backgroundColor: _isAdvance ? Colors.orange[800] : Colors.green[700],
          foregroundColor: Colors.white,
        ),
      ),
      const SizedBox(height: 12),
      _storageNote(),
    ]);
  }

  Widget _field(TextEditingController ctrl, String label,
      {String? prefix, Widget? suffix, bool number = false, String? hint}) {
    return TextField(
      controller: ctrl,
      keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
      textCapitalization: number ? TextCapitalization.none : TextCapitalization.words,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixText: prefix,
        suffixIcon: suffix,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }
}
