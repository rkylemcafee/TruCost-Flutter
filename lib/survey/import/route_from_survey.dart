// lib/survey/import/route_from_survey.dart
//
// Port of the web app's src/lib/routeFromSurvey.ts.
//
// Turn a state's written routing back into the line they drew.
//
// A route survey is a turn list, and a turn list is geometry in disguise:
//
//     3.20  SR-69 North   Turn right onto SR-62
//     2.70  SR-62 East    Arrive at destination.
//
// Consecutive roads meet at the turn, and in OpenStreetMap they genuinely
// share a node there — measured on 18144, SR-69 and SR-62 meet at exactly
// 0 ft. So every turn is a junction we can find, and the route is the chain
// of them.
//
// The difficulty is that two state roads can meet in more than one place, and
// picking the nearest is how you end up drawing a plausible route through the
// wrong county. The survey settles it: each step carries the distance
// travelled along that road, so the correct junction is the one that far from
// the last one. Mileage chooses the chain and then checks it — INDOT prints a
// running total, and a reconstruction that does not land on it is wrong in a
// way we can see rather than one we cannot.
//
// A note on the port. The web's searches pick the next node with
// `queue.sort(...)` then `shift()`; JavaScript's sort is stable, so among
// equal distances the earliest queued wins. Ties are common on a road graph
// (two ways meeting a junction at the same distance), and which one wins
// decides which node a chain lands on. The heap below orders by (distance,
// order queued) to make exactly the same choices. Likewise every Map and Set
// here is Dart's default linked one, which iterates in insertion order as
// JavaScript's do — several "first one wins" ties depend on that order.

import 'dart:math' as math;

/// [lat, lng].
typedef LL = List<double>;

class RouteStepGeom {
  /// The road travelled for this step, as the survey writes it.
  final String road;

  /// Miles INDOT says this step is.
  final double statedMiles;

  /// Miles the reconstruction actually measured.
  final double actualMiles;

  /// The run of road for this step, origin end first.
  final List<LL> shape;

  /// Where this step ends — the turn onto the next road, or the destination.
  ///
  /// This is what a survey point is made from. The structure check works out
  /// which road the load is on from the turn instructions, so without these it
  /// cannot tell "you drive across this bridge" from "this bridge is near the
  /// road you are on": Mulberry Street over the CSX sat 44 ft from SR-62
  /// through Mount Vernon and was reported as crossed.
  final LL? endsAt;

  /// True when no junction sat where the survey said it would, and the nearest
  /// one was taken instead.
  ///
  /// Worth surfacing rather than smoothing over: the step where our reading of
  /// the road and theirs disagree is exactly the place to look. On 18144 the
  /// SR-58 run measures 10.97 miles and INDOT states 9.40.
  final bool disputed;

  const RouteStepGeom({
    required this.road,
    required this.statedMiles,
    required this.actualMiles,
    required this.shape,
    required this.endsAt,
    required this.disputed,
  });
}

class TripGeom {
  final List<LL> shape;
  final List<RouteStepGeom> steps;

  /// Total miles measured, against what the survey states.
  final double miles;
  final double statedMiles;

  /// Why it could not be drawn, when shape is empty.
  final String why;

  /// True when this could only be drawn by going against a one-way road.
  ///
  /// Never a route somebody should drive. It means the survey's own words and
  /// the map disagree here, and the line is shown so a human can see where.
  final bool wrongWay;

  const TripGeom({
    required this.shape,
    required this.steps,
    required this.miles,
    required this.statedMiles,
    required this.why,
    this.wrongWay = false,
  });

  /// Nothing drawn, and why.
  factory TripGeom.none(double statedMiles, String why) =>
      TripGeom(shape: const [], steps: const [], miles: 0, statedMiles: statedMiles, why: why);

  TripGeom withWrongWay() => TripGeom(
        shape: shape,
        steps: steps,
        miles: miles,
        statedMiles: statedMiles,
        why: why,
        wrongWay: true,
      );
}

const double _earthMi = 3958.8;

/// How far apart two roads may be and still count as connected.
///
/// The length of a ramp. An interchange joins two roads without their geometry
/// touching, and the survey's own words for it — "Merge onto US-41 Ramp" —
/// describe exactly this gap.
const double _rampMiles = 0.35;

/// How far a ramp may run between the two roads it joins.
///
/// A cloverleaf loop is a few hundred yards; a long directional flyover can be
/// most of a mile. Beyond this it is not a ramp between these two roads, it is
/// a road of its own going somewhere else.
const double _rampWalkMiles = 1.5;

double miles(LL a, LL b) {
  final dLat = ((b[0] - a[0]) * math.pi) / 180;
  final dLng = ((b[1] - a[1]) * math.pi) / 180;
  final la = (a[0] * math.pi) / 180, lb = (b[0] * math.pi) / 180;
  final sLat = math.sin(dLat / 2), sLng = math.sin(dLng / 2);
  final h = sLat * sLat + math.cos(la) * math.cos(lb) * (sLng * sLng);
  return 2 * _earthMi * math.asin(math.min(1, math.sqrt(h)));
}

/// Which way traffic runs along a piece of road: 1 with the points as listed,
/// -1 against them, 0 either.
typedef Dir = int;

/// A piece of road: one OSM way, carrying one route number.
class Way {
  final String ref;
  final List<LL> geom;
  final Dir dir;
  const Way({required this.ref, required this.geom, this.dir = 0});
}

/// The name a road's ramps are filed under.
///
/// Ramps carry no route number of their own, so they have to be filed against
/// the roads they touch — but filed AS those roads they are indistinguishable
/// from them, and a walk along I-70 can step onto a ramp, off it onto US 40,
/// and still believe it is on I-70. Giving them their own name keeps them in
/// the graph, where they are needed to get across an interchange, and out of
/// the road, where they do not belong.
String rampRef(String ref) => '$ref →';

/// Is this a ramp's name rather than a road's?
bool isRampRef(String ref) => ref.endsWith(' →');

class _Edge {
  final int to;
  final double w;
  final String ref;

  /// What traffic may do along this edge: 0 both ways, 1 only from this node
  /// to the neighbour, -1 only from the neighbour to this node.
  final int rule;
  const _Edge(this.to, this.w, this.ref, this.rule);
}

/// A min-queue of (distance, node) that, among equal distances, gives back the
/// one queued first — what the web's stable sort-then-shift does.
class _Queue {
  final _heap = <(double, int, int)>[]; // (distance, order queued, node)
  int _seq = 0;

  bool get isNotEmpty => _heap.isNotEmpty;

  static bool _less((double, int, int) a, (double, int, int) b) =>
      a.$1 < b.$1 || (a.$1 == b.$1 && a.$2 < b.$2);

  void push(double d, int n) {
    _heap.add((d, _seq++, n));
    var i = _heap.length - 1;
    while (i > 0) {
      final p = (i - 1) >> 1;
      if (!_less(_heap[i], _heap[p])) break;
      final t = _heap[i];
      _heap[i] = _heap[p];
      _heap[p] = t;
      i = p;
    }
  }

  (double, int) pop() {
    final top = _heap.first;
    final last = _heap.removeLast();
    if (_heap.isNotEmpty) {
      _heap[0] = last;
      var i = 0;
      while (true) {
        final l = 2 * i + 1, r = l + 1;
        var m = i;
        if (l < _heap.length && _less(_heap[l], _heap[m])) m = l;
        if (r < _heap.length && _less(_heap[r], _heap[m])) m = r;
        if (m == i) break;
        final t = _heap[i];
        _heap[i] = _heap[m];
        _heap[m] = t;
        i = m;
      }
    }
    return (top.$1, top.$3);
  }
}

/// The roads a survey uses, as a graph that can be walked and measured.
///
/// Built per survey from the handful of route numbers it names, so it stays
/// small: 18144 touches eleven roads out of Indiana's five hundred.
class RoadNet {
  /// key -> index, where key is a vertex rounded to about a foot.
  final _id = <String, int>{};
  final _pt = <LL>[];

  /// node -> edges.
  ///
  /// Each edge's rule says what traffic may do along it. Reading it backwards
  /// — which is how the origin of a trip is found, by walking back from the
  /// first turn — flips its sign.
  final _adj = <List<_Edge>>[];

  /// Walk the wrong way up a one-way road.
  ///
  /// Off, because driving the wrong way is not a route. Turned on only as a
  /// last resort by drawTrip, when obeying the arrows leaves a trip undrawn —
  /// a line drawn against traffic and labelled as such beats no line at all,
  /// because it shows the operator exactly where the map and the survey
  /// disagree.
  bool allowWrongWay = false;

  /// ref -> the nodes that carry it
  final _onRef = <String, Set<int>>{};

  String _key(LL p) => '${p[0].toStringAsFixed(5)},${p[1].toStringAsFixed(5)}';

  int _node(LL p) {
    final k = _key(p);
    var i = _id[k];
    if (i == null) {
      i = _pt.length;
      _id[k] = i;
      _pt.add(p);
      _adj.add([]);
    }
    return i;
  }

  void add(Way way) {
    final set = _onRef.putIfAbsent(way.ref, () => <int>{});
    for (var i = 0; i < way.geom.length; i++) {
      final n = _node(way.geom[i]);
      set.add(n);
      if (i > 0) {
        final m = _node(way.geom[i - 1]);
        final d = miles(way.geom[i - 1], way.geom[i]);
        // Both edges exist either way; the flag says which of them is against
        // traffic, and the searches skip those.
        //
        // This used to be symmetric, on the reasoning that a survey can travel
        // a road in either direction and one-way rules were the router's
        // business. A divided highway broke that: OpenStreetMap holds each
        // carriageway as its own way, so with no direction to tell them apart
        // the shortest path is as likely to be the oncoming lanes as the
        // right ones. Split Trip 2 of survey 18179 drew 6.8 miles of a 185 ft
        // load up the southbound side of US 41 and SR 63 through Terre Haute.
        final dir = way.dir;
        _adj[m].add(_Edge(n, d, way.ref, dir));
        _adj[n].add(_Edge(m, d, way.ref, -dir));
      }
    }
  }

  LL point(int n) => _pt[n];
  List<int> nodesOn(String ref) => [...(_onRef[ref] ?? const <int>{})];

  /// Where two route numbers meet — the places you could turn from one to the
  /// other — as a pair of nodes, one on each road.
  ///
  /// Usually the same node: at an ordinary crossroads OpenStreetMap shares the
  /// vertex, and SR-69 and SR-62 meet at exactly 0 ft. But an interchange is
  /// grade separated, so SR-64 passes over US-41 at Princeton and they share
  /// nothing at all — the connection is a ramp, which the survey names in its
  /// own words ("Merge onto US-41 Ramp"). Requiring a shared vertex therefore
  /// reported that two roads crossing in plain sight "do not meet anywhere".
  ///
  /// So a pair within RAMP_MILES counts, and the hop between them is the ramp
  /// we are not drawing. It is a few hundred yards on a route of hundreds of
  /// miles, and the alternative is refusing to draw the trip at all.
  ///
  /// Two roads that run concurrently share every vertex for the length of the
  /// overlap — SR-64 and SR-65 do it for six miles — and sampling that gave 56
  /// "junctions" along one piece of road. What matters is where an overlap
  /// begins and ends, because that is where a turn happens, so shared runs are
  /// collapsed to their two far ends.
  List<(int, int)> junctions(String a, String b) {
    final aSet = _onRef[a], bSet = _onRef[b];
    if (aSet == null || bSet == null) return [];

    final shared = <int>{for (final n in aSet) if (bSet.contains(n)) n};
    final out = <(int, int)>[];

    final seen = <int>{};
    for (final start in shared) {
      if (seen.contains(start)) continue;
      final run = <int>[];
      final stack = [start];
      seen.add(start);
      while (stack.isNotEmpty) {
        final n = stack.removeLast();
        run.add(n);
        for (final e in _adj[n]) {
          final m = e.to;
          if (shared.contains(m) && !seen.contains(m)) {
            seen.add(m);
            stack.add(m);
          }
        }
      }
      if (run.length == 1) {
        out.add((run[0], run[0]));
        continue;
      }
      var p = run[0], q = run[0];
      var far = -1.0;
      for (final x in run) {
        for (final y in run) {
          final d = miles(_pt[x], _pt[y]);
          if (d > far) {
            far = d;
            p = x;
            q = y;
          }
        }
      }
      out.add((p, p));
      if (p != q) out.add((q, q));
    }
    if (out.isNotEmpty) return out;

    // Nothing shared: the connection is a ramp, so walk the ramps.
    //
    // Better than the straight-line hop below, because it is the real thing:
    // SR-64 and US-41 share no vertex at Princeton, but a ramp leaves one and
    // arrives at the other, and following it says exactly where the turn is.
    final viaRamp = _rampHop(aSet, bSet, _rampWalkMiles);
    if (viaRamp.isNotEmpty) return viaRamp;

    // Nothing shared and no ramp either: fall back to a ramp-length hop.
    final near = <(int, int)>[];
    for (final n in aSet) {
      for (final m in bSet) {
        if (miles(_pt[n], _pt[m]) > _rampMiles) continue;
        if (near.any((x) => miles(_pt[x.$1], _pt[n]) < 0.5)) continue;
        near.add((n, m));
      }
    }
    return near;
  }

  /// Where a ramp leaves one road and arrives at another.
  ///
  /// One search from every node of A at once, over ramp edges only, so the
  /// cost is the size of the ramp network rather than the size of A. A ramp
  /// belongs to both roads it touches, which is why travelling it reaches B
  /// without ever being part of either road.
  List<(int, int)> _rampHop(Set<int> aSet, Set<int> bSet, double cap) {
    final dist = <int, double>{};
    final src = <int, int>{};
    final queue = _Queue();
    for (final n in aSet) {
      dist[n] = 0;
      src[n] = n;
      queue.push(0, n);
    }

    final found = <(int, int)>[];
    while (queue.isNotEmpty) {
      final (d, n) = queue.pop();
      if (d > (dist[n] ?? double.infinity)) continue;
      if (bSet.contains(n) && !aSet.contains(n)) {
        found.add((src[n]!, n));
        continue;
      }
      for (final e in _adj[n]) {
        if (e.rule == -1 && !allowWrongWay) continue;
        if (!isRampRef(e.ref)) continue;
        final nd = d + e.w;
        if (nd > cap || nd >= (dist[e.to] ?? double.infinity)) continue;
        dist[e.to] = nd;
        src[e.to] = src[n]!;
        queue.push(nd, e.to);
      }
    }

    // One interchange produces many ramp ends; they are one turn.
    final out = <(int, int)>[];
    for (final pair in found) {
      if (out.any((x) => miles(_pt[x.$1], _pt[pair.$1]) < 0.5)) continue;
      out.add(pair);
    }
    return out;
  }

  /// Does this search follow an edge carrying `r`? `ref` is one road name,
  /// "*" for any road at all, or an Iterable of names.
  static bool Function(String r) _refFilter(Object ref) {
    // "*" is any road at all. Used for the short walk that carries a leg on to
    // a point somebody placed: what matters over a few hundred yards is that
    // there is pavement, not what it is called.
    if (ref == '*') return (_) => true;
    if (ref is Iterable<String>) {
      final want = ref.toSet();
      return want.contains;
    }
    return (r) => r == ref;
  }

  /// Shortest distance from `start` to each node, travelling only on `ref`.
  ///
  /// Dijkstra, restricted to one road. Branches, loops and the gaps where a
  /// route is split across several ways all come out right without having to
  /// stitch anything together first.
  ///
  /// `ref` is a road name, "*" for any road, or a list of road names.
  Map<int, double> along(int start, Object ref, double capMiles) {
    final follows = _refFilter(ref);
    final dist = <int, double>{start: 0};
    final queue = _Queue()..push(0, start);
    while (queue.isNotEmpty) {
      final (d, n) = queue.pop();
      if (d > (dist[n] ?? double.infinity)) continue;
      if (d > capMiles) continue;
      for (final e in _adj[n]) {
        if (!follows(e.ref) || (e.rule == -1 && !allowWrongWay)) continue;
        final nd = d + e.w;
        if (nd < (dist[e.to] ?? double.infinity)) {
          dist[e.to] = nd;
          queue.push(nd, e.to);
        }
      }
    }
    return dist;
  }

  /// Shortest distance TO `target` from each node, travelling only on `ref`.
  ///
  /// `along` run backwards. The difference only appears once one-way roads are
  /// obeyed, and then it matters: a trip's origin is not given as a place, it
  /// is found by going back along the first road from the first turn. Searched
  /// forwards from that turn on a northbound carriageway you walk further
  /// north, away from the origin, and the only way back is round the houses —
  /// Split Trip 2 of 18179 came out 124.70 miles against a stated 6.80.
  Map<int, double> toward(int target, String ref, double capMiles) {
    final dist = <int, double>{target: 0};
    final queue = _Queue()..push(0, target);
    while (queue.isNotEmpty) {
      final (d, n) = queue.pop();
      if (d > (dist[n] ?? double.infinity)) continue;
      if (d > capMiles) continue;
      for (final e in _adj[n]) {
        // Walking the edge the other way about, so its rule flips: the one
        // that may only be driven towards this node is the one to follow.
        if (e.ref != ref || (e.rule == 1 && !allowWrongWay)) continue;
        final nd = d + e.w;
        if (nd < (dist[e.to] ?? double.infinity)) {
          dist[e.to] = nd;
          queue.push(nd, e.to);
        }
      }
    }
    return dist;
  }

  /// The nodes of the shortest run along `ref` between two points.
  List<LL> path(int from, int to, Object ref) {
    final follows = _refFilter(ref);
    final prev = <int, int>{};
    final dist = <int, double>{from: 0};
    final queue = _Queue()..push(0, from);
    while (queue.isNotEmpty) {
      final (d, n) = queue.pop();
      if (n == to) break;
      if (d > (dist[n] ?? double.infinity)) continue;
      for (final e in _adj[n]) {
        if (!follows(e.ref) || (e.rule == -1 && !allowWrongWay)) continue;
        final nd = d + e.w;
        if (nd < (dist[e.to] ?? double.infinity)) {
          dist[e.to] = nd;
          prev[e.to] = n;
          queue.push(nd, e.to);
        }
      }
    }
    if (!dist.containsKey(to)) return [];
    final out = <LL>[];
    for (int? n = to; n != null; n = prev[n]) {
      out.add(_pt[n]);
    }
    return out.reversed.toList();
  }
}

/// How far off a step's stated mileage a junction may be and still be the one.
const double _stepToleranceMi = 1.2;

/// How many partial chains to carry forward.
const int _beam = 6;

/// Added to a chain's error when a step runs against the direction the survey
/// names.
///
/// A penalty rather than a veto, because a road winds: thirty miles of "SR-46
/// North" can finish slightly south of where it started and still be the
/// right road. Large enough that a candidate going the correct way always wins
/// when both fit the mileage.
const double _wrongWayPenalty = 50;

/// Does going from a to b agree with a named direction? Blank means no opinion.
bool _agrees(String dir, LL a, LL b) {
  final d = dir.trim().toLowerCase();
  if (d.isEmpty) return true;
  if (d.startsWith('n')) return b[0] >= a[0];
  if (d.startsWith('s')) return b[0] <= a[0];
  if (d.startsWith('e')) return b[1] >= a[1];
  if (d.startsWith('w')) return b[1] <= a[1];
  return true;
}

/// A turn: the node you leave the old road at, and the one you join the new
/// road at.
typedef _Turn = (int, int);

class _Chain {
  final List<_Turn> turns;
  final double error;
  final List<int> disputed;
  const _Chain(this.turns, this.error, this.disputed);
}

/// Follow a trip's turn list and return the line it describes.
///
/// `roads` is the road travelled on each step and `dist` the miles INDOT gives
/// for it, so turn i is where roads[i] meets roads[i+1], and the run from the
/// previous turn to it should measure dist[i].
///
/// Searched as a beam rather than greedily. The nearest junction is often the
/// right one and sometimes badly wrong — a route number can cross another
/// twice, thirty miles apart — and a greedy choice at the first turn cannot be
/// taken back once it has ruined everything after it. Six chains is enough to
/// let the mileage settle it a step or two later.
///
/// `dirs` is the direction named on each step — "North", "East" — which the
/// survey gives and the mileage cannot replace. A road runs both ways from a
/// junction, so 32.80 miles along SR-46 fits Terre Haute and Bloomington
/// equally well; without this, Split Trip 2 of 18144 ended 60 miles from its
/// stated destination with a total that matched to two decimal places.
/// Mileage alone cannot tell a route from its reflection.
TripGeom tripGeometry(
  RoadNet net,
  List<String> roads,
  List<double> dist,
  double statedTotal, [
  List<String> dirs = const [],
]) {
  TripGeom none(String why) => TripGeom.none(statedTotal, why);

  // "Continue straight on US-41" is not a turn. The survey breaks a run of one
  // road into several steps whenever something happens on it — a ramp merge,
  // a roundabout, a county line — and each row names the same road again:
  //
  //     0.40  US-41 Ramp East   Continue straight on US-41
  //     0.30  US-41 South       Arrive at destination.
  //
  // Taken literally that asks where US-41 meets US-41. Merged, it is simply
  // 0.70 miles of US-41.
  final merged = <String>[];
  final dists = <double>[];
  final dirn = <String>[];
  for (var i = 0; i < roads.length; i++) {
    if (merged.isNotEmpty && merged.last == roads[i]) {
      dists[dists.length - 1] += dist[i];
    } else {
      merged.add(roads[i]);
      dists.add(dist[i]);
      dirn.add(i < dirs.length ? dirs[i] : '');
    }
  }
  roads = merged;
  dist = dists;

  if (roads.isEmpty) return none('the trip lists no roads');
  if (roads.length == 1) return none('only one road (${roads[0]}) — nothing to turn at');
  for (final r in roads) {
    if (net.nodesOn(r).isEmpty) return none('$r is not in the map data');
  }

  var chains = [
    for (final t in net.junctions(roads[0], roads[1])) _Chain([t], 0, const []),
  ];
  if (chains.isEmpty) return none('${roads[0]} and ${roads[1]} do not meet anywhere');

  for (var i = 1; i < roads.length - 1; i++) {
    final next = <_Chain>[];
    final want = dist[i];
    for (final c in chains) {
      // Travel begins where the last turn put us ON this road.
      final from = c.turns.last.$2;
      final reach = net.along(from, roads[i], want + _stepToleranceMi + 2);
      for (final t in net.junctions(roads[i], roads[i + 1])) {
        final d = reach[t.$1];
        if (d == null) continue;
        final err = (d - want).abs();
        if (err > _stepToleranceMi) continue;
        final wrongWay = !_agrees(dirn[i], net.point(from), net.point(t.$1));
        next.add(_Chain(
          [...c.turns, t],
          c.error + err + (wrongWay ? _wrongWayPenalty : 0),
          c.disputed,
        ));
      }
    }
    if (next.isEmpty) {
      // Nothing within tolerance. Rather than abandon a 155-mile trip because
      // one step is a mile and a half out, take the nearest junction there is
      // and mark the step as disputed — the mileage has done its job by
      // telling us where to look.
      for (final c in chains) {
        final from = c.turns.last.$2;
        final reach = net.along(from, roads[i], want * 2 + 10);
        _Turn? pick;
        var err = double.infinity;
        for (final t in net.junctions(roads[i], roads[i + 1])) {
          final d = reach[t.$1];
          if (d == null) continue;
          if ((d - want).abs() < err) {
            err = (d - want).abs();
            pick = t;
          }
        }
        if (pick != null) next.add(_Chain([...c.turns, pick], c.error + err, [...c.disputed, i]));
      }
      if (next.isEmpty) {
        return none('${roads[i]} and ${roads[i + 1]} do not meet anywhere reachable along ${roads[i]}');
      }
    }
    chains = _stableSorted(next, (a, b) => a.error.compareTo(b.error)).take(_beam).toList();
  }

  final steps = <RouteStepGeom>[];
  final shape = <LL>[];

  // The origin is not given as a place, and does not need to be: it is the
  // first step's distance back along the first road from the first turn.
  //
  // Back along it in the RIGHT DIRECTION. A road runs both ways from a
  // junction, so 3.20 miles of SR-69 fits a point north of the turn exactly
  // as well as one south of it, and the mileage check cannot tell them apart
  // — the same reflection that put Split Trip 2 sixty miles from its
  // destination. Every other step already weighs the survey's direction word;
  // this one did not, and 18144 opened 4.74 miles from where the load
  // actually starts with both of its step mileages correct to the inch.
  //
  // The step says which way you TRAVEL, so the origin is the node you travel
  // FROM: the test is origin -> first turn, not the other way about.
  //
  // Which also settles the first TURN, and has to. The beam scores each turn
  // by the step that leads to it, so the first one — with no earlier turn to
  // measure from — was never scored at all: chains[0], whichever junction the
  // map happened to list first. That was harmless while a road could be
  // walked both ways, and stopped being harmless the moment one-way roads
  // were obeyed. An interchange offers several junction nodes and only one of
  // them can be arrived at going north; picking a southbound one left Split
  // Trip 2 of 18179 with nowhere to come from and a one-point line.
  final last = roads.length - 1;
  var best = chains[0];
  var from = best.turns[0].$1;
  var bestErr = double.infinity;
  for (final c in chains) {
    final turn = c.turns[0].$1;
    // The first step, measured backwards from the first turn.
    var origin = turn;
    var oErr = double.infinity;
    for (final MapEntry(key: n, value: d)
        in net.toward(turn, roads[0], dist[0] + _stepToleranceMi + 2).entries) {
      final e = (d - dist[0]).abs() +
          (_agrees(dirn[0], net.point(n), net.point(turn)) ? 0 : _wrongWayPenalty);
      if (e < oErr) {
        oErr = e;
        origin = n;
      }
    }
    // And the last, forwards from the last turn to the destination. Both ends
    // of a two-road trip were unscored before this, so the choice between the
    // junctions an overlap offers came down to which the map listed first:
    // SR-69 and SR-62 run concurrently for two miles through Mount Vernon,
    // either end fits "3.20 miles of SR-69", and only one of them leaves 2.70
    // miles of SR-62 ending where the survey says.
    final finish = _runTo(net, c.turns.last.$2, roads[last], dist[last], dirn[last]);
    final e = c.error + oErr + finish.err;
    if (e < bestErr) {
      bestErr = e;
      best = c;
      from = origin;
    }
  }

  for (var i = 0; i < roads.length; i++) {
    final turn = i < best.turns.length ? best.turns[i] : null;
    int end;
    if (turn != null) {
      end = turn.$1;
    } else {
      // The last step ends at the destination, dist[i] further along.
      end = _runTo(net, from, roads[i], dist[i], dirn[i]).node;
    }
    final run = net.path(from, end, roads[i]);
    steps.add(RouteStepGeom(
      road: roads[i],
      statedMiles: dist[i],
      actualMiles: _runMiles(run),
      shape: run,
      disputed: best.disputed.contains(i),
      endsAt: run.isNotEmpty ? run.last : null,
    ));
    shape.addAll(shape.isNotEmpty ? run.skip(1) : run);
    if (turn == null) break;
    // Step onto the next road. Where that is a ramp the two nodes differ, and
    // the straight line between them stands in for a ramp we do not draw.
    from = turn.$2;
    if (turn.$1 != turn.$2) shape.add(net.point(turn.$2));
  }

  return TripGeom(
    shape: shape,
    steps: steps,
    miles: steps.fold<double>(0, (t, s) => t + s.actualMiles),
    statedMiles: statedTotal,
    why: '',
  );
}

/// Travel `want` miles along `ref` from `from`, in the direction named, and
/// say where you end up and how far out the mileage was.
///
/// The last step of a trip ends at a destination rather than a turn, so there
/// is nothing to aim at but the mileage — and the same measurement decides
/// which turn the trip should have used, so it is here rather than inline.
({int node, double err}) _runTo(RoadNet net, int from, String ref, double want, String dir) {
  var node = from;
  var err = double.infinity;
  for (final MapEntry(key: n, value: d)
      in net.along(from, ref, want + _stepToleranceMi + 2).entries) {
    final e = (d - want).abs() +
        (_agrees(dir, net.point(from), net.point(n)) ? 0 : _wrongWayPenalty);
    if (e < err) {
      err = e;
      node = n;
    }
  }
  return (node: node, err: err);
}

double _runMiles(List<LL> run) {
  var t = 0.0;
  for (var i = 1; i < run.length; i++) {
    t += miles(run[i - 1], run[i]);
  }
  return t;
}

/// A trip that is one run of one road, with no turn in it.
///
/// Splits 4 and 5 of route survey 18144 are each 0.80 miles of I-70 at Terre
/// Haute, one east and one west — a turnaround, or a staging move. There is no
/// junction to find, so there is nothing for the mileage to anchor to, and the
/// origin is given as a place rather than a position: "I-70, TERRE HAUTE".
///
/// So it is anchored to `hint` — in practice where the previous trip ended —
/// and run out in the direction the survey names. That is a guess about WHERE
/// on the road, and an honest one: the survey does not say, and the
/// alternative is not drawing it at all. The length and the direction are
/// exact.
TripGeom singleRoadTrip(
  RoadNet net,
  String road,
  String direction,
  double wantMiles,
  LL? hint,
) {
  TripGeom none(String why) => TripGeom.none(wantMiles, why);

  final nodes = net.nodesOn(road);
  if (nodes.isEmpty) return none('$road is not in the map data');
  if (hint == null) return none('$road has no turn and nothing to anchor it to');

  var start = nodes[0];
  var near = double.infinity;
  for (final n in nodes) {
    final d = miles(net.point(n), hint);
    if (d < near) {
      near = d;
      start = n;
    }
  }

  final reach = net.along(start, road, wantMiles + 2);
  final want = direction.toLowerCase();
  final from = net.point(start);

  var end = start;
  var best = double.infinity;
  for (final MapEntry(key: n, value: d) in reach.entries) {
    if ((d - wantMiles).abs() > 0.5) continue;
    final p = net.point(n);
    // The direction named has to be the way this run actually goes.
    final goes = want.startsWith('e')
        ? p[1] > from[1]
        : want.startsWith('w')
            ? p[1] < from[1]
            : want.startsWith('n')
                ? p[0] > from[0]
                : want.startsWith('s')
                    ? p[0] < from[0]
                    : true;
    if (!goes) continue;
    final e = (d - wantMiles).abs();
    if (e < best) {
      best = e;
      end = n;
    }
  }
  if (end == start) {
    return none('no run of ${wantMiles.toStringAsFixed(2)} mi $direction along $road near the anchor');
  }

  final run = net.path(start, end, road);
  return TripGeom(
    shape: run,
    steps: [
      RouteStepGeom(
        road: road,
        statedMiles: wantMiles,
        actualMiles: _runMiles(run),
        shape: run,
        disputed: false,
        endsAt: run.isNotEmpty ? run.last : null,
      ),
    ],
    miles: _runMiles(run),
    statedMiles: wantMiles,
    why: '',
  );
}

/// Draw one trip of a survey — the only way the rest of the program should.
///
/// Four places had grown the same two lines: a trip that never leaves one road
/// has no turn to find and is anchored to where the last one ended, everything
/// else is a turn list. They are here now, with the one-way fallback, so the
/// import screen, the survey page, the re-draw and the terminal tool cannot
/// drift apart.
///
/// One-way roads are obeyed first. If that leaves the trip undrawn, it is
/// drawn again with them off and flagged — see RoadNet.allowWrongWay.
TripGeom drawTrip(
  RoadNet net,
  List<String> roads,
  List<double> dists,
  List<String> dirs,
  double statedMiles,
  LL? anchor,
) {
  TripGeom draw() => roads.toSet().length == 1
      ? singleRoadTrip(net, roads[0], dirs.isNotEmpty ? dirs[0] : '', statedMiles, anchor)
      : tripGeometry(net, roads, dists, statedMiles, dirs);

  final obeying = draw();
  if (obeying.shape.isNotEmpty) return obeying;

  net.allowWrongWay = true;
  try {
    final anyway = draw();
    // Still nothing: the arrows were not what stopped it, so report the first
    // failure, which has the better reason in it.
    return anyway.shape.isNotEmpty ? anyway.withWrongWay() : obeying;
  } finally {
    net.allowWrongWay = false;
  }
}

// What used to live here: dropSplitArtifacts and mergeJoinedTrips.
//
// They looked at two trips that ended and began in the same place, decided
// the state had split one piece of driving in two, deleted the few tenths of
// a mile it writes to reach that point and come back, and joined the halves
// into one continuous line.
//
// Every word of that is an inference, and inferring is the one thing a route
// survey must not do. A survey splits without saying why: the software the
// states use starts a new leg whenever the surveyor stops and restarts, so a
// split can be construction, a road the state will not send a load down, or
// simply where somebody broke off. What is true in every case is that the
// load still has to get across and the road it crosses on was not approved. A
// line drawn continuously over that gap says the question was answered. It
// was not, and the only person who could tell was being shown the picture.
//
// Removed 2026-10-22, on Kyle's instruction: "it is only producing what the
// route survey gives it, not inferring anything." The gaps are now drawn as
// gaps, and joining them is step three, by hand, in yellow.

/// How close two pieces must come to count as already joined. (JOINED_MILES
/// on the web.)
///
/// About 260 feet. Two pieces of one survey that genuinely continue meet at a
/// shared point, give or take which vertex the road graph stopped on; anything
/// further apart is a gap the survey left, for a reason it does not record.
const double joinedMiles = 0.05;

class RouteGap {
  /// The gap lies after this piece, between it and the next.
  final int after;

  /// Where the earlier piece stops.
  final LL from;

  /// Where the later piece starts.
  final LL to;

  /// Straight-line miles across it. Not a distance to drive — a size.
  final double miles;

  const RouteGap({required this.after, required this.from, required this.to, required this.miles});
}

/// The places this route does not join up.
///
/// A state survey is a list of trips, and where it splits them the document
/// does not say why. Whatever the reason, the load still has to get across and
/// the road it crosses on was not part of what the state approved — so
/// somebody has to work it out and ask. That is the escort's job and nothing
/// here can do it.
///
/// What this does is refuse to let it go unnoticed. The gaps used to be closed
/// by merging the pieces, which drew a continuous line over a question nobody
/// had answered — and a continuous line is a claim that it was handled.
///
/// Empty pieces are skipped rather than reported: a trip that could not be
/// drawn at all is a different problem with its own message, and counting it
/// as a gap would ask the escort to join a line that is not there.
List<RouteGap> routeGaps(List<List<LL>> pieces) {
  final out = <RouteGap>[];
  final drawn = <(List<LL>, int)>[
    for (var i = 0; i < pieces.length; i++)
      if (pieces[i].length >= 2) (pieces[i], i),
  ];
  for (var k = 1; k < drawn.length; k++) {
    final a = drawn[k - 1].$1, b = drawn[k].$1;
    final from = a.last, to = b.first;
    final d = miles(from, to);
    if (d <= joinedMiles) continue;
    out.add(RouteGap(after: drawn[k - 1].$2, from: from, to: to, miles: d));
  }
  return out;
}

/// A sorted copy that keeps equal elements in their original order, as
/// JavaScript's Array.sort does and Dart's List.sort does not promise to.
List<T> _stableSorted<T>(List<T> list, int Function(T a, T b) cmp) {
  final idx = List.generate(list.length, (i) => i);
  idx.sort((i, j) {
    final c = cmp(list[i], list[j]);
    return c != 0 ? c : i.compareTo(j);
  });
  return [for (final i in idx) list[i]];
}
