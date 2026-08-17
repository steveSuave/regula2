import '../math/angle_geometry.dart';
import '../math/circle_eq.dart';
import '../math/line_eq.dart';
import '../math/vec2.dart';
import '../projective/conic_matrix.dart';
import '../projective/proj_line.dart';
import '../projective/proj_point.dart';
import 'object_attributes.dart';

/// Base of every object in the construction graph.
///
/// The hierarchy is sealed at the *kind* level: every object is a
/// [GeoPoint], a [GeoLine], a [GeoCircle], a [GeoAngle], a [GeoPolygon],
/// a [GeoMeasurement], a [GeoLocus] or a [GeoText], so kind-switches are
/// exhaustive.
/// The kinds themselves are open — concrete objects
/// (`FreePoint`, `Midpoint`, …) live one-per-file under `objects/`,
/// which Dart's `sealed` would forbid on the root class directly.
///
/// Derived objects are pure functions of their [parents]: [recompute]
/// re-reads the parents' current state and updates this object's cached
/// geometry. The `Construction` DAG guarantees parents are recomputed
/// first (insertion order is a topological order).
///
/// An object can be *undefined* ([isDefined] is false) when its parents
/// are in a degenerate configuration — coincident points defining a line,
/// circles that stopped intersecting mid-drag. Undefined objects stay in
/// the graph and come back to life when the degeneracy passes; consumers
/// (painter, hit tester) must skip them while undefined.
sealed class GeoObject {
  GeoObject({required this.id, ObjectAttributes? attributes})
    : attributes = attributes ?? const ObjectAttributes();

  /// Stable unique id; referenced by the save format and dependents lookup.
  final String id;

  /// Display attributes. Mutable, but only via `ChangeAttributesCommand`.
  ObjectAttributes attributes;

  /// The objects this one is derived from, in construction order.
  /// Empty for free points. Fixed for the object's lifetime.
  List<GeoObject> get parents;

  /// Whether the object currently has valid geometry (see class doc).
  bool get isDefined;

  /// Recomputes this object's geometry from its parents' current state.
  ///
  /// Must be cheap, must not throw on degenerate input — degeneracy makes
  /// the object undefined instead.
  void recompute();
}

/// A point-valued object. [position] is null while undefined — for a
/// migrated kind that means "not real and finite": the projective value
/// exists, but projects outside the affine chart (see [projPoint]).
abstract class GeoPoint extends GeoObject {
  GeoPoint({required super.id, super.attributes});

  Vec2? get position;

  /// The point in homogeneous coordinates — the canonical V2 view (PLAN
  /// §Migration strategy). New domain code reads this, never [position].
  ///
  /// Abstract since Phase 121. Through the migration this carried a
  /// default that lifted [position] to `[x, y, 1]`, which was right for a
  /// kind whose affine kernel could only produce real finite values —
  /// and is now a trap: every kind stores homogeneous state, so a new
  /// one that forgot to would silently inherit a fallback instead of
  /// failing to compile. A kind implements this and reimplements
  /// [position] as its projection ([ProjPoint.toVec2]), which is what
  /// makes [isDefined] the rendering question "real and finite?".
  ProjPoint? get projPoint;

  @override
  bool get isDefined => position != null;
}

/// A line-valued object (infinite lines, rays, segments share the carrier
/// [line] for intersection math). [line] is null while undefined — for a
/// migrated kind that means "not real, or the line at infinity": the
/// projective carrier exists but has no affine implicit form (see
/// [projLine]).
abstract class GeoLine extends GeoObject {
  GeoLine({required super.id, super.attributes});

  LineEq? get line;

  /// The carrier in homogeneous coefficients — the canonical V2 view
  /// (PLAN §Migration strategy). New domain code reads this, never [line].
  ///
  /// Abstract since Phase 121 — see [GeoPoint.projPoint] for why the
  /// lift-from-affine default went. A kind stores homogeneous state,
  /// implements this, and reimplements [line] as its projection
  /// ([ProjLine.toLineEq]); real-extent metadata ([parameterExtent])
  /// stays affine either way.
  ProjLine? get projLine;

  /// The parameter span of the carrier this object actually occupies, in
  /// the carrier's arc-length parameterization (`LineEq.parameterAt`), as
  /// `(min, max)` — a null bound is unbounded on that side. Null when the
  /// whole carrier is available: infinite lines always, `Segment` and
  /// `Ray` only while undefined. The line sibling of
  /// [GeoCircle.angularExtent], so constrained points and locus sweeps
  /// stay on the drawn extent instead of the infinite carrier.
  (double?, double?)? get parameterExtent => null;

  /// Clamps a carrier parameter into [parameterExtent]: [t] itself when
  /// the whole carrier is available or the extent already contains it,
  /// otherwise the nearer extent bound.
  double clampParameter(double t) {
    final extent = parameterExtent;
    if (extent == null) {
      return t;
    }
    final (min, max) = extent;
    if (min != null && t < min) {
      return min;
    }
    if (max != null && t > max) {
      return max;
    }
    return t;
  }

  @override
  bool get isDefined => line != null;
}

/// A circle-valued object. [circle] is null while undefined — for a
/// migrated kind that means "not a real circle": the conic exists but does
/// not project to a center-and-radius form (see [conic]).
abstract class GeoCircle extends GeoObject {
  GeoCircle({required super.id, super.attributes});

  CircleEq? get circle;

  /// The carrier as a projective conic — the canonical V2 view (PLAN
  /// §Migration strategy). New domain code reads this, never [circle].
  ///
  /// Abstract since Phase 121 — see [GeoPoint.projPoint] for why the
  /// lift-from-affine default went. A kind stores a [ConicMatrix],
  /// implements this, and reimplements [circle] as its projection
  /// ([ConicMatrix.toCircleEq]); angular-extent metadata
  /// ([angularExtent]) stays affine either way.
  ConicMatrix? get conic;

  /// The angular span of the carrier this object actually occupies, as
  /// `(start, sweep)` with a counter-clockwise sweep in [0, 2π) — or null
  /// when the whole turn is available. Full circles are always null;
  /// `Arc` and `Sector` override with their drawn extent (null while
  /// undefined), so constrained points and locus sweeps stay on the
  /// visible branch instead of roaming the full carrier.
  (double, double)? get angularExtent => null;

  /// Clamps a carrier angle into [angularExtent]: [angle] itself when the
  /// extent is the whole turn or already contains it, otherwise the
  /// angularly nearer extent endpoint.
  double clampAngle(double angle) {
    final extent = angularExtent;
    if (extent == null) {
      return angle;
    }
    final (start, sweep) = extent;
    if (ccwSweep(start, angle) <= sweep) {
      return angle;
    }
    final end = start + sweep;
    return angularDistance(angle, start) <= angularDistance(angle, end)
        ? start
        : end;
  }

  @override
  bool get isDefined => circle != null;
}

/// Orients [projected] — the affine projection of a migrated line's
/// carrier — so its [LineEq.direction] points along [direction].
///
/// A projective line has no orientation, but the V1 affine views do
/// (`throughPoints` runs p1→p2, `pointDirection` runs along its argument),
/// and downstream consumers are load-bearing on them until Phase 116:
/// `intersections.dart` branch orderings, bisector sign conventions,
/// ray/segment parameter extents. Migrated kinds re-anchor the V1
/// convention here when projecting. A null [direction] (no V1 precedent —
/// e.g. a parent at infinity, where V1 had no line at all) returns
/// [projected] unchanged.
LineEq? orientedAlong(LineEq? projected, Vec2? direction) {
  if (projected == null || direction == null) {
    return projected;
  }
  return projected.direction.dot(direction) >= 0
      ? projected
      : LineEq(-projected.a, -projected.b, -projected.c);
}

/// An angle-valued object: a marker at a vertex plus a readable measure
/// ([AngleGeometry.measure]). Angles take part in no intersection math —
/// they are decorations over existing geometry. [angle] is null while
/// undefined.
abstract class GeoAngle extends GeoObject {
  GeoAngle({required super.id, super.attributes});

  AngleGeometry? get angle;

  @override
  bool get isDefined => angle != null;
}

/// A polygon-valued object: a filled region bounded by the closed loop
/// of [polygonVertices]. Polygons take part in no intersection math —
/// like angles they decorate existing geometry rather than carrying any.
/// A collinear or self-intersecting loop is still *defined* (it is a
/// drawable outline); [polygonVertices] is null only while a vertex is
/// undefined.
abstract class GeoPolygon extends GeoObject {
  GeoPolygon({required super.id, super.attributes});

  List<Vec2>? get polygonVertices;

  @override
  bool get isDefined => polygonVertices != null;
}

/// A measurement: a live number ([value]) displayed as canvas text at
/// [anchor]. Measurements carry no drawable geometry and take part in no
/// intersection math — the text rides the label machinery, so dragging,
/// font-size presets and color styling come free. Both payloads are null
/// while undefined.
abstract class GeoMeasurement extends GeoObject {
  GeoMeasurement({required super.id, super.attributes});

  double? get value;

  /// World position the measurement's text hangs from.
  Vec2? get anchor;

  @override
  bool get isDefined => value != null && anchor != null;
}

/// A text: user content displayed as canvas text at a fixed world
/// [anchor] (the placing tap), with any `{…}` expression slots evaluated
/// live against the referenced parents ([renderedText] carries the
/// substituted result). Texts carry no drawable geometry and take part in
/// no intersection math — like measurements, the text rides the label
/// machinery. A text whose references go degenerate stays *defined*
/// (undefined slots render as `?`): user-authored content must not vanish
/// mid-drag.
abstract class GeoText extends GeoObject {
  GeoText({required super.id, super.attributes});

  String? get renderedText;

  /// World position the text hangs from. Set at creation; moved only by
  /// `MoveTextAnchorCommand` (body-dragging a text repositions the text
  /// itself — never the geometry its expressions reference).
  Vec2 get anchor;

  @override
  bool get isDefined => renderedText != null;
}

/// A locus: the sampled trace of a point as a driver sweeps its host
/// curve, drawn as a polyline. Loci take part in no intersection math —
/// like polygons they are derived pictures over existing geometry.
/// Null entries in [samples] mark gaps where the traced point was
/// undefined at that sample; [samples] itself is null only while the
/// locus is undefined (the driver's host has no geometry to sweep).
abstract class GeoLocus extends GeoObject {
  GeoLocus({required super.id, super.attributes});

  List<Vec2?>? get samples;

  /// Bounded positions for viewport fitting and label anchoring: a line
  /// host sweeps its whole carrier (Phase 39f), so [samples] can reach
  /// astronomically far out along diverging arms — fitting or anchoring
  /// on those would throw the viewport or label past any useful zoom.
  /// Concrete loci override this with the defined positions traced from
  /// the sweep's focus window; the default is every defined sample.
  /// Null exactly while [samples] is.
  List<Vec2>? get coreSamples => switch (samples) {
    null => null,
    final s => [for (final p in s) ?p],
  };

  @override
  bool get isDefined => samples != null;
}
