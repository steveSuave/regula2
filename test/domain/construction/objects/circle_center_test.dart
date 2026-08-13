import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/construction/objects/circle_center.dart';
import 'package:regula/domain/construction/objects/circle_center_point.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/sector.dart';
import 'package:regula/domain/construction/objects/three_point_circle.dart';
import 'package:regula/domain/math/circle_eq.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/complex.dart';
import 'package:regula/domain/projective/conic_matrix.dart';
import 'package:regula/domain/projective/proj_line.dart';

import '../../../projective_stubs.dart';

void main() {
  group('CircleCenter', () {
    test('computes the parent circle center on construction', () {
      final a = FreePoint(id: 'a', position: const Vec2(2, 1));
      final b = FreePoint(id: 'b', position: const Vec2(5, 1));
      final circle = CircleCenterPoint(id: 'c', center: a, onCircle: b);
      final center = CircleCenter(id: 'cc', circle: circle);
      expect(center.position, const Vec2(2, 1));
      expect(center.parents, [circle]);
    });

    test('tracks a moved parent after recompute', () {
      final a = FreePoint(id: 'a', position: const Vec2(2, 1));
      final b = FreePoint(id: 'b', position: const Vec2(5, 1));
      final circle = CircleCenterPoint(id: 'c', center: a, onCircle: b);
      final center = CircleCenter(id: 'cc', circle: circle);
      a.position = const Vec2(-3, 4);
      circle.recompute();
      center.recompute();
      expect(center.position, const Vec2(-3, 4));
    });

    test('an arc-like parent yields the carrier circle center', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(1, 0));
      final c = FreePoint(id: 'c', position: const Vec2(0, 1));
      final sector = Sector(id: 's', center: a, start: b, end: c);
      final center = CircleCenter(id: 'cc', circle: sector);
      expect(center.position, const Vec2(0, 0));
    });

    test('undefined parent makes the center undefined', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(1, 0));
      final c = FreePoint(id: 'c', position: const Vec2(2, 0));
      final circle = ThreePointCircle(
        id: 'tpc',
        point1: a,
        point2: b,
        point3: c,
      );
      final center = CircleCenter(id: 'cc', circle: circle);
      expect(circle.isDefined, isFalse, reason: 'collinear points');
      expect(center.isDefined, isFalse);
      expect(center.position, isNull);
    });
  });

  group('projective semantics (Phase 109)', () {
    test('reads the center as the pole of the line at infinity, invariant '
        'under complex rescaling of the carrier', () {
      final parent = StubProjectiveCircle(
        ConicMatrix.lift(CircleEq(const Vec2(2, 1), 5)),
      );
      final center = CircleCenter(id: 'cc', circle: parent);
      expect(center.position, const Vec2(2, 1));
      parent.value = parent.value!.scaledBy(const Complex(-0.5, 3));
      center.recompute();
      expect(center.position!.closeTo(const Vec2(2, 1), 1e-9), isTrue);
    });

    test('a degenerate line-pair carrier has no center', () {
      final parent = StubProjectiveCircle(
        ConicMatrix.linePair(ProjLine.real(1, -2, 3), ProjLine.infinity),
      );
      final center = CircleCenter(id: 'cc', circle: parent);
      expect(center.isDefined, isFalse);
      expect(center.projPoint, isNull);
    });
  });
}
