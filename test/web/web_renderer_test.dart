@TestOn('browser')
library;

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:regula/presentation/canvas/geometry_painter.dart';

/// Phase 126d: the handful of things whose answer differs between the VM
/// harness and the renderer the app actually ships on.
///
/// This file exists because a bug got all the way to a user through a
/// green suite. The hyperbolic absolute's wash is the canvas minus the
/// disc, and it was built with
/// `Path.combine(PathOperation.difference, rect, oval)` — which on the
/// **web** renderer returns the outer rect *unbroken* whenever the oval
/// lies entirely inside it, and the correct annulus as soon as any part
/// of the oval crosses an edge. So a hyperbolic document showed a
/// uniformly washed canvas with the rim floating on it, and repaired
/// itself the moment the user zoomed far enough to push the boundary off
/// screen. Every VM test was green, because `dart:ui`'s path ops on the
/// VM and CanvasKit's are different implementations.
///
/// Run with `flutter test --platform chrome`. Web is the primary target
/// (PLAN §compile target), so anything whose correctness depends on the
/// rasterizer rather than on our own arithmetic belongs here.
void main() {
  const size = Size(400, 300);

  group('a filled region with a hole in it', () {
    test('even-odd cuts the hole wherever the disc sits', () {
      // The property the app needs, stated on the real renderer. The
      // fully-contained case is the one that used to fail.
      for (final (name, centre, radius) in [
        ('fully contained', const Offset(200, 150), 80.0),
        ('touching an edge', const Offset(200, 150), 150.0),
        ('overhanging', const Offset(200, 150), 170.0),
        ('larger than the canvas', const Offset(200, 150), 600.0),
      ]) {
        final path = outsideDiscPath(size, centre, radius);
        expect(path.contains(centre), isFalse, reason: '$name: centre');
        for (var i = 0; i < 8; i++) {
          final t = i * math.pi / 4;
          final unit = Offset(math.cos(t), math.sin(t));
          final inside = centre + unit * (radius * 0.9);
          final outside = centre + unit * (radius * 1.1);
          if ((Offset.zero & size).contains(inside)) {
            expect(path.contains(inside), isFalse, reason: '$name in @$i');
          }
          if ((Offset.zero & size).contains(outside)) {
            expect(path.contains(outside), isTrue, reason: '$name out @$i');
          }
        }
      }
    });

    test('the boolean difference is why this file exists', () {
      // Kept as evidence rather than as a requirement: it documents the
      // platform behaviour that cost a release, and it fails loudly if a
      // future engine fixes it (at which point this test can go, and the
      // even-odd path stays anyway — it needs no boolean op at all).
      final byDifference = Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        Path()..addOval(
          Rect.fromCircle(center: const Offset(200, 150), radius: 80),
        ),
      );
      expect(
        byDifference.contains(const Offset(200, 150)),
        isTrue,
        reason:
            'web path-ops difference leaves no hole for a contained '
            'shape; if this now fails the engine has been fixed',
      );
    });
  });
}
