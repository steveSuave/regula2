import 'package:glados/glados.dart';
import 'package:regula/domain/projective/complex.dart';
import 'package:regula/domain/projective/proj_point.dart';
import 'package:regula/domain/projective/tracing/traced_branch.dart';

import '../generators.dart';

void main() {
  group('TracedBranch slot', () {
    test('seed activates and the root round-trips the SoA buffer exactly', () {
      final branch = TracedBranch();
      expect(branch.isActive, isFalse);
      const p = ProjPoint(
        Complex(1.5, -2.5),
        Complex(0, 3.125),
        Complex(-4, 1e-12),
      );
      branch.seed(p);
      expect(branch.isActive, isTrue);
      expect(branch.root, p);
    });

    test('update replaces the root, clear deactivates and keeps nothing', () {
      final branch = TracedBranch()..seed(ProjPoint.real(1, 2, 1));
      branch.update(ProjPoint.real(3, 4, 1));
      expect(branch.root, ProjPoint.real(3, 4, 1));
      branch.clear();
      expect(branch.isActive, isFalse);
      branch.seed(ProjPoint.real(7, 8, 1));
      expect(branch.root, ProjPoint.real(7, 8, 1));
    });

    test('seed throws on the zero triple', () {
      expect(
        () => TracedBranch().seed(const ProjPoint(
          Complex.zero,
          Complex.zero,
          Complex.zero,
        )),
        throwsArgumentError,
      );
    });
  });

  group('TracedBranch.nearestIndexAmong', () {
    test('picks the projectively nearest candidate', () {
      final branch = TracedBranch()..seed(ProjPoint.real(1, 2, 1));
      expect(
        branch.nearestIndexAmong([
          ProjPoint.real(5, -5, 1),
          ProjPoint.real(1.01, 2.02, 1),
          ProjPoint.real(-1, 2, 1),
        ]),
        1,
      );
    });

    test('distinguishes conjugate mates by their imaginary side', () {
      // The tracked root sits just below the real axis; its continuation
      // must match the -i mate, never the +i one.
      final branch = TracedBranch()
        ..seed(ProjPoint(const Complex(2, -3.9), Complex.zero, Complex.one));
      final candidates = [
        ProjPoint(const Complex(2.1, -4), Complex.zero, Complex.one),
        ProjPoint(const Complex(2.1, 4), Complex.zero, Complex.one),
      ];
      expect(branch.nearestIndexAmong(candidates), 0);
      expect(branch.nearestIndexAmong(candidates.reversed.toList()), 1);
    });

    Glados2(any.projPoint, any.nonZeroComplex).test(
      'is invariant under rescaling candidates and root',
      (p, k) {
        final branch = TracedBranch()..seed(p);
        final candidates = [
          ProjPoint.real(4, 1, 1),
          p.scaledBy(const Complex(0.5, 2)),
          ProjPoint.real(-3, 2, 1),
        ];
        final index = branch.nearestIndexAmong(candidates);
        final rescaled = [for (final c in candidates) c.scaledBy(k)];
        expect(branch.nearestIndexAmong(rescaled), index);
        final rescaledRoot = TracedBranch()..seed(p.scaledBy(k));
        expect(rescaledRoot.nearestIndexAmong(candidates), index);
      },
    );

    test('ties break to the lower index', () {
      final branch = TracedBranch()..seed(ProjPoint.real(0, 0, 1));
      expect(
        branch.nearestIndexAmong([
          ProjPoint.real(1, 0, 1),
          ProjPoint.real(-1, 0, 1),
        ]),
        0,
      );
    });
  });
}
