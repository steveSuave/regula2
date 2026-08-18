import 'dart:math' as math;

import 'package:glados/glados.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/rotated_point.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/absolute.dart';
import 'package:regula/domain/projective/ck_measure.dart';
import 'package:regula/domain/projective/proj_point.dart';

import '../../../projective_stubs.dart';
import '../../projective/generators.dart';

void main() {
  group('RotatedPoint', () {
    test('rotates counter-clockwise around the center on construction', () {
      final p = FreePoint(id: 'p', position: const Vec2(1, 0));
      final c = FreePoint(id: 'c', position: const Vec2(0, 0));
      final r = RotatedPoint(id: 'r', point: p, center: c, angle: math.pi / 2);
      expect(r.position!.closeTo(const Vec2(0, 1), 1e-12), isTrue);
      expect(r.parents, [p, c]);
    });

    test('rotation is about the center, not the origin', () {
      final p = FreePoint(id: 'p', position: const Vec2(4, 1));
      final c = FreePoint(id: 'c', position: const Vec2(3, 1));
      final r = RotatedPoint(id: 'r', point: p, center: c, angle: math.pi / 2);
      expect(r.position!.closeTo(const Vec2(3, 2), 1e-12), isTrue);
    });

    test('preserves the distance to the center, also after drags', () {
      final p = FreePoint(id: 'p', position: const Vec2(5, -2));
      final c = FreePoint(id: 'c', position: const Vec2(-1, 3));
      final r = RotatedPoint(id: 'r', point: p, center: c, angle: 0.75);
      expect(
        r.position!.distanceTo(c.position),
        closeTo(p.position.distanceTo(c.position), 1e-9),
      );

      p.position = const Vec2(-7, 0.5);
      r.recompute();
      expect(
        r.position!.distanceTo(c.position),
        closeTo(p.position.distanceTo(c.position), 1e-9),
      );
    });

    test('angle 0 is the identity, opposite angles cancel', () {
      final p = FreePoint(id: 'p', position: const Vec2(2, 7));
      final c = FreePoint(id: 'c', position: const Vec2(-3, 1));
      expect(
        RotatedPoint(id: 'r0', point: p, center: c, angle: 0).position,
        p.position,
      );
      final forth = RotatedPoint(id: 'rf', point: p, center: c, angle: 1.2);
      final back = RotatedPoint(id: 'rb', point: forth, center: c, angle: -1.2);
      expect(back.position!.closeTo(p.position, 1e-9), isTrue);
    });

    test('a point at the center is its own image', () {
      final p = FreePoint(id: 'p', position: const Vec2(1, 1));
      final c = FreePoint(id: 'c', position: const Vec2(1, 1));
      final r = RotatedPoint(id: 'r', point: p, center: c, angle: 2);
      expect(r.isDefined, isTrue);
      expect(r.position!.closeTo(const Vec2(1, 1), 1e-12), isTrue);
    });

    test('tracks a moved center after recompute', () {
      final p = FreePoint(id: 'p', position: const Vec2(1, 0));
      final c = FreePoint(id: 'c', position: const Vec2(0, 0));
      final r = RotatedPoint(id: 'r', point: p, center: c, angle: math.pi);
      c.position = const Vec2(2, 0);
      r.recompute();
      expect(r.position!.closeTo(const Vec2(3, 0), 1e-12), isTrue);
    });
  });

  group('projective semantics (Phase 108)', () {
    test('a point at infinity rotates to the turned direction at infinity, '
        'marked as such — the center does not matter there', () {
      final r = RotatedPoint(
        id: 'r',
        point: StubProjectivePoint(ProjPoint.real(1, 0, 0)),
        center: FreePoint(id: 'c', position: const Vec2(3, -1)),
        angle: math.pi / 2,
      );
      expect(r.isDefined, isFalse);
      expect(r.position, isNull);
      final image = r.projPoint!;
      expect(image.isReal(), isTrue);
      expect(image.isFinite(), isFalse);
      expect(image.closeTo(ProjPoint.real(0, 1, 0)), isTrue);
    });

    group('under a proper absolute (Phase 127)', () {
      RotatedPoint rotated(Vec2 p, Vec2 c, double angle) => RotatedPoint(
        id: 'r',
        point: FreePoint(id: 'p', position: p),
        center: FreePoint(id: 'c', position: c),
        angle: angle,
      );

      test('an interior centre rotates, where Phase 125 refused', () {
        // The deferral was on the grounds that the pencil through a
        // general centre is not uniformly circular. True of centres
        // *outside* the absolute; the pencil through an interior point
        // misses the dual conic entirely, so its angle measure is
        // elliptic and the rotation is as circular as a Euclidean one.
        final r = rotated(const Vec2(0.5, 0), const Vec2(0.1, 0), 0.6);
        r.recompute(Absolute.hyperbolic);
        expect(r.isDefined, isTrue);
        expect(r.position, isNotNull);
      });

      test('and it is not the Euclidean answer', () {
        final euclidean = rotated(const Vec2(0.5, 0), const Vec2(0.1, 0), 0.6);
        final hyperbolic = rotated(const Vec2(0.5, 0), const Vec2(0.1, 0), 0.6)
          ..recompute(Absolute.hyperbolic);
        expect(
          hyperbolic.position!.closeTo(euclidean.position!, 1e-6),
          isFalse,
          reason: '${hyperbolic.position} vs ${euclidean.position}',
        );
      });

      test('the image stays on its hyperbolic orbit', () {
        // The claim that makes it a rotation rather than a map that
        // merely moves: every image is the same CK distance from the
        // centre as the subject, which no wrong scale or chart artefact
        // survives.
        const centre = Vec2(0.1, -0.2);
        const subject = Vec2(0.45, 0.3);
        final radius = distanceBetween(
          Absolute.hyperbolic,
          ProjPoint.lift(centre),
          ProjPoint.lift(subject),
        )!;
        for (final angle in [0.3, 1.4, -2.2, 3.9]) {
          final r = rotated(subject, centre, angle)
            ..recompute(Absolute.hyperbolic);
          expect(
            distanceBetween(
              Absolute.hyperbolic,
              ProjPoint.lift(centre),
              r.projPoint!,
            )!,
            closeTo(radius, 1e-9),
            reason: 'angle $angle left the orbit',
          );
        }
      });

      test('a centre outside the absolute is undefined, not approximated', () {
        // A boost, whose parameter is a rapidity rather than an angle —
        // so answering with `cos`/`sin` would be a different isometry,
        // not an approximate one.
        final r = rotated(const Vec2(0.5, 0), const Vec2(2, 0), 0.6);
        r.recompute(Absolute.hyperbolic);
        expect(r.projPoint, isNull);
        expect(r.isDefined, isFalse);
      });

      test('a centre on the absolute is undefined too — parabolic', () {
        final r = rotated(const Vec2(0.5, 0), const Vec2(1, 0), 0.6);
        r.recompute(Absolute.hyperbolic);
        expect(r.projPoint, isNull);
      });

      test('elliptic rotates about any real centre', () {
        for (final centre in [
          const Vec2(0, 0),
          const Vec2(0.4, 0.4),
          const Vec2(3, -7),
        ]) {
          final r = rotated(const Vec2(0.5, 0), centre, 0.6);
          r.recompute(Absolute.elliptic);
          expect(r.projPoint, isNotNull, reason: '$centre');
        }
      });

      test('the Euclidean answer is untouched by any of this', () {
        final r = rotated(const Vec2(1, 0), Vec2.zero, math.pi / 2);
        expect(r.position!.closeTo(const Vec2(0, 1), 1e-12), isTrue);
        r.recompute(Absolute.euclidean);
        expect(r.position!.closeTo(const Vec2(0, 1), 1e-12), isTrue);
      });
    });

    Glados3(any.vec2, any.vec2, any.nonZeroComplex).test(
      'recompute is invariant under complex rescaling of a parent',
      (p, c, k) {
        RotatedPoint build(ProjPoint point, ProjPoint center) => RotatedPoint(
          id: 'r',
          point: StubProjectivePoint(point),
          center: StubProjectivePoint(center),
          angle: 0.7,
        );
        final plain = build(ProjPoint.lift(p), ProjPoint.lift(c));
        final scaledPoint = build(
          ProjPoint.lift(p).scaledBy(k),
          ProjPoint.lift(c),
        );
        final scaledCenter = build(
          ProjPoint.lift(p),
          ProjPoint.lift(c).scaledBy(k),
        );
        expect(scaledPoint.projPoint!.closeTo(plain.projPoint!), isTrue);
        expect(scaledCenter.projPoint!.closeTo(plain.projPoint!), isTrue);
      },
    );
  });
}
