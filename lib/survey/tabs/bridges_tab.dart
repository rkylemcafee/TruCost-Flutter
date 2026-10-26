// lib/survey/tabs/bridges_tab.dart
//
// Bridges: everything that carries the load, in driving order, with one map
// of the whole route showing where every one of them is.
//
// The map is live — pinch in on a cluster, tap a pin to see which bridge it
// is — and tapping the target on a row takes the map there. One live map is
// fine on a phone; it is sixty of them that are not.

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../survey_data.dart';
import '../widgets/empty_note.dart';
import '../widgets/structure_row.dart';

class BridgesTab extends StatefulWidget {
  const BridgesTab({super.key, required this.data, required this.onChanged});
  final SurveyData data;
  final Future<void> Function() onChanged;

  @override
  State<BridgesTab> createState() => _BridgesTabState();
}

class _BridgesTabState extends State<BridgesTab> with AutomaticKeepAliveClientMixin {
  GoogleMapController? _map;
  bool _showSpotMaps = false;

  @override
  bool get wantKeepAlive => true;

  LatLngBounds? _bounds() {
    final pts = widget.data.route;
    if (pts.isEmpty) return null;
    var s = pts.first[0], n = s, w = pts.first[1], e = w;
    for (final p in pts) {
      if (p[0] < s) s = p[0];
      if (p[0] > n) n = p[0];
      if (p[1] < w) w = p[1];
      if (p[1] > e) e = p[1];
    }
    return LatLngBounds(southwest: LatLng(s, w), northeast: LatLng(n, e));
  }

  void _locate(Map<String, dynamic> s) {
    final at = LatLng((s['lat'] as num).toDouble(), (s['lng'] as num).toDouble());
    _map?.animateCamera(CameraUpdate.newLatLngZoom(at, 17));
    _map?.showMarkerInfoWindow(MarkerId(s['id']));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final d = widget.data;
    final rows = d.crossed;
    if (d.structures.isEmpty) {
      return RefreshIndicator(
        onRefresh: widget.onChanged,
        child: const EmptyNote('The route has not been checked for bridges yet.\n\n'
            'Open this survey on trucost.app and press "Check the route" on the Bridges tab. '
            'What it finds shows up here.'),
      );
    }
    final deckFt = rows.fold<double>(0, (n, s) => n + ((s['length_ft'] as num?)?.toDouble() ?? 0));
    final bounds = _bounds();

    return Column(children: [
      if (bounds != null)
        SizedBox(
          height: 260,
          child: GoogleMap(
            mapType: MapType.hybrid,
            initialCameraPosition: CameraPosition(target: bounds.northeast, zoom: 8),
            onMapCreated: (c) {
              _map = c;
              Future.delayed(const Duration(milliseconds: 300),
                  () => c.animateCamera(CameraUpdate.newLatLngBounds(bounds, 32)));
            },
            rotateGesturesEnabled: false,
            tiltGesturesEnabled: false,
            polylines: {
              for (final (i, piece) in d.pieces.indexed)
                Polyline(
                  polylineId: PolylineId('r$i'),
                  points: [for (final v in piece) LatLng(v[0], v[1])],
                  color: const Color(0xFF1A56DB),
                  width: 4,
                ),
            },
            markers: {
              for (final (i, s) in rows.indexed)
                Marker(
                  markerId: MarkerId(s['id']),
                  position: LatLng((s['lat'] as num).toDouble(), (s['lng'] as num).toDouble()),
                  icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
                  infoWindow: InfoWindow(
                    title: '${i + 1}. ${s['carries'] ?? 'Bridge'}',
                    snippet: [
                      milesLabel(s['miles_along']),
                      if (s['length_ft'] != null) '${(s['length_ft'] as num).round()} ft',
                      if (s['crosses'] != null) 'over ${s['crosses']}',
                    ].where((x) => x.isNotEmpty).join(' · '),
                  ),
                ),
            },
          ),
        ),
      Expanded(
        child: RefreshIndicator(
          onRefresh: widget.onChanged,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 40),
            children: [
              Text(
                '${rows.length} bridge(s) carry this load, in driving order'
                '${deckFt > 0 ? '  ·  ${deckFt.round()} ft of deck' : ''}'
                '${d.loadWeightLbs != null ? '  ·  ${d.loadWeightLbs} lb across each' : ''}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('A close-up map on every bridge', style: TextStyle(fontSize: 13)),
                value: _showSpotMaps,
                onChanged: (v) => setState(() => _showSpotMaps = v),
              ),
              for (final s in rows)
                StructureRow(
                  data: d,
                  s: s,
                  onChanged: widget.onChanged,
                  showMap: _showSpotMaps,
                  onLocate: () => _locate(s),
                ),
              if (d.ignored.any((s) => s['kind'] == 'cross'))
                _Ignored(data: d, kind: 'cross', onChanged: widget.onChanged),
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'From the FHWA National Bridge Inventory. Places to look, never permission: '
                  'the permit office and the inventory do not always agree.',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ),
            ],
          ),
        ),
      ),
    ]);
  }
}

/// What was ruled not an issue, folded away but one tap from coming back.
class _Ignored extends StatelessWidget {
  const _Ignored({required this.data, required this.kind, required this.onChanged});
  final SurveyData data;
  final String kind;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final rows = data.ignored.where((s) => (s['kind'] == 'cross') == (kind == 'cross')).toList();
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text('${rows.length} ruled not an issue', style: const TextStyle(fontSize: 13)),
      children: [
        for (final s in rows) StructureRow(data: data, s: s, onChanged: onChanged, showMap: false),
      ],
    );
  }
}

/// The same fold for the Overpasses tab.
class IgnoredStructures extends StatelessWidget {
  const IgnoredStructures({super.key, required this.data, required this.onChanged});
  final SurveyData data;
  final Future<void> Function() onChanged;
  @override
  Widget build(BuildContext context) => _Ignored(data: data, kind: 'under', onChanged: onChanged);
}
