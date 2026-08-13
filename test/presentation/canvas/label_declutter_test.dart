import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:regula/presentation/canvas/label_declutter.dart';

void main() {
  const canvas = Rect.fromLTWH(0, 0, 800, 600);
  const size = Size(40, 16);
  const defaultOffset = Offset(6, -18);

  LabelBox label(
    String id, {
    Offset anchor = const Offset(100, 100),
    Offset offset = defaultOffset,
  }) => LabelBox(id: id, anchor: anchor, size: size, offset: offset);

  Map<String, Offset> solve({
    List<LabelBox> labels = const [],
    List<RectObstacle> rects = const [],
    List<Capsule> capsules = const [],
  }) => declutterLabels(
    labels: labels,
    rects: rects,
    capsules: capsules,
    canvas: canvas,
  );

  group('segmentLengthInRect', () {
    const rect = Rect.fromLTRB(10, 10, 30, 30);

    test('fully inside: full length', () {
      expect(
        segmentLengthInRect(const Offset(12, 20), const Offset(28, 20), rect),
        closeTo(16, 1e-9),
      );
    });

    test('crossing: the clipped stretch', () {
      expect(
        segmentLengthInRect(const Offset(0, 20), const Offset(40, 20), rect),
        closeTo(20, 1e-9),
      );
    });

    test('outside and degenerate: zero', () {
      expect(
        segmentLengthInRect(const Offset(0, 40), const Offset(40, 40), rect),
        0,
      );
      expect(
        segmentLengthInRect(const Offset(0, 0), const Offset(0, 0), rect),
        0,
      );
    });
  });

  test('clean label is left alone', () {
    expect(solve(labels: [label('a')]), isEmpty);
  });

  test('default placement grazing its own stroke is left alone', () {
    // A horizontal segment through the anchor: the default rect's bottom
    // touches the stroke band edge-on, which must not read as overlap.
    expect(
      solve(
        labels: [label('a')],
        capsules: const [
          Capsule(Offset(60, 100), Offset(140, 100), 2, ownerId: 'a'),
        ],
      ),
      isEmpty,
    );
  });

  test('label across a foreign stroke moves clear, within the max radius', () {
    const capsule = Capsule(Offset(0, 90), Offset(800, 90), 2, ownerId: 'x');
    final moved = solve(labels: [label('a')], capsules: const [capsule]);
    expect(moved, contains('a'));
    final offset = moved['a']!;
    expect(offset.distance, lessThanOrEqualTo(40 + 1e-9));
    final rect = label('a').rectAt(offset);
    expect(
      segmentLengthInRect(capsule.a, capsule.b, rect),
      0,
      reason: 'relocated rect must not lie across the stroke',
    );
  });

  test('label inside its own angle wedge escapes the sweep', () {
    // Spokes and rim of a 90° marker opening up-right on screen (world
    // CCW from east to north), radius 28 at the vertex — the anchor.
    const vertex = Offset(100, 100);
    final tips = [
      for (var i = 0; i <= 3; i++)
        vertex +
            Offset(
              28 * math.cos(i * math.pi / 6),
              -28 * math.sin(i * math.pi / 6),
            ),
    ];
    final wedge = [
      for (final tip in tips) Capsule(vertex, tip, 2, ownerId: 'a'),
      for (var i = 0; i < tips.length - 1; i++)
        Capsule(tips[i], tips[i + 1], 2, ownerId: 'a'),
    ];
    final moved = solve(labels: [label('a')], capsules: wedge);
    expect(moved, contains('a'));
    final rect = label('a').rectAt(moved['a']!);
    for (final capsule in wedge) {
      expect(
        segmentLengthInRect(capsule.a, capsule.b, rect),
        0,
        reason: 'relocated rect must clear the whole marker',
      );
    }
  });

  test('coincident labels separate and the result is deterministic', () {
    final labels = [label('a'), label('b')];
    final moved = solve(labels: labels);
    expect(moved, isNotEmpty);
    final rects = [for (final l in labels) l.rectAt(moved[l.id] ?? l.offset)];
    final overlap = rects[0].intersect(rects[1]);
    expect(
      overlap.width <= 0 || overlap.height <= 0,
      isTrue,
      reason: 'separated labels must not overlap',
    );
    for (final offset in moved.values) {
      expect(offset.distance, lessThanOrEqualTo(40 + 1e-9));
    }
    expect(solve(labels: [label('a'), label('b')]), moved);
  });

  test('everything covered: least-bad placement, no churn on re-run', () {
    // A dense grid of strokes with no clear pocket within reach.
    final grid = [
      for (var y = 0; y <= 600; y += 10)
        Capsule(
          Offset(0, y.toDouble()),
          Offset(800, y.toDouble()),
          2,
          ownerId: 'x',
        ),
    ];
    final moved = solve(labels: [label('a')], capsules: grid);
    for (final offset in moved.values) {
      expect(offset.distance, lessThanOrEqualTo(40 + 1e-9));
    }
    expect(solve(labels: [label('a')], capsules: grid), moved);
  });

  test('rect obstacle overlap triggers a move', () {
    const obstacle = RectObstacle(Rect.fromLTWH(100, 70, 60, 40), ownerId: 'x');
    final moved = solve(labels: [label('a')], rects: const [obstacle]);
    expect(moved, contains('a'));
    final rect = label('a').rectAt(moved['a']!);
    final overlap = rect.intersect(obstacle.rect);
    expect(overlap.width <= 0 || overlap.height <= 0, isTrue);
  });

  test('label hanging off the canvas is pulled inside', () {
    final moved = solve(labels: [label('a', anchor: const Offset(5, 5))]);
    expect(moved, contains('a'));
    final rect = label('a', anchor: const Offset(5, 5)).rectAt(moved['a']!);
    expect(canvas.contains(rect.topLeft), isTrue);
    expect(canvas.contains(rect.bottomRight), isTrue);
  });

  test('label with an off-canvas anchor is never moved', () {
    const capsule = Capsule(Offset(-90, -10), Offset(-10, -10), 2);
    expect(
      solve(
        labels: [label('a', anchor: const Offset(-50, -10))],
        capsules: const [capsule],
      ),
      isEmpty,
    );
  });
}
