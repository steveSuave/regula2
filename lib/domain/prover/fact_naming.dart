import '../construction/geo_object.dart';
import 'fact.dart';
import 'predicate.dart';
import 'rational.dart';

/// How a fact is spelled for a reader, in one place.
///
/// This lives apart from `proof.dart` for an import-graph reason rather
/// than a conceptual one: `angle_chase.dart` names points too, and
/// `proof.dart` reads chases, so leaving these there would make the two
/// files mutually dependent. `proof.dart` re-exports them, so every
/// existing caller keeps its import.

/// A fact written for a reader: the kind, and each point by the name the
/// figure gives it, falling back to its id where it has none.
String describeFact(Fact fact) =>
    '${fact.kind.name}(${fact.points.map(describePoint).join(', ')}'
    '${fact.value == null ? '' : '; ${fact.value}'})';

/// A point's user-facing name, or its id when it is unnamed.
String describePoint(GeoPoint point) =>
    point.attributes.name.isEmpty ? point.id : point.attributes.name;

/// A kind's display name, as a heading over facts of that kind.
///
/// The display-name table the vocabulary does not have: `PredicateKind`
/// names its members for the rule set (`coll`, `eqangle`), and a reader
/// grouping the derived list wants "Collinear points". Lives beside
/// [readFact] for the same reason: what a list *says* should be readable
/// without a widget tree.
///
/// Exhaustive over a closed enum, deliberately — the argument written
/// at `stepReason`: a kind added without a label is a build error here,
/// where a string table would quietly fall behind. Header order in a
/// grouped list is `PredicateKind.values`' own, so it is fixed by the
/// declaration and never by the data.
String predicateKindLabel(PredicateKind kind) => switch (kind) {
  PredicateKind.coll => 'Collinear points',
  PredicateKind.para => 'Parallel lines',
  PredicateKind.perp => 'Perpendicular lines',
  PredicateKind.cong => 'Equal lengths',
  PredicateKind.cyclic => 'Concyclic points',
  PredicateKind.eqangle => 'Equal angles',
  PredicateKind.eqratio => 'Equal ratios',
  PredicateKind.midp => 'Midpoints',
  PredicateKind.simtri => 'Similar triangles',
  PredicateKind.contri => 'Congruent triangles',
  PredicateKind.rconst => 'Stated ratios',
  PredicateKind.lconst => 'Stated lengths',
};

/// A fact as a sentence — the prose renderer, beside [describeFact] and
/// deliberately not replacing it.
///
/// [describeFact] is what `Proof.render()` prints and what the
/// certificate tests read; making *it* prose would churn those
/// expectations and lose which spelling was actually derived. Prose is a
/// second renderer with a different job: the row a user reads.
///
/// Each kind gets its honest reading — `cong` is "equal in length", not
/// "AB = CD", which reads as the points coinciding. `eqangle` is the one
/// that can lie: it relates four *lines* mod π, so a three-point angle
/// name exists only when the two lines of a pair share a point. The
/// shared-vertex case is detected per pair and spelled three-point;
/// otherwise the pair is spelled as the lines it is
/// ("the angle from AB to CD"), because naming "angle ABC" for a
/// non-incident pair would be inventing a point.
///
/// What "equal" and "similar" claim is deliberately plain: `eqangle` is
/// read mod π and `simtri`/`contri` are orientation-free (M-P1), so the
/// sentence says marginally more than the fact does. The convention is
/// stated once, as [factReadingConvention], rather than hedged on every
/// line — a decision, not a default (Phase 157).
///
/// The segment separator is `angle_chase.dart`'s rule, not a second one
/// that could drift from it: decided once per fact, `AB` when every
/// name is a single character, `A,B` otherwise — "angle p17p3p9" would
/// run three names into one.
String readFact(Fact fact) => _read(fact.kind, fact.points, fact.value);

/// [readFact] for a predicate *as spelled* (Phase 162).
///
/// A fact reads in canonical order because it *is* its orbit — every
/// spelling is the same statement. A question is one spelling the user
/// chose, and for `eqangle` the choice is visible: the transpose
/// symmetry turns `∠(BC,CE) = ∠(BD,DC)` into `∠(EC,DC) = ∠(BC,DB)`,
/// the same directed statement mod π, whose three-point prose names
/// angles of different magnitude. Canonicalizing before reading would
/// hand the user a sentence they did not ask and would not believe.
String readPredicate(Predicate predicate) =>
    _read(predicate.kind, predicate.points, predicate.value);

String _read(PredicateKind kind, List<GeoPoint> points, Rational? value) {
  final names = points.map(describePoint).toList();
  final separator = names.every((name) => name.length == 1) ? '' : ',';
  String seg(int i) => '${names[i]}$separator${names[i + 1]}';
  String tri(int i) =>
      '${names[i]}$separator${names[i + 1]}$separator${names[i + 2]}';
  return switch (kind) {
    PredicateKind.coll => '${names[0]}, ${names[1]}, ${names[2]} are collinear',
    PredicateKind.para => '${seg(0)} is parallel to ${seg(2)}',
    PredicateKind.perp => '${seg(0)} is perpendicular to ${seg(2)}',
    PredicateKind.cong => '${seg(0)} and ${seg(2)} are equal in length',
    PredicateKind.cyclic => '${names.join(', ')} lie on a circle',
    PredicateKind.midp => '${names[0]} is the midpoint of ${seg(1)}',
    PredicateKind.eqratio => '${seg(0)} : ${seg(2)} = ${seg(4)} : ${seg(6)}',
    PredicateKind.simtri => 'triangles ${tri(0)} and ${tri(3)} are similar',
    PredicateKind.contri => 'triangles ${tri(0)} and ${tri(3)} are congruent',
    PredicateKind.eqangle => _readEqangle(points, names, separator),
    PredicateKind.rconst => '${seg(0)} : ${seg(2)} = $value',
    PredicateKind.lconst => '${seg(0)} has length $value',
  };
}

/// The convention [readFact]'s plain wording leaves implicit, to be
/// stated once where facts are read rather than repeated on every line:
/// angle equality is between lines and read mod π, and similarity and
/// congruence do not distinguish mirror images.
const String factReadingConvention =
    'Angles are compared as lines, mod π; similar and congruent '
    'triangles may be mirror images.';

String _readEqangle(
  List<GeoPoint> points,
  List<String> names,
  String separator,
) {
  final first = _anglePhrase(points, names, separator, 0);
  final second = _anglePhrase(points, names, separator, 4);
  if (first.threePoint && second.threePoint) {
    return 'angles ${first.text} and ${second.text} are equal';
  }
  String phrase(({String text, bool threePoint}) half) =>
      half.threePoint ? 'angle ${half.text}' : 'the angle from ${half.text}';
  return '${phrase(first)} equals ${phrase(second)}';
}

/// One half of an `eqangle` — the pair of lines at [offset] — as either
/// a three-point angle name (when the lines share exactly one point,
/// which is then the vertex) or the two lines themselves.
///
/// Exactly one: a pair sharing both points is one line twice, and there
/// is no angle there to name three-point.
({String text, bool threePoint}) _anglePhrase(
  List<GeoPoint> points,
  List<String> names,
  String separator,
  int offset,
) {
  final shared = <(int, int)>[
    for (var i = offset; i < offset + 2; i++)
      for (var j = offset + 2; j < offset + 4; j++)
        if (identical(points[i], points[j])) (i, j),
  ];
  if (shared.length == 1) {
    final (i, j) = shared.single;
    final arm1 = names[i == offset ? offset + 1 : offset];
    final arm2 = names[j == offset + 2 ? offset + 3 : offset + 2];
    return (
      text: '$arm1$separator${names[i]}$separator$arm2',
      threePoint: true,
    );
  }
  final line1 = '${names[offset]}$separator${names[offset + 1]}';
  final line2 = '${names[offset + 2]}$separator${names[offset + 3]}';
  return (text: '$line1 to $line2', threePoint: false);
}
