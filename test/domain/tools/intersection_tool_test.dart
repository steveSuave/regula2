import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/commands/add_object_command.dart';
import 'package:regula/domain/construction/geo_object.dart';
import 'package:regula/domain/construction/object_attributes.dart';
import 'package:regula/domain/construction/objects/angle_bisector_line.dart';
import 'package:regula/domain/construction/objects/circle_center_point.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/intersection_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/midpoint.dart';
import 'package:regula/domain/construction/objects/segment.dart';
import 'package:regula/domain/construction/objects/two_line_bisector_line.dart';
import 'package:regula/domain/construction/objects/vertex_angle.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/tools/intersection_tool.dart';
import 'package:regula/domain/tools/tool.dart';

void main() {
  late int nextId;
  late FreePoint o;
  late FreePoint x;
  late FreePoint y;

  IntersectionTool tool() => IntersectionTool(newId: () => 'n${nextId++}');

  /// Unit circle around the origin (radius |ox| = 4).
  CircleCenterPoint circleAtOrigin() =>
      CircleCenterPoint(id: 'k', center: o, onCircle: x);

  setUp(() {
    nextId = 0;
    o = FreePoint(id: 'o', position: Vec2.zero);
    x = FreePoint(id: 'x', position: const Vec2(4, 0));
    y = FreePoint(id: 'y', position: const Vec2(0, 4));
  });

  IntersectionPoint committedPoint(ToolResult result) {
    expect(result, isA<ToolCommitted>());
    final command = (result as ToolCommitted).command;
    return (command as AddObjectCommand).object as IntersectionPoint;
  }

  group('IntersectionTool', () {
    test('two lines commit one IntersectionPoint, parents in tap order', () {
      final horizontal = LineThroughTwoPoints(id: 'h', point1: o, point2: x);
      final vertical = LineThroughTwoPoints(id: 'v', point1: o, point2: y);
      final t = tool();

      expect(
        t.onInput(ToolInput(const Vec2(2, 0.1), hit: horizontal)),
        isA<ToolAccepted>(),
      );
      final point = committedPoint(
        t.onInput(ToolInput(const Vec2(0.1, 2), hit: vertical)),
      );

      expect(point.parents, [horizontal, vertical]);
      expect(point.branchIndex, 0);
      expect(point.position!.closeTo(Vec2.zero), isTrue);
    });

    test('line ∩ circle: the branch nearest the second tap wins', () {
      // The horizontal line cuts the radius-4 circle at (±4, 0).
      final horizontal = LineThroughTwoPoints(id: 'h', point1: o, point2: x);
      final circle = circleAtOrigin();

      final near = committedPoint(
        (tool()..onInput(ToolInput(const Vec2(1, 0), hit: horizontal))).onInput(
          ToolInput(const Vec2(3.5, 0.2), hit: circle),
        ),
      );
      final far = committedPoint(
        (tool()..onInput(ToolInput(const Vec2(1, 0), hit: horizontal))).onInput(
          ToolInput(const Vec2(-3.5, 0.2), hit: circle),
        ),
      );

      expect(near.position!.closeTo(const Vec2(4, 0)), isTrue);
      expect(far.position!.closeTo(const Vec2(-4, 0)), isTrue);
      expect(near.branchIndex != far.branchIndex, isTrue);
    });

    test('circle-first tap order still lands the branch nearest the tap', () {
      // Same construction as above, curves picked in the other order —
      // the line's branch role is fixed by type, not argument order.
      final horizontal = LineThroughTwoPoints(id: 'h', point1: o, point2: x);
      final circle = circleAtOrigin();
      final t = tool()..onInput(ToolInput(const Vec2(0, 4.1), hit: circle));

      final point = committedPoint(
        t.onInput(ToolInput(const Vec2(-3.9, 0), hit: horizontal)),
      );

      expect(point.parents, [circle, horizontal]);
      expect(point.position!.closeTo(const Vec2(-4, 0)), isTrue);
    });

    test('circle ∩ circle picks the branch nearest the second tap', () {
      final circle1 = circleAtOrigin();
      final center2 = FreePoint(id: 'c2', position: const Vec2(4, 4));
      final circle2 = CircleCenterPoint(id: 'k2', center: center2, onCircle: x);
      // Radius-4 circles centered (0,0) and (4,4) meet at (4,0) and (0,4).
      final t = tool()..onInput(ToolInput(const Vec2(4, 0.1), hit: circle1));

      final point = committedPoint(
        t.onInput(ToolInput(const Vec2(3.8, 0), hit: circle2)),
      );

      expect(point.position!.closeTo(const Vec2(4, 0)), isTrue);
    });

    test('non-intersecting curves commit an undefined branch-0 point', () {
      final horizontal = LineThroughTwoPoints(id: 'h', point1: o, point2: x);
      final far = FreePoint(id: 'f', position: const Vec2(0, 10));
      final rim = FreePoint(id: 'r', position: const Vec2(1, 10));
      final circle = CircleCenterPoint(id: 'k', center: far, onCircle: rim);
      final t = tool()..onInput(ToolInput(const Vec2(1, 0), hit: horizontal));

      final point = committedPoint(
        t.onInput(ToolInput(const Vec2(1, 9), hit: circle)),
      );

      expect(point.branchIndex, 0);
      expect(point.position, isNull);
      expect(point.isDefined, isFalse);
    });

    test('non-curve taps are ignored: empty canvas, points, angles', () {
      final t = tool();
      final angle = VertexAngle(id: 'a', arm1: x, vertex: o, arm2: y);

      expect(t.onInput(const ToolInput(Vec2(9, 9))), isA<ToolIgnored>());
      expect(t.onInput(ToolInput(Vec2.zero, hit: o)), isA<ToolIgnored>());
      expect(t.onInput(ToolInput(Vec2.zero, hit: angle)), isA<ToolIgnored>());
      expect(t.previewPositions, isEmpty);
      expect(t.previewObjectIds, isEmpty);
    });

    test('the same curve twice is ignored, a segment carrier works', () {
      final circle = circleAtOrigin();
      final segment = Segment(id: 's', point1: y, point2: x);
      final t = tool()..onInput(ToolInput(const Vec2(4, 0.1), hit: circle));

      expect(
        t.onInput(ToolInput(const Vec2(-4, 0.1), hit: circle)),
        isA<ToolIgnored>(),
      );
      final point = committedPoint(
        t.onInput(ToolInput(const Vec2(0.2, 3.8), hit: segment)),
      );
      expect(point.position!.closeTo(const Vec2(0, 4)), isTrue);
    });

    test('the first curve is reported for haloing, with no marker', () {
      final horizontal = LineThroughTwoPoints(id: 'h', point1: o, point2: x);
      final t = tool()..onInput(ToolInput(const Vec2(2, 0.4), hit: horizontal));

      expect(t.previewObjectIds, ['h']);
      expect(
        t.previewPositions,
        isEmpty,
        reason: 'an existing curve is haloed, never marked',
      );
    });

    test('a first-tapped circle is haloed too', () {
      final t = tool()
        ..onInput(ToolInput(const Vec2(0, 3.5), hit: circleAtOrigin()));

      expect(t.previewObjectIds, hasLength(1));
      expect(t.previewPositions, isEmpty);
    });

    test('after committing the tool is ready for the next pair', () {
      final horizontal = LineThroughTwoPoints(id: 'h', point1: o, point2: x);
      final vertical = LineThroughTwoPoints(id: 'v', point1: o, point2: y);
      final t = tool()
        ..onInput(ToolInput(const Vec2(2, 0), hit: horizontal))
        ..onInput(ToolInput(const Vec2(0, 2), hit: vertical));

      expect(t.previewObjectIds, isEmpty);
      expect(
        t.onInput(ToolInput(const Vec2(3, 0), hit: horizontal)),
        isA<ToolAccepted>(),
        reason: 'the tool reset itself on commit',
      );
    });

    test('bisector × segment reuses the existing crossing point', () {
      // Segments ab and cd cross at (2, 0); p is that crossing and bi is
      // their wedge bisector — bi's only crossing with ab *is* p, so the
      // tap must not stack a second point on it.
      final a = FreePoint(id: 'a', position: Vec2.zero);
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final c = FreePoint(id: 'c', position: const Vec2(2, -2));
      final d = FreePoint(id: 'd', position: const Vec2(2, 2));
      final ab = Segment(id: 'ab', point1: a, point2: b);
      final cd = Segment(id: 'cd', point1: c, point2: d);
      final p = IntersectionPoint(
        curve1: ab,
        curve2: cd,
        branchIndex: 0,
        id: 'p',
      );
      final bi = TwoLineBisectorLine(id: 'bi', line1: ab, line2: cd, branch: 0);
      final objects = [a, b, c, d, ab, cd, p, bi];
      final t = tool()
        ..onInput(ToolInput(const Vec2(2.4, 0.4), hit: bi, objects: objects));

      expect(
        t.onInput(ToolInput(const Vec2(3, 0.1), hit: ab, objects: objects)),
        isA<ToolIgnored>(),
      );
      expect(t.previewObjectIds, [
        'bi',
      ], reason: 'the refused tap keeps the first curve armed');
    });

    test('bisector of two segments off one vertex reuses that vertex', () {
      // User report (inter2.json): segments ab and ac share endpoint a,
      // bi bisects their wedge — bi's only crossing with either segment
      // *is* a itself, so intersecting bi with a parent must be refused,
      // not stack a new point on a.
      final a = FreePoint(id: 'a', position: Vec2.zero);
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final c = FreePoint(id: 'c', position: const Vec2(0, 4));
      final ab = Segment(id: 'ab', point1: a, point2: b);
      final ac = Segment(id: 'ac', point1: a, point2: c);
      final bi = TwoLineBisectorLine(id: 'bi', line1: ab, line2: ac, branch: 0);
      final objects = [a, b, c, ab, ac, bi];
      final t = tool()
        ..onInput(ToolInput(const Vec2(1, 1), hit: bi, objects: objects));

      expect(
        t.onInput(ToolInput(const Vec2(2, 0.1), hit: ab, objects: objects)),
        isA<ToolIgnored>(),
      );
      expect(
        t.onInput(ToolInput(const Vec2(0.1, 2), hit: ac, objects: objects)),
        isA<ToolIgnored>(),
        reason: 'the other parent is refused too',
      );
    });

    test('three-point bisector × arm segment reuses the vertex too', () {
      final a = FreePoint(id: 'a', position: Vec2.zero);
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final c = FreePoint(id: 'c', position: const Vec2(2, -2));
      final d = FreePoint(id: 'd', position: const Vec2(2, 2));
      final ab = Segment(id: 'ab', point1: a, point2: b);
      final cd = Segment(id: 'cd', point1: c, point2: d);
      final p = IntersectionPoint(
        curve1: ab,
        curve2: cd,
        branchIndex: 0,
        id: 'p',
      );
      final bi = AngleBisectorLine(id: 'bi', arm1: b, vertex: p, arm2: d);
      final objects = [a, b, c, d, ab, cd, p, bi];
      final t = tool()
        ..onInput(ToolInput(const Vec2(2.4, 0.4), hit: bi, objects: objects));

      expect(
        t.onInput(ToolInput(const Vec2(1, 0.1), hit: ab, objects: objects)),
        isA<ToolIgnored>(),
      );
    });

    test('the same pair twice is refused, per branch', () {
      // The horizontal line cuts the radius-4 circle at (±4, 0); with the
      // (4, 0) branch already constructed only the (-4, 0) tap commits.
      final horizontal = LineThroughTwoPoints(id: 'h', point1: o, point2: x);
      final circle = circleAtOrigin();
      var objects = <GeoObject>[o, x, horizontal, circle];
      final existing = committedPoint(
        (tool()..onInput(ToolInput(const Vec2(1, 0), hit: horizontal))).onInput(
          ToolInput(const Vec2(3.9, 0.1), hit: circle),
        ),
      );
      objects = [...objects, existing];

      expect(
        (tool()..onInput(
              ToolInput(const Vec2(1, 0), hit: horizontal, objects: objects),
            ))
            .onInput(
              ToolInput(const Vec2(3.9, 0.1), hit: circle, objects: objects),
            ),
        isA<ToolIgnored>(),
        reason: 'the (4, 0) branch already exists',
      );
      final other = committedPoint(
        (tool()..onInput(
              ToolInput(const Vec2(1, 0), hit: horizontal, objects: objects),
            ))
            .onInput(
              ToolInput(const Vec2(-3.9, 0.1), hit: circle, objects: objects),
            ),
      );
      expect(other.position!.closeTo(const Vec2(-4, 0)), isTrue);
    });

    test('an occupied branch is refused even while it has no position '
        '(Phase 120c)', () {
      // Proximity can only speak for a point that has one. Pull the
      // circle clear of the line so the crossings are complex: the
      // existing branch-0 point goes undefined, and before the
      // structural test every further tap on the pair looked unoccupied
      // and stacked another object on it. Six of them piled up on one
      // conic pair in the reported document.
      final horizontal = LineThroughTwoPoints(id: 'h', point1: o, point2: x);
      final far = FreePoint(id: 'f', position: const Vec2(0, 100));
      final circle = CircleCenterPoint(id: 'k', center: far, onCircle: y);
      var objects = <GeoObject>[o, x, y, far, horizontal, circle];
      final existing = IntersectionPoint(
        id: 'e',
        curve1: horizontal,
        curve2: circle,
        branchIndex: 0,
      );
      objects = [...objects, existing];
      expect(existing.position, isNull, reason: 'the crossings are complex');

      expect(
        (tool()..onInput(
              ToolInput(const Vec2(1, 0), hit: horizontal, objects: objects),
            ))
            .onInput(
              ToolInput(const Vec2(0, 99), hit: circle, objects: objects),
            ),
        isA<ToolIgnored>(),
        reason: 'branch 0 of this pair is already built',
      );
    });

    test('the reversed parent order dedups too, defined or not '
        '(Phase 120c)', () {
      // `branchIndex` addresses the canonical order of
      // `intersectionCandidates(curve1, curve2)`, which is not the order
      // of the reversed pair — so the same crossing carries a different
      // index depending on which curve the user tapped first. Proximity
      // covered that while the crossing was real; with it complex, the
      // reversed tap built a fresh duplicate. That is how the reported
      // document came to hold points on *both* orderings, two of them
      // exact duplicates of points it already had.
      final horizontal = LineThroughTwoPoints(id: 'h', point1: o, point2: x);
      final circle = circleAtOrigin();
      var objects = <GeoObject>[o, x, horizontal, circle];
      final existing = committedPoint(
        (tool()..onInput(ToolInput(const Vec2(1, 0), hit: horizontal))).onInput(
          ToolInput(const Vec2(3.9, 0.1), hit: circle),
        ),
      );
      objects = [...objects, existing];

      expect(
        (tool()..onInput(
              ToolInput(const Vec2(1, 0), hit: circle, objects: objects),
            ))
            .onInput(
              ToolInput(const Vec2(3.9, 0.1), hit: horizontal, objects: objects),
            ),
        isA<ToolIgnored>(),
        reason: 'the same crossing, collected the other way round',
      );
      // The *other* crossing is still free in either order.
      expect(
        (tool()..onInput(
              ToolInput(const Vec2(1, 0), hit: circle, objects: objects),
            ))
            .onInput(
              ToolInput(
                const Vec2(-3.9, 0.1),
                hit: horizontal,
                objects: objects,
              ),
            ),
        isA<ToolCommitted>(),
      );
    });

    test('two lines sharing a defining point reuse that point', () {
      final horizontal = LineThroughTwoPoints(id: 'h', point1: o, point2: x);
      final vertical = LineThroughTwoPoints(id: 'v', point1: o, point2: y);
      final objects = [o, x, y, horizontal, vertical];
      final t = tool()
        ..onInput(
          ToolInput(const Vec2(2, 0), hit: horizontal, objects: objects),
        );

      expect(
        t.onInput(ToolInput(const Vec2(0, 2), hit: vertical, objects: objects)),
        isA<ToolIgnored>(),
        reason: 'o already is the crossing of both lines',
      );
    });

    test('a hidden coincident point does not block the tap', () {
      final c = FreePoint(id: 'c', position: const Vec2(2, -2));
      final d = FreePoint(id: 'd', position: const Vec2(2, 2));
      final horizontal = LineThroughTwoPoints(id: 'h', point1: o, point2: x);
      final vertical = LineThroughTwoPoints(id: 'v', point1: c, point2: d);
      final hidden = IntersectionPoint(
        curve1: horizontal,
        curve2: vertical,
        branchIndex: 0,
        id: 'p',
        attributes: const ObjectAttributes(visible: false),
      );
      final objects = [o, x, c, d, horizontal, vertical, hidden];
      final t = tool()
        ..onInput(
          ToolInput(const Vec2(1, 0), hit: horizontal, objects: objects),
        );

      final point = committedPoint(
        t.onInput(ToolInput(const Vec2(2, 1), hit: vertical, objects: objects)),
      );
      expect(point.position!.closeTo(const Vec2(2, 0)), isTrue);
    });

    test('reset clears the collected curve', () {
      final horizontal = LineThroughTwoPoints(id: 'h', point1: o, point2: x);
      final vertical = LineThroughTwoPoints(id: 'v', point1: o, point2: y);
      final t = tool()
        ..onInput(ToolInput(const Vec2(2, 0), hit: horizontal))
        ..reset();

      expect(t.previewObjectIds, isEmpty);
      expect(
        t.onInput(ToolInput(const Vec2(0, 2), hit: vertical)),
        isA<ToolAccepted>(),
        reason: 'after reset the next curve is the first input again',
      );
    });

    test('a point on the crossing by theorem refuses the tap', () {
      // The centroid, built as the crossing of two medians, sits on the
      // *third* median too — by theorem, not by incident parents, so the
      // structural check cannot see it; the numeric identity probe can.
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(6, 0));
      final c = FreePoint(id: 'c', position: const Vec2(0, 6));
      final midAB = Midpoint(id: 'mab', point1: a, point2: b);
      final midBC = Midpoint(id: 'mbc', point1: b, point2: c);
      final midAC = Midpoint(id: 'mac', point1: a, point2: c);
      final median1 = Segment(id: 'm1', point1: a, point2: midBC);
      final median2 = Segment(id: 'm2', point1: b, point2: midAC);
      final median3 = Segment(id: 'm3', point1: c, point2: midAB);
      final crossing = IntersectionPoint(
        id: 'g',
        curve1: median1,
        curve2: median2,
        branchIndex: 0,
      );
      final objects = <GeoObject>[
        a,
        b,
        c,
        midAB,
        midBC,
        midAC,
        median1,
        median2,
        median3,
        crossing,
      ];
      final t = tool();

      t.onInput(ToolInput(const Vec2(2, 2), hit: median2, objects: objects));
      expect(
        t.onInput(ToolInput(const Vec2(2, 2), hit: median3, objects: objects)),
        isA<ToolIgnored>(),
        reason: 'the medians crossing already occupies median2 ∩ median3',
      );
    });
  });
}
