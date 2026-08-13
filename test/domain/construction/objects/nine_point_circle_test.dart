import 'package:glados/glados.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/nine_point_circle.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/complex.dart';
import 'package:regula/domain/projective/conic_matrix.dart';
import 'package:regula/domain/projective/proj_line.dart';
import 'package:regula/domain/projective/proj_point.dart';

import '../../../projective_stubs.dart';
import '../../projective/generators.dart';

void main() {
  group('NinePointCircle', () {
    test('3-4-5 right triangle: center (1, 0.75), radius 1.25', () {
      // Circumcenter (2, 1.5) — the hypotenuse midpoint — and orthocenter
      // (0, 0) — the right-angle vertex; the nine-point circle sits halfway
      // between them at half the circumradius.
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final c = FreePoint(id: 'c', position: const Vec2(0, 3));
      final k = NinePointCircle(id: 'k', vertex1: a, vertex2: b, vertex3: c);
      expect(k.circle!.center.closeTo(const Vec2(1, 0.75)), isTrue);
      expect(k.circle!.radius, closeTo(1.25, 1e-9));
      expect(k.parents, [a, b, c]);
    });

    test('passes through the three side midpoints', () {
      final a = FreePoint(id: 'a', position: const Vec2(-1, 2));
      final b = FreePoint(id: 'b', position: const Vec2(5, 0));
      final c = FreePoint(id: 'c', position: const Vec2(2, 7));
      final k = NinePointCircle(id: 'k', vertex1: a, vertex2: b, vertex3: c);
      final circle = k.circle!;
      final midpoints = [
        (a.position + b.position) / 2,
        (b.position + c.position) / 2,
        (c.position + a.position) / 2,
      ];
      for (final m in midpoints) {
        expect(circle.center.distanceTo(m), closeTo(circle.radius, 1e-9));
      }
    });

    test('drag through collinearity: undefined, then recovers', () {
      final construction = Construction();
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final c = FreePoint(id: 'c', position: const Vec2(0, 3));
      final k = NinePointCircle(id: 'k', vertex1: a, vertex2: b, vertex3: c);
      construction
        ..add(a)
        ..add(b)
        ..add(c)
        ..add(k);

      construction.moveFreePoint('c', const Vec2(2, 0));
      expect(k.isDefined, isFalse);
      expect(k.circle, isNull);

      construction.moveFreePoint('c', const Vec2(0, 3));
      expect(k.isDefined, isTrue);
      expect(k.circle!.center.closeTo(const Vec2(1, 0.75)), isTrue);
    });

    test('coincident points are collinear, so undefined', () {
      final a = FreePoint(id: 'a', position: const Vec2(1, 1));
      final b = FreePoint(id: 'b', position: const Vec2(1, 1));
      final c = FreePoint(id: 'c', position: const Vec2(4, 5));
      final k = NinePointCircle(id: 'k', vertex1: a, vertex2: b, vertex3: c);
      expect(k.isDefined, isFalse);
    });
  });

  group('projective semantics (Phase 109)', () {
    Glados3(any.vec2, any.vec2, any.vec2).test(
      'the conic passes through the three side midpoints',
      (p, q, r) {
        final k = NinePointCircle(
          id: 'k',
          vertex1: FreePoint(id: 'a', position: p),
          vertex2: FreePoint(id: 'b', position: q),
          vertex3: FreePoint(id: 'c', position: r),
        );
        final conic = k.conic;
        if (conic == null) {
          return; // Coincident vertices are guarded to fully undefined.
        }
        expect(conic.evaluate(circularPointI), Complex.zero);
        expect(conic.evaluate(circularPointJ), Complex.zero);
        for (final (u, v) in [(p, q), (q, r), (p, r)]) {
          expect(conic.containsPoint(ProjPoint.lift(u.lerp(v, 0.5))), isTrue);
        }
      },
    );

    Glados3(any.nonZeroComplex, any.nonZeroComplex, any.nonZeroComplex).test(
      'recompute is invariant under complex rescaling of vertices',
      (s1, s2, s3) {
        final a = StubProjectivePoint(ProjPoint.real(0, 0), id: 'a');
        final b = StubProjectivePoint(ProjPoint.real(4, 0), id: 'b');
        final c = StubProjectivePoint(ProjPoint.real(0, 3), id: 'c');
        final k = NinePointCircle(id: 'k', vertex1: a, vertex2: b, vertex3: c);
        final reference = k.conic!;
        a.value = a.value!.scaledBy(s1);
        b.value = b.value!.scaledBy(s2);
        c.value = c.value!.scaledBy(s3);
        k.recompute();
        expect(k.conic!.closeTo(reference), isTrue);
        // Right triangle at the origin: circumcenter (2, 1.5), orthocenter
        // (0, 0) — nine-point center (1, 0.75), radius half of 2.5.
        expect(k.circle!.center.closeTo(const Vec2(1, 0.75), 1e-9), isTrue);
        expect(k.circle!.radius, closeTo(1.25, 1e-9));
      },
    );

    test('collinear vertices carry the degenerate midline conic (V2)', () {
      final k = NinePointCircle(
        id: 'k',
        vertex1: FreePoint(id: 'a', position: const Vec2(0, 0)),
        vertex2: FreePoint(id: 'b', position: const Vec2(2, 1)),
        vertex3: FreePoint(id: 'c', position: const Vec2(6, 3)),
      );
      expect(k.isDefined, isFalse);
      expect(k.circle, isNull);
      // The side midpoints lie on the vertices' own line y = x/2.
      expect(
        k.conic!.closeTo(
          ConicMatrix.linePair(ProjLine.real(1, -2, 0), ProjLine.infinity),
        ),
        isTrue,
      );
    });
  });
}
