import '../construction/geo_object.dart';
import '../construction/object_attributes.dart';
import '../construction/objects/parallel_line.dart';
import '../construction/objects/point_on_object.dart';
import '../construction/objects/segment.dart';
import '../math/vec2.dart';
import '../projective/absolute.dart';
import 'multi_point_tool.dart';
import 'tool.dart';

/// Four taps make a trapezium: the first three are consecutive corners
/// A, B, C; the fourth places the last corner D *on* the hidden parallel
/// to AB through C, projected from the tap — so AB ∥ CD by construction
/// and dragging any tapped corner keeps the shape a trapezium.
///
/// The fourth input is *position-only*: tapping an existing point
/// projects its location but never consumes the object — D must stay
/// constrained to the parallel. D is a `PointOnObject` and inherits its
/// analytic-parameter caveat (translating the parallel along itself
/// leaves D in place; see that class).
///
/// While the tapped corners are degenerate (A and B coincident) the
/// parallel has no geometry to project the fourth tap onto — D falls
/// back to parameter 0 and recovers with the rest of the shape when the
/// corners separate.
class TrapeziumMacroTool extends MultiPointTool {
  TrapeziumMacroTool({required super.newId});

  /// The tapped corner points; the position-only fourth input is not a
  /// collected vertex.
  /// **Euclidean only** (Phase 129). The fourth corner is glued to *the*
  /// parallel to AB through C, and that uniqueness is what a Cayley–Klein
  /// plane denies — from below in the hyperbolic case, where infinitely
  /// many lines through C miss AB, and from above in the elliptic one,
  /// where none do. `parallelThrough` already answered the zero triple;
  /// nothing downstream had noticed.
  @override
  bool availableUnder(Absolute absolute) => absolute.isEuclidean;

  @override
  int get pointCount => 3;

  /// The fourth tap, alive only inside the commit turn.
  Vec2? _dTarget;

  @override
  ToolResult onInput(ToolInput input) {
    if (collectedVertices.length < pointCount) {
      return collectVertex(input) == null
          ? const ToolIgnored()
          : const ToolAccepted();
    }
    _dTarget = input.position;
    final result = commitCollected();
    _dTarget = null;
    return result;
  }

  @override
  void reset() {
    _dTarget = null;
    super.reset();
  }

  @override
  List<GeoObject> buildObjects(List<GeoPoint> points) {
    final a = points[0];
    final b = points[1];
    final c = points[2];
    const hidden = ObjectAttributes(visible: false);

    final sideAB = Segment(id: newId(), point1: a, point2: b);
    final sideBC = Segment(id: newId(), point1: b, point2: c);
    final parallel = ParallelLine(
      id: newId(),
      through: c,
      reference: sideAB,
      attributes: hidden,
    );
    final cornerD = parallel.line == null
        ? PointOnObject(id: newId(), curve: parallel, parameter: 0)
        : PointOnObject.near(id: newId(), curve: parallel, position: _dTarget!);

    return [
      sideAB,
      sideBC,
      parallel,
      cornerD,
      Segment(id: newId(), point1: c, point2: cornerD),
      Segment(id: newId(), point1: cornerD, point2: a),
    ];
  }
}
