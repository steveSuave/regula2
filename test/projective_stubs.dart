import 'package:regula/domain/construction/geo_object.dart';
import 'package:regula/domain/math/circle_eq.dart';
import 'package:regula/domain/math/line_eq.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/conic_matrix.dart';
import 'package:regula/domain/projective/conic_shape.dart';
import 'package:regula/domain/projective/proj_line.dart';
import 'package:regula/domain/projective/proj_point.dart';

/// Test-only parents whose projective views are set directly — for
/// exercising migrated kinds (Phase 107+) with inputs the real object
/// graph cannot produce yet: points at infinity, complex-rescaled
/// homogeneous coordinates. The affine views are the standard projections,
/// so the stubs behave exactly like migrated kinds.
class StubProjectivePoint extends GeoPoint {
  StubProjectivePoint(this.value, {super.id = 'stub-point'});

  ProjPoint? value;

  @override
  ProjPoint? get projPoint => value;

  @override
  Vec2? get position => value?.toVec2();

  @override
  List<GeoObject> get parents => const [];

  @override
  void recompute() {}
}

/// The line sibling of [StubProjectivePoint].
class StubProjectiveLine extends GeoLine {
  StubProjectiveLine(this.value, {super.id = 'stub-line'});

  ProjLine? value;

  @override
  ProjLine? get projLine => value;

  @override
  LineEq? get line => value?.toLineEq();

  @override
  List<GeoObject> get parents => const [];

  @override
  void recompute() {}
}

/// The circle sibling of [StubProjectivePoint] (Phase 109): a parent
/// whose conic is set directly — for exercising kinds that consume
/// [GeoCircle.conic] with complex-rescaled or degenerate carriers.
class StubProjectiveCircle extends GeoCircle {
  StubProjectiveCircle(this.value, {super.id = 'stub-circle'});

  ConicMatrix? value;

  @override
  ConicMatrix? get conic => value;

  @override
  CircleEq? get circle => value?.toCircleEq();

  @override
  List<GeoObject> get parents => const [];

  @override
  void recompute() {}
}

/// A conic-valued stub that is *defined* whenever its conic has real ink —
/// the shape a conic kind has (Phase 120's `FivePointConic`), as opposed to
/// [StubProjectiveCircle], which is a circle kind and goes undefined the
/// moment its conic stops projecting to a centre and radius.
///
/// It exists because Phase 119 builds the painter and hit-tester arms for
/// general conics one phase before the object that produces them.
class StubProjectiveConic extends GeoCircle {
  StubProjectiveConic(this.value, {super.id = 'stub-conic'});

  ConicMatrix? value;

  @override
  ConicMatrix? get conic => value;

  @override
  CircleEq? get circle => value?.toCircleEq();

  @override
  bool get isDefined => value != null && ConicShape.of(value!).isDrawable;

  @override
  List<GeoObject> get parents => const [];

  @override
  void recompute() {}
}
