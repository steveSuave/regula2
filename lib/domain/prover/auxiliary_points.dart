import '../construction/geo_object.dart';
import '../construction/objects/intersection_point.dart';
import '../construction/objects/midpoint.dart';
import '../construction/objects/projection_point.dart';
import '../projective/absolute.dart';

/// The families a proposed point can come from, in the order Phase 153's
/// checklist names them — midpoints first, then feet of perpendiculars,
/// then intersections.
///
/// The order was a guess when the checklist was written and is a
/// measurement now: `auxiliary_upside_test.dart` finds every unlock in
/// the corpus in [midpoint], and none in the other two.
enum AuxiliaryFamily { midpoint, foot, meet }

/// A point the prover could construct but the user did not draw — JGEX's
/// A2, enumerated (PLAN §M-P, Phase 153).
///
/// It names its parents by *reference*, which is `Construction.add`'s own
/// contract: the graph is wired by identity, so a candidate enumerated
/// over one construction can only be built into that construction. A
/// caller trying candidates one at a time on fresh copies re-enumerates
/// per copy; [auxiliaryCandidates] is deterministic, so index *i* names
/// the same point in every copy of one document.
class AuxiliaryCandidate {
  const AuxiliaryCandidate(this.family, this.parents, {this.branch = 0});

  final AuxiliaryFamily family;

  /// Two objects: two points for [AuxiliaryFamily.midpoint], a point and
  /// a line for [AuxiliaryFamily.foot], two curves for
  /// [AuxiliaryFamily.meet].
  final List<GeoObject> parents;

  /// Which crossing, for [AuxiliaryFamily.meet]; zero otherwise.
  final int branch;

  /// The point itself, under [id].
  ///
  /// Built detached — recomputing off its parents but in no
  /// construction, which is how [auxiliaryCandidates] reads a proposal's
  /// position before deciding to offer it.
  GeoPoint build(String id) => switch (family) {
    AuxiliaryFamily.midpoint => Midpoint(
      id: id,
      point1: parents[0] as GeoPoint,
      point2: parents[1] as GeoPoint,
    ),
    AuxiliaryFamily.foot => ProjectionPoint(
      id: id,
      point: parents[0] as GeoPoint,
      line: parents[1] as GeoLine,
    ),
    AuxiliaryFamily.meet => IntersectionPoint(
      id: id,
      curve1: parents[0],
      curve2: parents[1],
      branchIndex: branch,
    ),
  };

  @override
  String toString() {
    final names = [for (final parent in parents) parent.id].join(',');
    return family == AuxiliaryFamily.meet
        ? '${family.name}($names:$branch)'
        : '${family.name}($names)';
  }
}

/// Every auxiliary point [objects] admits, deduplicated and in a
/// deterministic order.
///
/// The families in [families] are enumerated in [AuxiliaryFamily]'s
/// declaration order, and within a family in the objects' own order, so
/// the list is a function of the document alone — which is what lets a
/// search resume, and what lets a measurement name a candidate by index.
///
/// **A proposal coinciding with a point already there is dropped, and
/// the test is numeric on purpose.** Some coincidences are structural (a
/// document that already names the midpoint of `AB`) and some are
/// theorems (the foot of a centre on a chord *is* that chord's
/// midpoint) — and no structural test sees the second kind. This is the
/// `DiagramFilter` boundary, not a violation of it: which points are
/// worth *proposing* is a search heuristic, where reading the diagram is
/// sanctioned, and nothing here asserts a predicate. Every statement the
/// proposed point goes on to license is derived structurally and
/// screened by the filter exactly as any other.
///
/// A proposal with no real finite position is dropped for the same
/// reason and with no comment on whether it exists: two parallel lines
/// meet at infinity, and a point the user could not have drawn is not a
/// point the prover should offer to draw for them.
List<AuxiliaryCandidate> auxiliaryCandidates(
  Iterable<GeoObject> objects, {
  Set<AuxiliaryFamily> families = const {
    AuxiliaryFamily.midpoint,
    AuxiliaryFamily.foot,
    AuxiliaryFamily.meet,
  },
  Absolute absolute = Absolute.euclidean,
  double tolerance = 1e-6,
}) {
  final all = List.of(objects);
  final points = [
    for (final object in all)
      if (object is GeoPoint && object.position != null) object,
  ];
  final lines = [
    for (final object in all)
      if (object is GeoLine && object.projLine != null) object,
  ];
  final circles = [
    for (final object in all)
      if (object is GeoCircle && object.conic != null) object,
  ];

  final taken = [for (final point in points) point.position!];
  final out = <AuxiliaryCandidate>[];
  void offer(AuxiliaryCandidate candidate) {
    final position = candidate.build('probe').position;
    if (position == null) return;
    if (taken.any((other) => other.distanceTo(position) < tolerance)) return;
    taken.add(position);
    out.add(candidate);
  }

  if (families.contains(AuxiliaryFamily.midpoint)) {
    for (var i = 0; i < points.length; i++) {
      for (var j = i + 1; j < points.length; j++) {
        offer(
          AuxiliaryCandidate(AuxiliaryFamily.midpoint, [points[i], points[j]]),
        );
      }
    }
  }
  if (families.contains(AuxiliaryFamily.foot)) {
    for (final point in points) {
      for (final line in lines) {
        // A point on the line is its own foot, and the dedup above is
        // what knows it — an incidence test here was written first and
        // deleted, because it failed no test the dedup was not already
        // failing. One mechanism, and it covers the numeric case too.
        offer(AuxiliaryCandidate(AuxiliaryFamily.foot, [point, line]));
      }
    }
  }
  if (families.contains(AuxiliaryFamily.meet)) {
    final curves = <GeoObject>[...lines, ...circles];
    for (var i = 0; i < curves.length; i++) {
      for (var j = i + 1; j < curves.length; j++) {
        final crossings = intersectionCandidates(
          curves[i],
          curves[j],
          absolute: absolute,
        ).length;
        for (var branch = 0; branch < crossings; branch++) {
          offer(
            AuxiliaryCandidate(AuxiliaryFamily.meet, [
              curves[i],
              curves[j],
            ], branch: branch),
          );
        }
      }
    }
  }
  return out;
}
