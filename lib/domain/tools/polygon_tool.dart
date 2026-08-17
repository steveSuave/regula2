import '../construction/geo_object.dart';
import '../construction/object_attributes.dart';
import '../construction/objects/polygon.dart';
import 'multi_point_tool.dart';
import 'tool.dart';

/// Collects polygon vertices one ladder-resolved tap at a time and
/// **closes on re-tapping the first vertex** once at least 3 are
/// collected — no dialog, no fixed count (the first variable-arity tool).
///
/// A tap on any *other* already-collected vertex is ignored: a vertex may
/// appear once per loop, so no self-touching rings. Collected existing
/// points are recognized by hit identity; not-yet-committed new points
/// (which the hit tester can't see) by tap distance within the snap
/// threshold — with snapping disabled (threshold 0) a new first vertex
/// can't be re-tapped, matching the ladder's own degraded behavior.
///
/// The commit is one `MacroCommand` of the new points followed by the
/// [Polygon], which gets `fillAlpha: 0.25` baked in — the attribute
/// *default* stays null, so nothing else starts filling.
class PolygonTool extends MultiPointTool {
  PolygonTool({required super.newId});

  /// The polygon's translucent default fill, baked into the created
  /// object (the Phase 22 checkbox value: alpha byte 64).
  static const double defaultFillAlpha = 0.25;

  /// Unused — the polygon closes by gesture, not by count; [onInput] is
  /// fully overridden and never consults this.
  @override
  int get pointCount => 3;

  @override
  ToolResult onInput(ToolInput input) {
    final tappedIndex = _collectedIndexOf(input);
    if (tappedIndex != null) {
      if (tappedIndex == 0 && collectedVertices.length >= 3) {
        return commitCollected();
      }
      return const ToolIgnored();
    }
    if (collectVertex(input) == null) {
      return const ToolIgnored();
    }
    return const ToolAccepted();
  }

  @override
  List<GeoObject> buildObjects(List<GeoPoint> points) => [
    Polygon(
      id: newId(),
      vertices: points,
      attributes: const ObjectAttributes(fillAlpha: defaultFillAlpha),
    ),
  ];

  /// The index of the already-collected vertex [input] lands on, or null.
  /// Existing points match by hit identity; new private points by
  /// position within the snap threshold — but only while the tap isn't
  /// consuming an existing point (a point hit *means* that point, even
  /// right next to a collected new vertex).
  int? _collectedIndexOf(ToolInput input) {
    final vertices = collectedVertices;
    final existingIds = previewObjectIds.toSet();
    final hit = input.hit;
    for (var i = 0; i < vertices.length; i++) {
      final vertex = vertices[i];
      if (existingIds.contains(vertex.id)) {
        if (identical(hit, vertex)) {
          return i;
        }
      } else if (hit is! GeoPoint) {
        final position = vertex.position;
        if (position != null &&
            input.position.distanceTo(position) <= input.snapThreshold) {
          return i;
        }
      }
    }
    return null;
  }
}
