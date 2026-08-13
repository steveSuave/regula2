import 'package:glados/glados.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/angle_bisector_line.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/intersection_point.dart';
import 'package:regula/domain/math/circle_eq.dart';
import 'package:regula/domain/math/line_eq.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/complex.dart';
import 'package:regula/domain/projective/conic_matrix.dart';
import 'package:regula/domain/projective/proj_point.dart';

import '../../../projective_stubs.dart';
import '../../math/generators.dart';

void main() {
  group('AngleBisectorLine', () {
    test('right angle at the origin bisects to y = x', () {
      final a = FreePoint(id: 'a', position: const Vec2(5, 0));
      final v = FreePoint(id: 'v', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(0, 5));
      final bisector = AngleBisectorLine(id: 'k', arm1: a, vertex: v, arm2: b);

      expect(bisector.parents, [a, v, b]);
      expect(
        bisector.line!.closeTo(
          LineEq.throughPoints(Vec2.zero, const Vec2(1, 1)),
        ),
        isTrue,
      );
    });

    test('arm dragged onto the vertex: undefined, then recovers', () {
      final construction = Construction();
      final a = FreePoint(id: 'a', position: const Vec2(5, 0));
      final v = FreePoint(id: 'v', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(0, 5));
      final bisector = AngleBisectorLine(id: 'k', arm1: a, vertex: v, arm2: b);
      construction
        ..add(a)
        ..add(v)
        ..add(b)
        ..add(bisector);

      construction.moveFreePoint('a', const Vec2(0, 0));
      expect(bisector.isDefined, isFalse);
      expect(bisector.line, isNull);

      construction.moveFreePoint('a', const Vec2(5, 0));
      expect(bisector.isDefined, isTrue);
      expect(bisector.line!.contains(const Vec2(1, 1)), isTrue);
    });

    test('tracks a moving vertex', () {
      final construction = Construction();
      final a = FreePoint(id: 'a', position: const Vec2(5, 0));
      final v = FreePoint(id: 'v', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(0, 5));
      final bisector = AngleBisectorLine(id: 'k', arm1: a, vertex: v, arm2: b);
      construction
        ..add(a)
        ..add(v)
        ..add(b)
        ..add(bisector);

      construction.moveFreePoint('v', const Vec2(1, 1));
      expect(bisector.line!.contains(const Vec2(1, 1)), isTrue);
      final u = (a.position - const Vec2(1, 1)).normalized();
      final w = (b.position - const Vec2(1, 1)).normalized();
      expect(
        bisector.line!.distanceTo(const Vec2(1, 1) + u),
        closeTo(bisector.line!.distanceTo(const Vec2(1, 1) + w), 1e-9),
      );
    });
  });

  group('projective semantics (Phase 110)', () {
    test('an arm at infinity contributes its direction (V1: undefined)', () {
      final bisector = AngleBisectorLine(
        id: 'k',
        arm1: StubProjectivePoint(ProjPoint.real(1, 0, 0)),
        vertex: StubProjectivePoint(ProjPoint.real(0, 0)),
        arm2: StubProjectivePoint(ProjPoint.real(0, 3)),
      );
      expect(bisector.isDefined, isTrue);
      expect(bisector.line!.closeTo(LineEq(1, -1, 0)), isTrue);
    });

    test('a complex arm view gives a complex carrier that no intersection '
        'consumes (the locus-miss phantom regression)', () {
      // The arm is an undefined intersection's conjugate branch: the
      // bisector carrier goes complex — non-null, unprojectable — and a
      // downstream intersection must NOT mine it for its one real point.
      final arm = StubProjectivePoint(
        const ProjPoint(Complex(2, 1e-4), Complex(1, -2e-4), Complex.one),
      );
      final vertex = FreePoint(id: 'v', position: const Vec2(5, 5));
      final bisector = AngleBisectorLine(
        id: 'k',
        arm1: arm,
        vertex: vertex,
        arm2: FreePoint(id: 'b', position: const Vec2(9, 5)),
      );
      expect(bisector.isDefined, isFalse);
      expect(bisector.line, isNull);
      expect(bisector.projLine, isNotNull);
      expect(bisector.projLine!.isReal(), isFalse);

      // The vertex is real and on the circle below — the complex carrier
      // passes through it, but candidates must stay empty.
      final circle = StubProjectiveCircle(
        ConicMatrix.lift(CircleEq(const Vec2(5, 3), 2)),
      );
      expect(intersectionCandidates(bisector, circle), isEmpty);
      final x = IntersectionPoint(
        id: 'x',
        curve1: bisector,
        curve2: circle,
        branchIndex: 0,
      );
      expect(x.isDefined, isFalse);
      expect(x.projPoint, isNull);
      expect(x.candidateCount, 0);
    });

    Glados3(any.coordinate, any.coordinate, any.vec2).test(
      'complex rescaling of the parent views leaves the bisector invariant '
      '(chart-canonical selection)',
      (re, im, shift) {
        var k = Complex(re, im);
        if (k.abs2 < 1) {
          k = k + const Complex(2, 1);
        }
        final a = ProjPoint.lift(const Vec2(5, 0) + shift);
        final v = ProjPoint.lift(shift);
        final b = ProjPoint.lift(const Vec2(0, 5) + shift);
        final baseline = AngleBisectorLine(
          id: 'k',
          arm1: StubProjectivePoint(a),
          vertex: StubProjectivePoint(v),
          arm2: StubProjectivePoint(b),
        );
        final scaled = AngleBisectorLine(
          id: 'k2',
          arm1: StubProjectivePoint(a.scaledBy(k)),
          vertex: StubProjectivePoint(v.scaledBy(k)),
          arm2: StubProjectivePoint(b.scaledBy(k)),
        );
        expect(scaled.line, isNotNull);
        expect(scaled.line!.closeTo(baseline.line!), isTrue);
        expect(
          scaled.line!.direction.dot(baseline.line!.direction),
          greaterThan(0),
          reason: 'the internal/external selection is chart-anchored',
        );
      },
    );
  });
}
