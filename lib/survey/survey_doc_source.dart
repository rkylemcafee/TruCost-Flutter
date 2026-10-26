// lib/survey/survey_doc_source.dart
//
// Getting a state's route survey into the phone: the PDF they emailed, or the
// paper they handed over.
//
// Three ways in, one thing out. A PDF is kept as it came. Paper — scanned with
// the iPhone's document camera, or one photograph — is turned into a PDF here,
// so the survey's paperwork is always a PDF however it arrived and opens the
// same way on the desk.
//
// Reading the words is done by iOS itself (PDFKit for a PDF, Vision for a
// picture) through the channel in ios/Runner/AppDelegate.swift. Both hand back
// words with their positions so the columns of the routing table survive.

import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

const _channel = MethodChannel('trucost/survey_doc');

enum SurveyDocWay { pdf, scan, photo }

/// One state survey document, ready to store and to read.
class SurveyDocFile {
  SurveyDocFile({required this.bytes, required this.fileName, this.pdfPath, this.imagePaths = const []});
  final Uint8List bytes;
  final String fileName;
  final String mimeType = 'application/pdf';

  /// Set when it arrived as a PDF: read its text layer.
  final String? pdfPath;

  /// Set when it arrived as paper: read the pictures.
  final List<String> imagePaths;

  bool get isPaper => imagePaths.isNotEmpty;

  /// Words with positions, one list per page: {x, y, w, s}, y upward.
  ///
  /// A PDF with no usable text layer — a scan saved as PDF, or Indiana's
  /// Type 3 fonts — comes back nearly empty; the caller's usable-text check
  /// says so in words.
  Future<List<List<Map<String, dynamic>>>> fragments() async {
    final raw = isPaper
        ? await _channel.invokeMethod<List>('ocrFragments', {'paths': imagePaths})
        : await _channel.invokeMethod<List>('pdfFragments', {'path': pdfPath});
    return (raw ?? const [])
        .map((page) => (page as List).map((f) => Map<String, dynamic>.from(f as Map)).toList())
        .toList();
  }
}

/// Ask which way the survey is coming in, then get it.
Future<SurveyDocFile?> pickSurveyDoc(BuildContext context) async {
  final way = await showModalBottomSheet<SurveyDocWay>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text('The state\'s route survey', style: TextStyle(fontWeight: FontWeight.w600)),
        ),
        ListTile(
          leading: const Icon(Icons.picture_as_pdf_outlined),
          title: const Text('PDF from the state'),
          subtitle: const Text('From Files, Mail or iCloud Drive'),
          onTap: () => Navigator.pop(ctx, SurveyDocWay.pdf),
        ),
        ListTile(
          leading: const Icon(Icons.document_scanner_outlined),
          title: const Text('Scan the paper'),
          subtitle: const Text('Every page, squared up and flattened'),
          onTap: () => Navigator.pop(ctx, SurveyDocWay.scan),
        ),
        ListTile(
          leading: const Icon(Icons.photo_camera_outlined),
          title: const Text('Take a picture'),
          subtitle: const Text('One page, or a handwritten survey'),
          onTap: () => Navigator.pop(ctx, SurveyDocWay.photo),
        ),
        const SizedBox(height: 8),
      ]),
    ),
  );
  if (way == null) return null;

  switch (way) {
    case SurveyDocWay.pdf:
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
      );
      final path = files.isEmpty ? null : files.single.path;
      if (path == null) return null;
      return SurveyDocFile(
        bytes: await File(path).readAsBytes(),
        fileName: files.single.name,
        pdfPath: path,
      );
    case SurveyDocWay.scan:
      final List<String> paths;
      try {
        paths = (await _channel.invokeMethod<List>('scanDocument'))?.cast<String>() ?? const [];
      } on PlatformException catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? 'Scanning failed')));
        }
        return null;
      }
      if (paths.isEmpty) return null;
      return _paper(paths, 'scanned');
    case SurveyDocWay.photo:
      final shot = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 90, maxWidth: 3000);
      if (shot == null) return null;
      return _paper([shot.path], 'photo');
  }
}

/// Pages of paper as one PDF, a page per picture, each filling its page.
Future<SurveyDocFile> _paper(List<String> imagePaths, String how) async {
  final doc = pw.Document();
  for (final p in imagePaths) {
    final img = pw.MemoryImage(await File(p).readAsBytes());
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.all(18),
      build: (_) => pw.Center(child: pw.Image(img, fit: pw.BoxFit.contain)),
    ));
  }
  final bytes = await doc.save();
  final stamp = DateTime.now().toIso8601String().substring(0, 16).replaceAll(RegExp(r'[:T]'), '-');
  final name = 'state-route-survey-$how-$stamp.pdf';
  final dir = await getTemporaryDirectory();
  final f = File('${dir.path}/$name');
  await f.writeAsBytes(bytes);
  return SurveyDocFile(bytes: bytes, fileName: name, pdfPath: f.path, imagePaths: imagePaths);
}
