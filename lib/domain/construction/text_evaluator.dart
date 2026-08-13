import 'dart:math' as math;

import '../math/expression.dart';
import '../math/polygon_math.dart';
import '../math/vec2.dart';
import 'geo_object.dart';
import 'objects/arc.dart';
import 'objects/sector.dart';
import 'objects/segment.dart';
import 'text_template.dart';

/// The geometry side of the text tool's expression language (Phase 58):
/// binds names to [GeoObject]s and answers the accessors and bare-name
/// sugar over their live geometry. Everything unknown, mistyped or
/// currently undefined yields null — `TextTemplate.render` shows it as
/// `?` — so `ExpressionText.recompute` can never throw.
///
/// Migrated (Phase 112): point and circle accessors read the referenced
/// objects' projective views and project them into the chart here — every
/// expression value is a chart quantity (the metric boundary). A
/// reference that is complex or at infinity renders `?`, exactly like an
/// undefined one. `Segment.start`/`end` sugar stays on the kind's own
/// drawable-endpoint API (itself a projection of migrated parents).

const double _degPerRad = 180 / math.pi;

/// Resolves each of [names] to the object so named, in order.
///
/// Throws [FormatException] — shared by the dialog validator and the tool
/// — when a name matches nothing, or matches a text (texts are not
/// referenceable v1: nothing may ever depend on a text).
List<GeoObject> bindReferences(
  List<String> names,
  Iterable<GeoObject> objects,
) {
  final byName = <String, GeoObject>{};
  for (final object in objects) {
    final name = object.attributes.name;
    if (name.isNotEmpty) {
      byName.putIfAbsent(name, () => object);
    }
  }
  return [
    for (final name in names)
      switch (byName[name]) {
        null => throw FormatException("No object named '$name'"),
        GeoText() => throw FormatException(
            "Texts can't reference other texts ('$name')"),
        final object => object,
      },
  ];
}

/// An [ExpressionEnv] over a fixed name → object binding (built once at
/// creation from the template's `referenceNames`, so later renames don't
/// change what a text measures).
class GeoObjectEnv implements ExpressionEnv {
  const GeoObjectEnv(this.bindings);

  final Map<String, GeoObject> bindings;

  /// Bare-name sugar: a segment reads as its length, a measurement as its
  /// value, an angle as its degree measure. Other kinds have no obvious
  /// single number (a circle name could mean radius, circumference or
  /// area) and stay accessor-only.
  @override
  double? variable(String name) => switch (bindings[name]) {
        Segment(:final start?, :final end?) => start.distanceTo(end),
        GeoMeasurement(:final value) => value,
        GeoAngle(:final angle?) => angle.measure * _degPerRad,
        _ => null,
      };

  @override
  bool isObjectFunction(String name) => objectFunctionNames.contains(name);

  @override
  double? objectFunction(String name, List<String> argNames) {
    final args = <GeoObject>[];
    for (final argName in argNames) {
      final object = bindings[argName];
      if (object == null) {
        return null;
      }
      args.add(object);
    }
    return switch ((name, args)) {
      ('dist', [final GeoPoint p, final GeoPoint q]) =>
        _distance(p.projPoint?.toVec2(), q.projPoint?.toVec2()),
      ('len', [Segment(:final start?, :final end?)]) => start.distanceTo(end),
      ('len', [final GeoCircle curve]) => _circleLength(curve),
      ('angle', [final GeoPoint a, final GeoPoint b, final GeoPoint c]) =>
        _angleDegrees(
          a.projPoint?.toVec2(),
          b.projPoint?.toVec2(),
          c.projPoint?.toVec2(),
        ),
      ('area', [GeoPolygon(:final polygonVertices?)]) =>
        polygonSignedArea(polygonVertices).abs(),
      ('area', [final GeoCircle curve]) => _circleArea(curve),
      ('radius', [GeoCircle(:final conic?)]) => conic.toCircleEq()?.radius,
      ('perimeter', [GeoPolygon(:final polygonVertices?)]) =>
        _polygonPerimeter(polygonVertices),
      ('x', [final GeoPoint p]) => p.projPoint?.toVec2()?.x,
      ('y', [final GeoPoint p]) => p.projPoint?.toVec2()?.y,
      _ => null,
    };
  }
}

double? _distance(Vec2? p, Vec2? q) =>
    (p == null || q == null) ? null : p.distanceTo(q);

/// `LengthMeasurement` semantics: circumference for a full circle, arc
/// length for an arc, full perimeter (both radii) for a sector.
double? _circleLength(GeoCircle curve) {
  final circle = curve.conic?.toCircleEq();
  if (circle == null) {
    return null;
  }
  return switch (curve) {
    Sector(:final sweep?) => 2 * circle.radius + circle.radius * sweep,
    Arc(:final sweep?) => circle.radius * sweep.abs(),
    Sector() || Arc() => null,
    _ => 2 * math.pi * circle.radius,
  };
}

/// `AreaMeasurement` semantics: disc for a full circle, wedge for a
/// sector, the chord's circular segment for an arc.
double? _circleArea(GeoCircle curve) {
  final circle = curve.conic?.toCircleEq();
  if (circle == null) {
    return null;
  }
  final r = circle.radius;
  return switch (curve) {
    Sector(:final sweep?) => r * r * sweep / 2,
    Arc(:final sweep?) => r * r * (sweep.abs() - math.sin(sweep.abs())) / 2,
    Sector() || Arc() => null,
    _ => math.pi * r * r,
  };
}

double? _angleDegrees(Vec2? a, Vec2? vertex, Vec2? c) {
  if (a == null || vertex == null || c == null) {
    return null;
  }
  final u = a - vertex;
  final v = c - vertex;
  if (u.normSquared == 0 || v.normSquared == 0) {
    return null;
  }
  final cosine = u.dot(v) / (u.norm * v.norm);
  return math.acos(cosine.clamp(-1.0, 1.0)) * _degPerRad;
}

double _polygonPerimeter(List<Vec2> vertices) {
  var sum = 0.0;
  for (var i = 0; i < vertices.length; i++) {
    sum += vertices[i].distanceTo(vertices[(i + 1) % vertices.length]);
  }
  return sum;
}
