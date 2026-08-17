import '../construction/geo_object.dart';
import '../construction/object_attributes.dart';
import '../construction/objects/intersection_point.dart';
import '../construction/objects/parallel_line.dart';
import '../construction/objects/segment.dart';
import 'multi_point_tool.dart';

/// Three taps make a parallelogram: the tapped points are consecutive
/// corners A, B, C, and the fourth corner D = A + (C − B) is *derived*,
/// so dragging any tapped corner keeps the shape a parallelogram.
///
/// Like `SquareMacroTool`, D is a scripted composition of existing
/// primitives: the intersection of the parallel to BC through A with the
/// parallel to AB through C, both referenced on the visible side
/// segments and added invisible. Line∩line has a single branch, so there
/// is no side to pick — the parallelogram is fully determined by the
/// three taps.
///
/// Collinear (or coincident) corners leave the two parallels parallel to
/// each other, so D and the sides through it stay undefined until the
/// degeneracy passes.
///
/// When the construction already contains a visible point identically
/// coincident with D — the tapped points were three corners of an
/// existing parallelogram, or three side-midpoints of a quadrilateral
/// (Varignon) — that point is reused as the fourth corner and the hidden
/// scaffolding is not added at all (see [dedupedDerivedPoint]).
class ParallelogramMacroTool extends MultiPointTool {
  ParallelogramMacroTool({required super.newId});

  @override
  int get pointCount => 3;

  @override
  List<GeoObject> buildObjects(List<GeoPoint> points) {
    final a = points[0];
    final b = points[1];
    final c = points[2];
    const hidden = ObjectAttributes(visible: false);

    final sideAB = Segment(id: newId(), point1: a, point2: b);
    final sideBC = Segment(id: newId(), point1: b, point2: c);
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
    final cornerD = IntersectionPoint(
      id: newId(),
      curve1: parallelThroughC,
      curve2: parallelThroughA,
      branchIndex: 0,
      absolute: absolute,
    );
    final corner = dedupedDerivedPoint(cornerD);

    return [
      sideAB,
      sideBC,
      if (identical(corner, cornerD)) ...[
        parallelThroughC,
        parallelThroughA,
        cornerD,
      ],
      Segment(id: newId(), point1: c, point2: corner),
      Segment(id: newId(), point1: corner, point2: a),
    ];
  }
}
