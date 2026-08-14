import 'dart:math' as math;

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
      expect(branch.motion, 0);
      expect(branch.matchedIndex, -1);
    });

    test('allowComplexCarriers is arc-scoped: reset by seed and clear', () {
      final branch = TracedBranch()..seed(ProjPoint.real(1, 2, 1));
      expect(branch.allowComplexCarriers, isFalse);
      branch.allowComplexCarriers = true;
      branch.clear();
      expect(branch.allowComplexCarriers, isFalse);
      branch.allowComplexCarriers = true;
      branch.seed(ProjPoint.real(1, 2, 1));
      expect(branch.allowComplexCarriers, isFalse);
    });

    test('seed without candidates leaves separation unconstrained; with '
        'candidates it records their minimum pairwise distance', () {
      final bare = TracedBranch()..seed(ProjPoint.real(0, 0, 1));
      expect(bare.separation, double.infinity);

      // (1,0,1) vs (−1,0,1): join (0,−2,0), norms 2·2 — distance exactly 1.
      final seededWith = TracedBranch()
        ..seed(ProjPoint.real(0, 0, 1), candidates: [
          ProjPoint.real(1, 0, 1),
          ProjPoint.real(-1, 0, 1),
        ]);
      expect(seededWith.separation, 1.0);
    });

    test('hasCandidates tracks the last candidate set: true after a '
        'candidate-ful seed or follow, false after coast or a bare seed, '
        'and checkpoint/restore round-trips it (Phase 116b)', () {
      final branch = TracedBranch()..seed(ProjPoint.real(0, 0, 1));
      expect(branch.hasCandidates, isFalse);

      branch.seed(
        ProjPoint.real(0, 0, 1),
        candidates: [ProjPoint.real(1, 0, 1)],
      );
      expect(branch.hasCandidates, isTrue);

      final matching = branch.checkpoint();
      expect(matching.hasCandidates, isTrue);

      branch.coast();
      expect(branch.hasCandidates, isFalse);

      branch.restore(matching);
      expect(branch.hasCandidates, isTrue);

      branch.coast();
      branch.follow([ProjPoint.real(2, 0, 1)]);
      expect(branch.hasCandidates, isTrue);
    });

    test('clear deactivates; a re-seed starts fresh', () {
      final branch = TracedBranch()..seed(ProjPoint.real(1, 2, 1));
      branch.follow([ProjPoint.real(3, 4, 1)]);
      branch.clear();
      expect(branch.isActive, isFalse);
      branch.seed(ProjPoint.real(7, 8, 1));
      expect(branch.root, ProjPoint.real(7, 8, 1));
      expect(branch.motion, 0);
      expect(branch.matchedIndex, -1);
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

  group('TracedBranch.follow', () {
    test('matches the nearest candidate, stores it, and records the '
        'bookkeeping the step controller reads', () {
      final branch = TracedBranch()..seed(ProjPoint.real(1, 2, 1));
      final matched = branch.follow([
        ProjPoint.real(5, -5, 1),
        ProjPoint.real(1.01, 2.02, 1),
      ]);
      expect(matched, ProjPoint.real(1.01, 2.02, 1));
      expect(branch.root, matched);
      expect(branch.matchedIndex, 1);
      expect(branch.motion, greaterThan(0));
      expect(branch.motion, lessThan(0.01));
      expect(branch.separation, greaterThan(0.5));
    });

    test('an exact hit has zero motion; a single candidate has infinite '
        'separation (one root cannot swap with anything)', () {
      final branch = TracedBranch()..seed(ProjPoint.real(3, 4, 1));
      branch.follow([ProjPoint.real(3, 4, 1)]);
      expect(branch.motion, 0);
      expect(branch.matchedIndex, 0);
      expect(branch.separation, double.infinity);
    });

    test('separation is the minimum over all candidate pairs', () {
      final branch = TracedBranch()..seed(ProjPoint.real(1, 0, 0));
      branch.follow([
        ProjPoint.real(1, 0, 0),
        ProjPoint.real(0, 1, 0),
        ProjPoint.real(0, 1, 1e-3),
      ]);
      // The two nearby candidates dominate: distance ≈ 1e-3, far below
      // their unit distances to the first.
      expect(branch.separation, closeTo(1e-3, 1e-6));
      expect(branch.matchedIndex, 0);
    });

    Glados2(any.projPoint, any.nonZeroComplex).test(
      'motion and separation are invariant under rescaling the candidates',
      (p, k) {
        final candidates = [
          ProjPoint.real(4, 1, 1),
          p.scaledBy(const Complex(0.5, 2)),
          ProjPoint.real(-3, 2, 1),
        ];
        final branch = TracedBranch()..seed(p);
        branch.follow(candidates);
        final motion = branch.motion;
        final separation = branch.separation;

        final rescaled = TracedBranch()..seed(p);
        rescaled.follow([for (final c in candidates) c.scaledBy(k)]);
        expect(rescaled.matchedIndex, branch.matchedIndex);
        expect(rescaled.motion, closeTo(motion, 1e-9 + motion * 1e-9));
        if (separation.isFinite) {
          expect(
            rescaled.separation,
            closeTo(separation, 1e-9 + separation * 1e-9),
          );
        } else {
          expect(rescaled.separation, double.infinity);
        }
      },
    );
  });

  group('TracedBranch.coast', () {
    test('keeps the root, zeroes motion, and lifts the separation '
        'constraint for the re-acquisition step', () {
      final branch = TracedBranch()
        ..seed(ProjPoint.real(0, 0, 1), candidates: [
          ProjPoint.real(1, 0, 1),
          ProjPoint.real(-1, 0, 1),
        ]);
      branch.follow([ProjPoint.real(1, 0, 1), ProjPoint.real(-1, 0, 1)]);
      branch.coast();
      expect(branch.root, ProjPoint.real(1, 0, 1));
      expect(branch.motion, 0);
      expect(branch.matchedIndex, -1);
      expect(branch.separation, double.infinity);
      expect(branch.isActive, isTrue);
    });
  });

  group('TracedBranch checkpoint/restore', () {
    test('restore rolls root and bookkeeping back to the checkpoint', () {
      final branch = TracedBranch()
        ..seed(ProjPoint.real(0, 0, 1), candidates: [
          ProjPoint.real(1, 0, 1),
          ProjPoint.real(-1, 0, 1),
        ]);
      branch.follow([ProjPoint.real(0.1, 0, 1), ProjPoint.real(-1, 0, 1)]);
      final root = branch.root;
      final motion = branch.motion;
      final separation = branch.separation;
      final matchedIndex = branch.matchedIndex;
      final state = branch.checkpoint();
      expect(state.separation, separation);

      branch.follow([ProjPoint.real(0.5, 0.5, 1)]);
      expect(branch.root, isNot(root));
      branch.restore(state);
      expect(branch.root, root);
      expect(branch.motion, motion);
      expect(branch.separation, separation);
      expect(branch.matchedIndex, matchedIndex);
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

  group('TracedBranch motion measure', () {
    test('motion equals the chordal distance between the old root and the '
        'matched candidate', () {
      final branch = TracedBranch()..seed(ProjPoint.real(0, 0, 1));
      const candidate = ProjPoint(Complex(3, 0), Complex.zero, Complex.one);
      branch.follow(const [candidate]);
      // join((0,0,1),(3,0,1)) = (0,3,0) — norm2 9 over 1·10.
      expect(branch.motion, closeTo(math.sqrt(9 / 10), 1e-15));
      expect(
        branch.motion,
        TracedBranch.chordalDistance(
          ProjPoint.real(0, 0, 1),
          ProjPoint.real(3, 0, 1),
        ),
      );
    });
  });

  group('TracedBranch.chordalDistance', () {
    test('hand value, symmetry, zero on projectively equal points', () {
      final p = ProjPoint.real(0, 0, 1);
      final q = ProjPoint.real(3, 0, 1);
      expect(
        TracedBranch.chordalDistance(p, q),
        closeTo(math.sqrt(9 / 10), 1e-15),
      );
      expect(
        TracedBranch.chordalDistance(q, p),
        TracedBranch.chordalDistance(p, q),
      );
      expect(
        TracedBranch.chordalDistance(q, q.scaledBy(const Complex(0.5, 2))),
        0,
      );
    });

    Glados2(any.projPoint, any.nonZeroComplex).test(
      'is invariant under rescaling either argument',
      (p, k) {
        final q = ProjPoint.real(4, 1, 1);
        final d = TracedBranch.chordalDistance(p, q);
        expect(
          TracedBranch.chordalDistance(p.scaledBy(k), q),
          closeTo(d, 1e-9 + d * 1e-9),
        );
        expect(
          TracedBranch.chordalDistance(p, q.scaledBy(k)),
          closeTo(d, 1e-9 + d * 1e-9),
        );
      },
    );
  });
}
