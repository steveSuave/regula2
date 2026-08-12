import 'package:glados/glados.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/point_on_object.dart';
import 'package:regula/domain/construction/objects/segment_ratio_point.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/proj_point.dart';

import '../../../projective_stubs.dart';
import '../../projective/generators.dart';

void main() {
  group('SegmentRatioPoint', () {
    test('interpolates at the ratio on construction', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(4, 2));
      final p = SegmentRatioPoint(id: 'p', point1: a, point2: b, ratio: 0.25);
      expect(p.position, const Vec2(1, 0.5));
      expect(p.parents, [a, b]);
    });

    test('ratio 0 and 1 sit on the endpoints, 0.5 is the midpoint', () {
      final a = FreePoint(id: 'a', position: const Vec2(-2, 1));
      final b = FreePoint(id: 'b', position: const Vec2(6, 5));
      expect(
        SegmentRatioPoint(id: 'p0', point1: a, point2: b, ratio: 0).position,
        a.position,
      );
      expect(
        SegmentRatioPoint(id: 'p1', point1: a, point2: b, ratio: 1).position,
        b.position,
      );
      expect(
        SegmentRatioPoint(id: 'ph', point1: a, point2: b, ratio: 0.5).position,
        const Vec2(2, 3),
      );
    });

    test('ratios outside [0, 1] extrapolate beyond the endpoints', () {
      final a = FreePoint(id: 'a', position: const Vec2(1, 1));
      final b = FreePoint(id: 'b', position: const Vec2(3, 1));
      expect(
        SegmentRatioPoint(id: 'p2', point1: a, point2: b, ratio: 2).position,
        const Vec2(5, 1),
      );
      expect(
        SegmentRatioPoint(id: 'pm', point1: a, point2: b, ratio: -1).position,
        const Vec2(-1, 1),
      );
    });

    test('tracks a moved parent after recompute', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final p = SegmentRatioPoint(id: 'p', point1: a, point2: b, ratio: 0.75);
      b.position = const Vec2(0, 8);
      p.recompute();
      expect(p.position, const Vec2(0, 6));
    });

    test('coincident parents are not degenerate', () {
      final a = FreePoint(id: 'a', position: const Vec2(1, 1));
      final b = FreePoint(id: 'b', position: const Vec2(1, 1));
      final p = SegmentRatioPoint(id: 'p', point1: a, point2: b, ratio: 3);
      expect(p.isDefined, isTrue);
      expect(p.position, const Vec2(1, 1));
    });

    test('undefined while a parent is, recovers after', () {
      final a = FreePoint(id: 'a', position: Vec2.zero);
      final b = FreePoint(id: 'b', position: Vec2.zero); // coincident
      final line = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
      final onLine = PointOnObject(id: 'q', curve: line, parameter: 1);
      final anchor = FreePoint(id: 'c', position: const Vec2(0, 2));
      final p = SegmentRatioPoint(
        id: 'p',
        point1: anchor,
        point2: onLine,
        ratio: 0.5,
      );
      expect(p.isDefined, isFalse);

      b.position = const Vec2(2, 0); // line (and onLine) come back
      line.recompute();
      onLine.recompute(); // arc-length parameter 1 → (1, 0)
      p.recompute();
      expect(p.isDefined, isTrue);
      expect(p.position, const Vec2(0.5, 1));
    });
  });

  group('projective semantics (Phase 108)', () {
    test('the far endpoint at infinity: that point at infinity for a '
        'nonzero ratio, marked as such', () {
      final r = SegmentRatioPoint(
        id: 'r',
        point1: FreePoint(id: 'a', position: const Vec2(1, 2)),
        point2: StubProjectivePoint(ProjPoint.real(3, 4, 0)),
        ratio: 0.25,
      );
      expect(r.isDefined, isFalse);
      expect(r.position, isNull);
      final image = r.projPoint!;
      expect(image.isReal(), isTrue);
      expect(image.isFinite(), isFalse);
      expect(image.closeTo(ProjPoint.real(3, 4, 0)), isTrue);
    });

    test('the far endpoint at infinity with ratio 0: the bilinear form '
        'degenerates to the zero triple, undefined', () {
      final r = SegmentRatioPoint(
        id: 'r',
        point1: FreePoint(id: 'a', position: const Vec2(1, 2)),
        point2: StubProjectivePoint(ProjPoint.real(3, 4, 0)),
        ratio: 0,
      );
      expect(r.isDefined, isFalse);
      expect(r.projPoint, isNull);
    });

    Glados3(any.vec2, any.vec2, any.nonZeroComplex).test(
        'recompute is invariant under complex rescaling of a parent',
        (p, q, k) {
      SegmentRatioPoint build(ProjPoint p1, ProjPoint p2) => SegmentRatioPoint(
            id: 'r',
            point1: StubProjectivePoint(p1),
            point2: StubProjectivePoint(p2),
            ratio: 0.75,
          );
      final plain = build(ProjPoint.lift(p), ProjPoint.lift(q));
      expect(build(ProjPoint.lift(p).scaledBy(k), ProjPoint.lift(q))
          .projPoint!
          .closeTo(plain.projPoint!), isTrue);
      expect(build(ProjPoint.lift(p), ProjPoint.lift(q).scaledBy(k))
          .projPoint!
          .closeTo(plain.projPoint!), isTrue);
    });
  });
}
