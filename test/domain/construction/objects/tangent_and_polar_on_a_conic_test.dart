import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/construction/objects/bifocal_conic.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/polar_line.dart';
import 'package:regula/domain/construction/objects/tangent_line.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/conic_matrix.dart';
import 'package:regula/domain/projective/proj_point.dart';
import 'package:regula/domain/projective/tolerances.dart';

/// `TangentLine` and `PolarLine` take a **conic**, not just a circle.
///
/// Both are polar constructions on the parent's conic matrix — the polar
/// is `A·p` verbatim, and the tangents are the polars of the touch points
/// — so neither has ever needed the parent to be circular. Nothing said
/// so: their parent field is named `circle`, their docs speak of circles,
/// and every test used one. The toolbar and shortcut labels now promise
/// "point and conic", which is what this pins.
void main() {
  // A genuine ellipse: distinct foci, so it is not a circle.
  late FreePoint focus1;
  late FreePoint focus2;
  late FreePoint through;
  late BifocalConic ellipse;

  setUp(() {
    focus1 = FreePoint(id: 'f1', position: const Vec2(-3, 0));
    focus2 = FreePoint(id: 'f2', position: const Vec2(3, 0));
    through = FreePoint(id: 't', position: const Vec2(0, 4));
    ellipse = BifocalConic(
      id: 'e',
      focus1: focus1,
      focus2: focus2,
      point: through,
      difference: false,
    );
  });

  test('the parent really is a non-circular conic', () {
    expect(ellipse.isDefined, isTrue);
    expect(ellipse.conic, isNotNull);
    // The affine circle view is null exactly because it is not a circle —
    // which is what makes every assertion below about conics, not circles.
    expect(ellipse.circle, isNull);
  });

  test('the polar of an external pole is a real line, and poles on the '
      'conic polarize to the tangent there', () {
    final pole = FreePoint(id: 'p', position: const Vec2(10, 0));
    final polar = PolarLine(id: 'pl', point: pole, circle: ellipse);
    expect(polar.isDefined, isTrue);
    expect(polar.projLine, isNotNull);

    // A pole *on* the conic: its polar is the tangent at that point, so
    // the point lies on its own polar (La Hire).
    final on = FreePoint(id: 'q', position: const Vec2(0, 4));
    final atPoint = PolarLine(id: 'pl2', point: on, circle: ellipse);
    expect(atPoint.isDefined, isTrue);
    expect(
      atPoint.projLine!.contains(on.projPoint, 1e-9),
      isTrue,
      reason: 'a point on the conic lies on its own polar',
    );
  });

  test('both tangents from an external point touch the ellipse, and pass '
      'through the point', () {
    final pole = FreePoint(id: 'p', position: const Vec2(10, 0));
    final touches = <ProjPoint>[];
    for (final branch in [0, 1]) {
      final tangent = TangentLine(
        id: 'tan$branch',
        point: pole,
        circle: ellipse,
        branch: branch,
      );
      expect(tangent.isDefined, isTrue, reason: 'branch $branch');
      expect(
        tangent.projLine!.contains(pole.projPoint, 1e-9),
        isTrue,
        reason: 'branch $branch passes through the pole',
      );

      // Tangency: the line meets the conic in a *double* root.
      final meets = intersectLineConic(tangent.projLine!, ellipse.conic!);
      expect(meets, hasLength(2));
      expect(
        meets[0].closeTo(meets[1], doubleRootEpsilon),
        isTrue,
        reason: 'branch $branch meets the ellipse twice at one point',
      );
      touches.add(meets[0]);
    }
    // Two different tangents, not the same one twice.
    expect(touches[0].closeTo(touches[1], doubleRootEpsilon), isFalse);

    // Projected at the *double-root* tolerance, not the predicate default:
    // a double root is only ~sqrt(machine eps) accurate, so its imaginary
    // part is ~1e-8 of pure noise (this is what `intersectionCandidates`
    // snaps away with `_realSnapped`).
    final a = touches[0].toVec2(doubleRootEpsilon)!;
    final b = touches[1].toVec2(doubleRootEpsilon)!;
    // Ellipse x^2/25 + y^2/16 = 1, pole at (10, 0): the chord of contact
    // is the polar x = 25/10, and the touch points mirror in y.
    expect(a.x, closeTo(2.5, 1e-6));
    expect(b.x, closeTo(2.5, 1e-6));
    expect(a.y, closeTo(-b.y, 1e-6));
    expect(a.y.abs(), closeTo(4 * math.sqrt(1 - 6.25 / 25), 1e-6));
  });

  test('a pole strictly inside has no real tangents, and still has a '
      'polar — except at the centre, which polarizes to the line at '
      'infinity', () {
    final inside = FreePoint(id: 'p', position: const Vec2(1, 0));
    for (final branch in [0, 1]) {
      final tangent = TangentLine(
        id: 'tan$branch',
        point: inside,
        circle: ellipse,
        branch: branch,
      );
      // The touch points are complex, so the carrier is a complex line:
      // honestly undefined for rendering rather than absent.
      expect(tangent.isDefined, isFalse, reason: 'branch $branch');
    }
    final polar = PolarLine(id: 'pl', point: inside, circle: ellipse);
    expect(polar.isDefined, isTrue, reason: 'the polar is defined inside');

    // The conic's centre is the pole of the line at infinity, so its own
    // polar is that line: a real carrier with no affine view, which reads
    // undefined rather than absent.
    final centre = FreePoint(id: 'o', position: Vec2.zero);
    final atCentre = PolarLine(id: 'pl0', point: centre, circle: ellipse);
    expect(atCentre.projLine, isNotNull);
    expect(atCentre.line, isNull);
    expect(atCentre.isDefined, isFalse);
  });
}
