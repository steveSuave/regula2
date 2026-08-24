import '../construction/geo_object.dart';
import '../construction/incidence.dart';
import '../construction/objects/ray.dart';
import '../construction/objects/segment.dart';
import 'fact_naming.dart';
import 'hypotheses.dart';
import 'predicate.dart';
import 'questions.dart';

/// How a question is spelled once the user has said *what* to ask about.
///
/// Two producers phrase questions: the selection chips
/// ([askableQuestions]), which read a `Set<String>` and offer every
/// reading it admits, and the question builder (`QuestionTemplate`,
/// Phase 160), where the user puts each object into a slot and the slot
/// carries the order. Both end at the same place — a [ProverQuestion]
/// holding every point-tuple spelling of one statement — and the
/// spelling rules live here so that a statement is spelled the same way
/// whichever surface asked it.
///
/// The rules, in one place:
///
/// - a line is named by *every* pair of points the construction puts on
///   it (across coincident copies, Phase 164), because a fact a rule
///   derives may be spelled with any of them;
/// - a **length** is named only by the pair that bounds it — a segment's
///   ends, or two points the user picked. `cong(A,X,C,D)` with `X` a
///   third point on segment `AB` is a *different statement* from
///   `|AB| = |CD|`, not a spelling of it, so `cong`, `eqratio` and `midp`
///   never read through the witness pairs;
/// - a tuple that names no pair of lines (`perp(a,b,a,b)`) is refused
///   before it is asked, as the rule engine refuses it at binding time.

/// A pair of points naming a line, and whether it bounds a length.
///
/// The distinction is what keeps `cong` from being asked about two
/// *lines*: "are these the same length?" is a question about segments
/// and about points the user picked, never about a line, which has no
/// length to compare. Direction and perpendicularity are fine either way.
class WitnessPair {
  const WitnessPair(this.a, this.b, {required this.boundsLength});

  final GeoPoint a;
  final GeoPoint b;
  final bool boundsLength;

  /// Both endpoints the same point: names no line at all.
  bool get isDegenerate => identical(a, b);

  /// Whether [other] names the same two points, either order.
  bool namesSameLine(WitnessPair other) =>
      (identical(a, other.a) && identical(b, other.b)) ||
      (identical(a, other.b) && identical(b, other.a));
}

/// Every way one line-shaped thing is named, and the points on it —
/// with whether the *thing* has a length.
class CarrierGroup {
  CarrierGroup(List<WitnessPair> pairs, List<GeoPoint> points)
    : pairs = List.unmodifiable(pairs),
      points = List.unmodifiable(points) {
    if (pairs.isEmpty) {
      throw ArgumentError.value(pairs, 'pairs', 'must be non-empty');
    }
  }

  /// Two points the user named as a pair: one witness, bounding a length.
  CarrierGroup.ofPoints(GeoPoint a, GeoPoint b)
    : this([WitnessPair(a, b, boundsLength: true)], [a, b]);

  /// The pairs on [carrier] over the points the construction puts on it
  /// (across coincident copies, Phase 164), or null when fewer than two
  /// points name it — a line with no name is not something the
  /// vocabulary can talk about.
  ///
  /// A segment or a ray bounds a length between its own two defining
  /// points, listed first; any other pair on it merely witnesses the
  /// direction. A general line bounds nothing.
  static CarrierGroup? ofCarrier(Iterable<GeoObject> objects, GeoLine carrier) {
    final on = pointsOnCarrier(objects, carrier);
    final pairs = <WitnessPair>[];
    final defining = switch (carrier) {
      Segment(:final point1, :final point2) => (point1, point2),
      Ray(:final origin, :final through) => (origin, through),
      _ => null,
    };
    if (defining != null) {
      pairs.add(WitnessPair(defining.$1, defining.$2, boundsLength: true));
    }
    for (var i = 0; i < on.length; i++) {
      for (var j = i + 1; j < on.length; j++) {
        if (defining != null &&
            ((identical(on[i], defining.$1) && identical(on[j], defining.$2)) ||
                (identical(on[i], defining.$2) &&
                    identical(on[j], defining.$1)))) {
          continue;
        }
        pairs.add(WitnessPair(on[i], on[j], boundsLength: false));
      }
    }
    if (pairs.isEmpty) return null;
    return CarrierGroup(pairs, on);
  }

  /// Every pair naming the line — the length-bounding one first when
  /// there is one.
  final List<WitnessPair> pairs;

  /// The points on the line, in construction order.
  final List<GeoPoint> points;

  /// Whether the thing has a length to compare.
  bool get boundsLength => pairs.any((pair) => pair.boundsLength);

  /// The pairs that name the *length*, not merely the direction.
  List<WitnessPair> get lengthPairs => [
    for (final pair in pairs)
      if (pair.boundsLength) pair,
  ];

  /// How the thing is named in a reading: its defining pair when it has
  /// one, else the first pair known on it — with the separator rule
  /// `readFact` uses.
  String get name {
    final pair = pairs.first;
    final names = [pair.a, pair.b].map(describePoint).toList();
    final separator = names.every((name) => name.length == 1) ? '' : ',';
    return names.join(separator);
  }
}

/// Whether relating [first] to [second] is structurally degenerate: a
/// pair with both endpoints the same point names no line at all, and two
/// pairs naming the *same* two points relate a line to itself.
///
/// Refused here rather than left to the filter: it is a property of the
/// tuple, not of any configuration, which is the same line the rule
/// engine draws at binding time.
bool degeneratePairs(WitnessPair first, WitnessPair second) =>
    first.isDegenerate || second.isDegenerate || first.namesSameLine(second);

/// A binary relation between two line-shaped things: `perp`, `para` or
/// `cong`, over every non-degenerate pairing of their names.
///
/// `cong` reads through the length pairs only (see the library note),
/// and is null when either side has no length. Null too when every
/// pairing is degenerate: the only phrasing named no pair of lines, so
/// there is no question.
ProverQuestion? relationQuestion(
  PredicateKind kind,
  CarrierGroup first,
  CarrierGroup second,
) {
  final List<WitnessPair> ps;
  final List<WitnessPair> qs;
  switch (kind) {
    case PredicateKind.perp:
    case PredicateKind.para:
      ps = first.pairs;
      qs = second.pairs;
    case PredicateKind.cong:
      if (!first.boundsLength || !second.boundsLength) return null;
      ps = first.lengthPairs;
      qs = second.lengthPairs;
    default:
      throw ArgumentError.value(kind, 'kind', 'not a relation of two lines');
  }
  final spellings = [
    for (final p in ps)
      for (final q in qs)
        if (!degeneratePairs(p, q)) Predicate(kind, [p.a, p.b, q.a, q.b]),
  ];
  if (spellings.isEmpty) return null;
  return ProverQuestion(kind, spellings);
}

/// Three line-shaped things: are they concurrent? Sugar (Phase 159,
/// PLAN §"JGEX's question list, compared"): in a point-tuple vocabulary
/// concurrency is `coll(P, X, Y)` where `P` is a named point on two of
/// the lines and `X`, `Y` name the third — every pair of carriers with a
/// named meeting point, every witness pair on the third. With no named
/// meeting point there is nothing to say, and the honest answer is null
/// rather than a point invented here. A `concurrent` predicate proper —
/// refutation with no named point at all — is a vocabulary addition and
/// its own phase.
ProverQuestion? concurrencyQuestion(List<CarrierGroup> groups) {
  if (groups.length != 3) {
    throw ArgumentError.value(groups, 'groups', 'concurrency is of three');
  }
  final spellings = <Predicate>[];
  for (var i = 0; i < 3; i++) {
    for (var j = i + 1; j < 3; j++) {
      final k = 3 - i - j;
      final meeting = [
        for (final point in groups[i].points)
          if (groups[j].points.any((other) => identical(other, point))) point,
      ];
      for (final p in meeting) {
        for (final pair in groups[k].pairs) {
          if (identical(p, pair.a) || identical(p, pair.b)) continue;
          spellings.add(Predicate(PredicateKind.coll, [p, pair.a, pair.b]));
        }
      }
    }
  }
  if (spellings.isEmpty) return null;
  final names = groups.map((group) => group.name).toList();
  return ProverQuestion(
    PredicateKind.coll,
    spellings,
    reading: '${names[0]}, ${names[1]} and ${names[2]} are concurrent',
  );
}

/// A line and a circle: is the line tangent? Sugar (Phase 159): the
/// tangent at `T` is perpendicular to the radius `O→T`, so the question
/// is `perp(O, T, T, P)` for every other named `P` on the line — which
/// needs a named centre and a named touch point, exactly as Phase 155's
/// hypothesis does. A point the construction puts on both the line and
/// the circle is the touch point; without one, or without a centre, or
/// for a conic that is not a circle by construction, there is no
/// statement to ask and the answer is null (naming the point is Phase
/// 153's job, not a special case here). A secant with two named
/// crossings phrases the same question about each, and the filter
/// refutes it.
ProverQuestion? tangencyQuestion(
  Iterable<GeoObject> objects,
  CarrierGroup line,
  GeoCircle circle,
) {
  if (!isCircleByConstruction(circle)) return null;
  final centre = circleCentre(circle, objects);
  if (centre == null) return null;
  final touches = [
    for (final point in line.points)
      if (structurallyIncident(circle, point)) point,
  ];
  final spellings = [
    for (final touch in touches)
      for (final other in line.points)
        if (!identical(other, touch) && !identical(other, centre))
          Predicate(PredicateKind.perp, [centre, touch, touch, other]),
  ];
  if (spellings.isEmpty) return null;
  final at = touches.length == 1 ? ' at ${describePoint(touches.single)}' : '';
  return ProverQuestion(
    PredicateKind.perp,
    spellings,
    reading: '${line.name} is tangent to the circle$at',
  );
}

/// `∠(g0, g1) = ∠(g2, g3)` over four line-shaped things, in the order
/// given — the spelling is the caller's, because the chip reads as
/// spelled (Phase 162). Every witness pair on each side; pairings that
/// name no angle (a degenerate side) or that spell `θ = θ` (the same two
/// lines on both sides) are dropped. Null when nothing is left.
ProverQuestion? eqangleQuestion(List<CarrierGroup> groups) {
  if (groups.length != 4) {
    throw ArgumentError.value(groups, 'groups', 'eqangle is of four');
  }
  final [gi, gj, gk, gl] = groups;
  final spellings = [
    for (final p in gi.pairs)
      for (final q in gj.pairs)
        for (final r in gk.pairs)
          for (final s in gl.pairs)
            if (!degeneratePairs(p, q) &&
                !degeneratePairs(r, s) &&
                !_sameLines(p, q, r, s))
              Predicate(PredicateKind.eqangle, [
                p.a,
                p.b,
                q.a,
                q.b,
                r.a,
                r.b,
                s.a,
                s.b,
              ]),
  ];
  if (spellings.isEmpty) return null;
  return ProverQuestion(PredicateKind.eqangle, spellings);
}

/// Whether the angle from [p] to [q] is the angle from [r] to [s] by
/// spelling alone — the same two lines on both sides, in either order —
/// which is `0 = 0` or `θ = θ` and not a question.
bool _sameLines(WitnessPair p, WitnessPair q, WitnessPair r, WitnessPair s) =>
    (p.namesSameLine(r) && q.namesSameLine(s)) ||
    (p.namesSameLine(s) && q.namesSameLine(r));
