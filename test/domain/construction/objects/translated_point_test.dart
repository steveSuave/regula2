import 'package:glados/glados.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/point_on_object.dart';
import 'package:regula/domain/construction/objects/translated_point.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/proj_point.dart';

import '../../../projective_stubs.dart';
import '../../projective/generators.dart';

void main() {
  group('TranslatedPoint', () {
    test('translates by the vector on construction', () {
      final p = FreePoint(id: 'p', position: const Vec2(1, 2));
      final from = FreePoint(id: 'f', position: const Vec2(0, 0));
      final to = FreePoint(id: 't', position: const Vec2(3, -1));
      final r = TranslatedPoint(
        id: 'r',
        point: p,
        vectorFrom: from,
        vectorTo: to,
      );
      expect(r.position, const Vec2(4, 1));
      expect(r.parents, [p, from, to]);
    });

    test('image minus point equals the vector, also after drags', () {
      final p = FreePoint(id: 'p', position: const Vec2(-2, 5));
      final from = FreePoint(id: 'f', position: const Vec2(1, 1));
      final to = FreePoint(id: 't', position: const Vec2(4, -2));
      final r = TranslatedPoint(
        id: 'r',
        point: p,
        vectorFrom: from,
        vectorTo: to,
      );
      expect(r.position! - p.position, to.position - from.position);

      to.position = const Vec2(-6, 3);
      r.recompute();
      expect(r.position! - p.position, to.position - from.position);

      p.position = const Vec2(9, 9);
      r.recompute();
      expect(r.position! - p.position, to.position - from.position);
    });

    test('coincident vector points give the zero translation', () {
      final p = FreePoint(id: 'p', position: const Vec2(1, 2));
      final from = FreePoint(id: 'f', position: const Vec2(3, 3));
      final to = FreePoint(id: 't', position: const Vec2(3, 3));
      final r = TranslatedPoint(
        id: 'r',
        point: p,
        vectorFrom: from,
        vectorTo: to,
      );
      expect(r.isDefined, isTrue);
      expect(r.position, const Vec2(1, 2));
    });

    test('undefined while a parent is, recovers after', () {
      final a = FreePoint(id: 'a', position: Vec2.zero);
      final b = FreePoint(id: 'b', position: Vec2.zero); // coincident
      final line = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
      final onLine = PointOnObject(id: 'q', curve: line, parameter: 1);
      final p = FreePoint(id: 'p', position: const Vec2(1, 1));
      final from = FreePoint(id: 'f', position: const Vec2(0, 0));
      final r = TranslatedPoint(
        id: 'r',
        point: p,
        vectorFrom: from,
        vectorTo: onLine,
      );
      expect(r.isDefined, isFalse);

      b.position = const Vec2(0, 2); // onLine comes back at (0, 1)
      line.recompute();
      onLine.recompute();
      r.recompute();
      expect(r.isDefined, isTrue);
      expect(r.position, const Vec2(1, 2));
    });
  });

  group('projective semantics (Phase 108)', () {
    test('a translation fixes a point at infinity, marked as such', () {
      final r = TranslatedPoint(
        id: 'r',
        point: StubProjectivePoint(ProjPoint.real(1, 2, 0)),
        vectorFrom: FreePoint(id: 'f', position: const Vec2(0, 0)),
        vectorTo: FreePoint(id: 't', position: const Vec2(3, -1)),
      );
      expect(r.isDefined, isFalse);
      expect(r.position, isNull);
      final image = r.projPoint!;
      expect(image.isReal(), isTrue);
      expect(image.isFinite(), isFalse);
      expect(image.closeTo(ProjPoint.real(1, 2, 0)), isTrue);
    });

    test('a vector endpoint at infinity sends a finite point to that '
        'direction at infinity, marked as such', () {
      final r = TranslatedPoint(
        id: 'r',
        point: FreePoint(id: 'p', position: const Vec2(5, 6)),
        vectorFrom: FreePoint(id: 'f', position: const Vec2(1, 2)),
        vectorTo: StubProjectivePoint(ProjPoint.real(3, 4, 0)),
      );
      expect(r.isDefined, isFalse);
      final image = r.projPoint!;
      expect(image.isReal(), isTrue);
      expect(image.isFinite(), isFalse);
      expect(image.closeTo(ProjPoint.real(3, 4, 0)), isTrue);
    });

    Glados3(any.vec2, any.vec2, any.nonZeroComplex).test(
      'recompute is invariant under complex rescaling of a parent',
      (p, delta, k) {
        TranslatedPoint build(ProjPoint point, ProjPoint from, ProjPoint to) =>
            TranslatedPoint(
              id: 'r',
              point: StubProjectivePoint(point),
              vectorFrom: StubProjectivePoint(from),
              vectorTo: StubProjectivePoint(to),
            );
        final lifted = ProjPoint.lift(p);
        final from = ProjPoint.real(1, -2);
        final to = ProjPoint.lift(delta);
        final plain = build(lifted, from, to);
        expect(
          build(
            lifted.scaledBy(k),
            from,
            to,
          ).projPoint!.closeTo(plain.projPoint!),
          isTrue,
        );
        expect(
          build(
            lifted,
            from.scaledBy(k),
            to,
          ).projPoint!.closeTo(plain.projPoint!),
          isTrue,
        );
        expect(
          build(
            lifted,
            from,
            to.scaledBy(k),
          ).projPoint!.closeTo(plain.projPoint!),
          isTrue,
        );
      },
    );
  });
}
