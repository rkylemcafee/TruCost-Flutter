// lib/survey/widgets/static_map.dart
//
// A Static Maps picture in a card, and the full-screen view behind a tap.
//
// The picture is the answer to "what does this corner look like", so a map
// that fails to load says so in words rather than leaving a grey box that
// could be mistaken for a field.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class StaticMap extends StatelessWidget {
  const StaticMap({
    super.key,
    required this.url,
    this.aspect = 640 / 420,
    this.caption,
    this.onTap,
  });

  final String url;
  final double aspect;

  /// Shown under the picture full-screen, and used as the shared file's name.
  final String? caption;

  /// Defaults to opening the picture full-screen.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap ?? () => MapViewer.open(context, url: url, caption: caption ?? 'Map'),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: AspectRatio(
          aspectRatio: aspect,
          child: Image.network(
            url,
            fit: BoxFit.cover,
            loadingBuilder: (_, child, progress) => progress == null
                ? child
                : Container(
                    color: Colors.grey.shade200,
                    alignment: Alignment.center,
                    child: const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
            errorBuilder: (_, _, _) => Container(
              color: Colors.grey.shade200,
              alignment: Alignment.center,
              padding: const EdgeInsets.all(12),
              child: const Text('Map did not load — check the signal and pull to refresh.',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.grey)),
            ),
          ),
        ),
      ),
    );
  }
}

/// One map, full screen, pinch to zoom, with a Share button.
class MapViewer extends StatelessWidget {
  const MapViewer({super.key, required this.url, required this.caption});
  final String url;
  final String caption;

  static Future<void> open(BuildContext context, {required String url, required String caption}) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => MapViewer(url: url, caption: caption)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(caption, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share),
            onPressed: () async {
              final file = await downloadMap(url, caption);
              if (file == null) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('Could not fetch the map to share')));
                }
                return;
              }
              await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], subject: caption));
            },
          ),
        ],
      ),
      body: InteractiveViewer(
        maxScale: 5,
        child: Center(child: Image.network(url, fit: BoxFit.contain)),
      ),
    );
  }
}

/// Fetch a map picture into a temporary file named for what it shows.
Future<File?> downloadMap(String url, String name) async {
  try {
    final r = await http.get(Uri.parse(url));
    if (r.statusCode != 200) return null;
    final dir = await getTemporaryDirectory();
    final safe = name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_');
    final f = File('${dir.path}/$safe.jpg');
    await f.writeAsBytes(r.bodyBytes);
    return f;
  } catch (_) {
    return null;
  }
}
