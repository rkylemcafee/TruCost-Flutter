// lib/survey/turn_map_editor.dart
//
// A live map of one turn, with the trailer drawn on it to scale.
//
// The phone's version of the web's TurnMapEditor. The rectangle is a polygon
// with real corners on the earth, so pinching the map never changes its size
// relative to the road — the size was never in pixels to begin with. Drag the
// yellow handle to move it, turn it with the buttons, frame the view with your
// fingers, and "Save this view" stores exactly what the web stores: the
// trailer as a centre and a bearing, and the framed centre and zoom the report
// prints.
//
// North stays up and the map does not tilt. The report's picture is a
// north-up overhead, and a view that could be rotated would be a view the
// report cannot reproduce.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'map_image.dart';
import 'survey_data.dart';
import 'survey_repository.dart';

class TurnMapEditor extends StatefulWidget {
  const TurnMapEditor({super.key, required this.data, required this.point});
  final SurveyData data;
  final Map<String, dynamic> point;

  @override
  State<TurnMapEditor> createState() => _TurnMapEditorState();
}

class _TurnMapEditorState extends State<TurnMapEditor> {
  final _repo = SurveyRepository();
  GoogleMapController? _map;
  late LatLng _target;
  late double _zoom;
  late LatLng _turn;
  TrailerPlacement? _trailer;
  bool _dirty = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.point;
    final f = SurveyData.frameOf(p);
    _target = LatLng(f[0], f[1]);
    _zoom = SurveyData.zoomOf(p).toDouble();
    _turn = LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble());
    _trailer = TrailerPlacement.fromAnnotations(p['annotations']);
  }

  double get _lenFt => widget.data.deckLengthFt ?? 0;
  double get _widFt => widget.data.deckWidthFt ?? 0;

  /// Which way the road runs at the turn, so a new trailer starts lined up
  /// with it rather than pointing north across a field.
  double _roadBearing(LatLng at) {
    final r = widget.data.route;
    if (r.length < 2) return 0;
    var best = 0;
    var bestD = double.infinity;
    for (var i = 0; i < r.length; i++) {
      final d = haversineMiles([at.latitude, at.longitude], r[i]);
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    final a = r[math.max(0, best - 1)], b = r[math.min(r.length - 1, best + 1)];
    final y = math.sin((b[1] - a[1]) * math.pi / 180) * math.cos(b[0] * math.pi / 180);
    final x = math.cos(a[0] * math.pi / 180) * math.sin(b[0] * math.pi / 180) -
        math.sin(a[0] * math.pi / 180) * math.cos(b[0] * math.pi / 180) * math.cos((b[1] - a[1]) * math.pi / 180);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  void _place() => setState(() {
        _trailer = TrailerPlacement(_target.latitude, _target.longitude, _roadBearing(_target));
        _dirty = true;
      });

  void _turnBy(double deg) {
    final t = _trailer;
    if (t == null) return;
    setState(() {
      _trailer = TrailerPlacement(t.lat, t.lng, (t.deg + deg + 360) % 360);
      _dirty = true;
    });
  }

  void _moveTo(LatLng at) {
    final t = _trailer;
    if (t == null) return;
    setState(() {
      _trailer = TrailerPlacement(at.latitude, at.longitude, t.deg);
      _dirty = true;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final p = widget.point;
    try {
      await _repo.updatePoint(p['id'], {
        'annotations': TrailerPlacement.intoAnnotations(p['annotations'], _trailer),
        'map_center_lat': _target.latitude,
        'map_center_lng': _target.longitude,
        // Whole zoom levels only: the report's Static Maps picture has no
        // in-between, and the database is checked to 14–21.
        'map_zoom': _zoom.round().clamp(minTurnZoom, maxTurnZoom),
        'lat': _turn.latitude,
        'lng': _turn.longitude,
      });
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
  }

  Set<Polyline> get _lines => {
        for (final (i, piece) in widget.data.pieces.indexed)
          Polyline(
            polylineId: PolylineId('route$i'),
            points: [for (final v in piece) LatLng(v[0], v[1])],
            color: const Color(0xFF1A56DB),
            width: 5,
          ),
      };

  Set<Polygon> get _polygons {
    final t = _trailer;
    if (t == null || _lenFt <= 0 || _widFt <= 0) return {};
    return {
      Polygon(
        polygonId: const PolygonId('trailer'),
        points: [for (final c in trailerCorners(t, _lenFt, _widFt)) LatLng(c[0], c[1])],
        strokeColor: const Color(0xFFFACC15),
        strokeWidth: 2,
        fillColor: const Color(0x66FACC15),
      ),
    };
  }

  Set<Marker> get _markers {
    final t = _trailer;
    return {
      Marker(
        markerId: const MarkerId('turn'),
        position: _turn,
        draggable: true,
        infoWindow: InfoWindow(title: 'Turn ${widget.point['seq']}', snippet: 'Drag to where the turn really is'),
        onDragEnd: (at) => setState(() {
          _turn = at;
          _dirty = true;
        }),
      ),
      if (t != null && _lenFt > 0) ...{
        Marker(
          markerId: const MarkerId('handle'),
          position: LatLng(t.lat, t.lng),
          draggable: true,
          anchor: const Offset(0.5, 0.5),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow),
          infoWindow: const InfoWindow(title: 'Trailer', snippet: 'Drag to move it'),
          onDrag: _moveTo,
          onDragEnd: _moveTo,
        ),
      },
    };
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final t = _trailer;
    final acrossFt = (metersPerPixel(_target.latitude, _zoom) * 3.28084 * 390).round();

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Leave without saving?'),
            content: const Text('The trailer and the view you framed will not be kept.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Stay')),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Leave')),
            ],
          ),
        );
        if (leave == true && context.mounted) Navigator.pop(context, false);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('Turn ${widget.point['seq']} — trailer'),
          actions: [
            TextButton(
              onPressed: _saving || d.sealed ? null : _save,
              child: const Text('Save this view'),
            ),
          ],
        ),
        body: Column(children: [
          Expanded(
            child: Stack(children: [
              GoogleMap(
                mapType: MapType.hybrid,
                initialCameraPosition: CameraPosition(target: _target, zoom: _zoom),
                onMapCreated: (c) => _map = c,
                onCameraMove: (pos) {
                  _target = pos.target;
                  if (pos.zoom.round() != _zoom.round()) setState(() {});
                  _zoom = pos.zoom;
                  _dirty = true;
                },
                // Snap to a whole zoom when the fingers come off, so what is
                // on screen is what the report will print.
                onCameraIdle: () {
                  final whole = _zoom.round().clamp(minTurnZoom, maxTurnZoom).toDouble();
                  if ((whole - _zoom).abs() > 0.01) _map?.animateCamera(CameraUpdate.zoomTo(whole));
                  setState(() {});
                },
                minMaxZoomPreference: const MinMaxZoomPreference(14, 21),
                rotateGesturesEnabled: false,
                tiltGesturesEnabled: false,
                polylines: _lines,
                polygons: _polygons,
                markers: _markers,
              ),
              // Where "Put trailer here" will put it.
              const IgnorePointer(child: Center(child: Icon(Icons.add, color: Colors.white70, size: 28))),
              Positioned(
                left: 10,
                top: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
                  child: Text(
                    'Zoom ${_zoom.round()} · about $acrossFt ft across',
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ),
              ),
            ]),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: !d.haveDeck
                  ? const Text(
                      'Enter the deck length and the load width on Load & route to draw the trailer. '
                      'You can still frame the view and move the turn.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    )
                  : Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(
                        'Deck ${ftIn(d.survey['trailer_length_in'] as num?)} × ${ftIn(d.loadWidthIn)}'
                        '${t == null ? '' : '  ·  heading ${t.deg.round()}°'}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      if (t == null)
                        FilledButton.icon(
                          onPressed: d.sealed ? null : _place,
                          icon: const Icon(Icons.local_shipping_outlined),
                          label: const Text('Put trailer at the cross-hair'),
                          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                        )
                      else
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          _turnButton('-15°', -15),
                          _turnButton('-1°', -1),
                          _turnButton('+1°', 1),
                          _turnButton('+15°', 15),
                          IconButton(
                            tooltip: 'Turn it round',
                            onPressed: () => _turnBy(180),
                            icon: const Icon(Icons.swap_vert),
                          ),
                          IconButton(
                            tooltip: 'Move it to the cross-hair',
                            onPressed: () => _moveTo(_target),
                            icon: const Icon(Icons.center_focus_strong_outlined),
                          ),
                          IconButton(
                            tooltip: 'Take it off',
                            onPressed: () => setState(() {
                              _trailer = null;
                              _dirty = true;
                            }),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ]),
                    ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _turnButton(String label, double deg) => OutlinedButton(
        onPressed: () => _turnBy(deg),
        style: OutlinedButton.styleFrom(minimumSize: const Size(52, 40), padding: EdgeInsets.zero),
        child: Text(label, style: const TextStyle(fontSize: 12)),
      );
}
