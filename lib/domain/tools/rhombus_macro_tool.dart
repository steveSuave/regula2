import '../construction/geo_object.dart';
import '../construction/object_attributes.dart';
import '../construction/objects/compass_circle.dart';
import '../construction/objects/intersection_point.dart';
import '../construction/objects/parallel_line.dart';
import '../construction/objects/point_on_object.dart';
import '../construction/objects/segment.dart';
import '../math/vec2.dart';
import '../projective/conic_shape.dart';
import 'mirror_point_scaffolding.dart';
import 'multi_point_tool.dart';
import 'tool.dart';

/// Three taps make a rhombus: the first two are adjacent corners A, B
/// (one side); the third is *position-only* and picks the adjacent
/// side's direction — corner C is the tap projected onto the hidden
/// compass circle around B with radius |AB|, so |BC| = |AB| rides the
/// construction. D closes the shape so that |CD| = |DA| = |AB| as well,
/// making all four sides equal under every drag.
///
/// **How D is built depends on the document's geometry** (Phase 138):
///
/// - **Euclidean**: the parallelogram trick — the single-branch
///   intersection of the parallel to AB through C with the parallel to
///   BC through A. Kept because it is what every existing document
///   contains, and because a line∩line meet has no branch to pick.
/// - **Proper absolute**: D is B reflected across the diagonal AC. "The
///   parallel through a point" is the uniqueness a Cayley–Klein plane
///   exists to deny, so the Euclidean route has no analogue there; an
///   equilateral quadrilateral does, and a rhombus's diagonal is an axis
///   of symmetry in every geometry. Not the Euclid I.1 route PLAN
///   §"The macro triage" recorded — see [_metricCornerD] for what
///   measuring it found.
///
/// Like the trapezium's fourth tap, the third input projects an existing
/// point's location but never consumes the object — C must stay
/// constrained to the circle. C is a `PointOnObject` on a compass circle,
/// which under a proper absolute is a conic bitangent to the absolute
/// with no centre and no polar angle: it is swept by `ConicShape`'s
/// pencil angle instead (Phase 132), which is the capability this tool
/// was refused for until now.
///
/// Coincident A, B collapse the circle to its center: the shape is
/// degenerate but every parent stays defined, and separating the corners
/// restores it.
class RhombusMacroTool extends MultiPointTool {
  RhombusMacroTool({required super.newId});

  /// The tapped corner points; the position-only third input is not a
  /// collected vertex.
  @override
  int get pointCount => 2;

  /// The third tap, alive only inside the commit turn.
  Vec2? _cTarget;

  @override
  ToolResult onInput(ToolInput input) {
    if (collectedVertices.length < pointCount) {
      return collectVertex(input) == null
          ? const ToolIgnored()
          : const ToolAccepted();
    }
    _cTarget = input.position;
    final result = commitCollected();
    _cTarget = null;
    return result;
  }

  @override
  void reset() {
    _cTarget = null;
    super.reset();
  }

  @override
  List<GeoObject> buildObjects(List<GeoPoint> points) {
    final a = points[0];
    final b = points[1];

    final sideAB = Segment(id: newId(), point1: a, point2: b);
    final circleAroundB = _compass(centre: b, a: a, b: b);
    final cornerC = _cornerOn(circleAroundB)..recompute(absolute);
    final sideBC = Segment(id: newId(), point1: b, point2: cornerC);
    final (:scaffolding, corner: cornerD) = absolute.isEuclidean
        ? _euclideanCornerD(a: a, sideAB: sideAB, sideBC: sideBC, c: cornerC)
        : _metricCornerD(a: a, c: cornerC, b: b);

    return [
      sideAB,
      circleAroundB,
      cornerC,
      sideBC,
      ...scaffolding,
      cornerD,
      Segment(id: newId(), point1: cornerC, point2: cornerD),
      Segment(id: newId(), point1: cornerD, point2: a),
    ];
  }

  /// A hidden circle centred at [centre] with radius |[a][b]|,
  /// recomputed under the document's absolute: a constructor has no
  /// document to ask and settles on the Euclidean default, while
  /// [_cornerOn] and [_metricCornerD] read the conic straight back.
  CompassCircle _compass({
    required GeoPoint centre,
    required GeoPoint a,
    required GeoPoint b,
  }) => CompassCircle(
    id: newId(),
    radiusPoint1: a,
    radiusPoint2: b,
    center: centre,
    attributes: const ObjectAttributes(visible: false),
  )..recompute(absolute);

  /// Corner C: the third tap glued where it landed on [circle].
  ///
  /// A zero-radius circle (A ≡ B) is still a defined curve, but it has no
  /// point to project onto — the Euclidean projection has no angle to
  /// pick at its centre, and the degenerate conic has no real curve for
  /// `ConicShape` to search. Both fall back to the parameter origin, like
  /// the trapezium does on an undefined carrier.
  PointOnObject _cornerOn(CompassCircle circle) {
    final target = _cTarget!;
    final chart = circle.circle;
    final degenerate = chart != null
        ? target == chart.center
        : circle.conic == null ||
              ConicShape.of(circle.conic!).parameterNear(target) == null;
    return degenerate
        ? PointOnObject(id: newId(), curve: circle, parameter: 0)
        : PointOnObject.near(id: newId(), curve: circle, position: target);
  }

  /// The parallelogram trick, Euclidean only: D is where the parallel to
  /// AB through C meets the parallel to BC through A. One meet, no
  /// branch.
  ({List<GeoObject> scaffolding, GeoPoint corner}) _euclideanCornerD({
    required GeoPoint a,
    required Segment sideAB,
    required Segment sideBC,
    required PointOnObject c,
  }) {
    const hidden = ObjectAttributes(visible: false);
    final parallelThroughC = ParallelLine(
      id: newId(),
      through: c,
      reference: sideAB,
      attributes: hidden,
    );
    final parallelThroughA = ParallelLine(
      id: newId(),
      through: a,
      reference: sideBC,
      attributes: hidden,
    );
    return (
      scaffolding: [parallelThroughC, parallelThroughA],
      corner: IntersectionPoint(
        id: newId(),
        curve1: parallelThroughC,
        curve2: parallelThroughA,
        branchIndex: 0,
        absolute: absolute,
      ),
    );
  }

  /// D is B **reflected across the diagonal AC** — the harmonic homology
  /// in AC with respect to the absolute, single-valued and branch-free.
  /// The reflection fixes A and C, so |AD| = |AB| and |CD| = |CB|, and
  /// |CB| = |AB| already because C rides the compass circle about B: all
  /// four sides equal, in every geometry.
  ///
  /// **This is not the route PLAN §"The macro triage" recorded**, which
  /// was Euclid I.1 — D as the crossing of the compass circles about A
  /// and about C other than B. That construction is correct and its
  /// branch is unstable, for the reason [mirrorPointAcross]'s own doc
  /// gives: B lies on both circles, so the two crossings are B and D,
  /// they *swap* as B crosses the axis, and a `branchIndex` is fixed at
  /// creation. Sliding C once around its circle passes through collinear
  /// A, B, C — measured on a hyperbolic rhombus, D jumps 0.80 world units
  /// onto B at the crossing and stays pinned there for the rest of the
  /// sweep, the figure folded flat onto triangle ABC with no drag that
  /// recovers it. Every side stays equal throughout, which is why the
  /// obvious test cannot see it. See PLAN §"The macro triage" and Phase
  /// 138.
  ({List<GeoObject> scaffolding, GeoPoint corner}) _metricCornerD({
    required GeoPoint a,
    required PointOnObject c,
    required GeoPoint b,
  }) {
    final diagonalAC = Segment(
      id: newId(),
      point1: a,
      point2: c,
      attributes: const ObjectAttributes(visible: false),
    )..recompute(absolute);
    final (:scaffolding, :mirrored) = mirrorPointAcross(
      point: b,
      axis: diagonalAC,
      newId: newId,
      absolute: absolute,
    );
    return (scaffolding: [diagonalAC, ...scaffolding], corner: mirrored);
  }
}
