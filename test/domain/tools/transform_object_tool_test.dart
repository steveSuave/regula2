import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/commands/add_object_command.dart';
import 'package:regula/domain/commands/macro_command.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/geo_object.dart';
import 'package:regula/domain/construction/objects/apollonius_circle.dart';
import 'package:regula/domain/construction/objects/arc.dart';
import 'package:regula/domain/construction/objects/central_reflection_point.dart';
import 'package:regula/domain/construction/objects/circle_center_point.dart';
import 'package:regula/domain/construction/objects/compass_circle.dart';
import 'package:regula/domain/construction/objects/diameter_circle.dart';
import 'package:regula/domain/construction/objects/five_point_conic.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/homothetic_point.dart';
import 'package:regula/domain/construction/objects/inscribed_circle.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/nine_point_circle.dart';
import 'package:regula/domain/construction/objects/perpendicular_line.dart';
import 'package:regula/domain/construction/objects/point_on_object.dart';
import 'package:regula/domain/construction/objects/reflected_point.dart';
import 'package:regula/domain/construction/objects/rotated_point.dart';
import 'package:regula/domain/construction/objects/sector.dart';
import 'package:regula/domain/construction/objects/segment.dart';
import 'package:regula/domain/construction/objects/three_point_circle.dart';
import 'package:regula/domain/construction/objects/translated_point.dart';
import 'package:regula/domain/construction/objects/vertex_angle.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/conic_shape.dart';
import 'package:regula/domain/tools/tool.dart';
import 'package:regula/domain/tools/transform_object_tool.dart';

void main() {
  late int nextId;
  String newId() => 'n${nextId++}';

  setUp(() => nextId = 0);

  // The x-axis as a mirror, plus its defining points.
  late FreePoint m1;
  late FreePoint m2;
  late LineThroughTwoPoints xAxis;

  setUp(() {
    m1 = FreePoint(id: 'm1', position: const Vec2(0, 0));
    m2 = FreePoint(id: 'm2', position: const Vec2(4, 0));
    xAxis = LineThroughTwoPoints(id: 'x', point1: m1, point2: m2);
  });

  group('point mode (Phase 15 behavior preserved)', () {
    test('reflect: point then line, or line then point — same object', () {
      final p = FreePoint(id: 'p', position: const Vec2(1, 5));

      for (final lineFirst in [true, false]) {
        final tool = TransformObjectTool.reflectAboutLine(newId: newId);
        final inputs = [
          ToolInput(const Vec2(2, 0), hit: xAxis),
          ToolInput(p.position, hit: p),
        ];
        if (!lineFirst) {
          inputs.setAll(0, inputs.reversed.toList());
        }

        expect(tool.onInput(inputs[0]), isA<ToolAccepted>());
        final result = tool.onInput(inputs[1]);
        expect(result, isA<ToolCommitted>(), reason: 'lineFirst: $lineFirst');
        final command = (result as ToolCommitted).command;
        final image = (command as AddObjectCommand).object as ReflectedPoint;
        expect(image.parents, [p, xAxis]);
        expect(image.position!.closeTo(const Vec2(1, -5), 1e-12), isTrue);
      }
    });

    test(
      'reflect: line first + empty tap creates the point, one undo unit',
      () {
        final construction = Construction()
          ..add(m1)
          ..add(m2)
          ..add(xAxis);
        final tool = TransformObjectTool.reflectAboutLine(newId: newId);

        tool.onInput(ToolInput(const Vec2(2, 0), hit: xAxis));
        final result =
            tool.onInput(const ToolInput(Vec2(1, 5))) as ToolCommitted;

        expect(result.command, isA<MacroCommand>());
        result.command.apply(construction);
        expect(construction.length, 5, reason: 'new free point + image');
        final image = construction.objects.last as ReflectedPoint;
        expect(image.position!.closeTo(const Vec2(1, -5), 1e-12), isTrue);

        result.command.undo(construction);
        expect(construction.length, 3, reason: 'one undo unit');
      },
    );

    test('reflect: with the point slot filled, only a line commits', () {
      final p = FreePoint(id: 'p', position: const Vec2(1, 5));
      final q = FreePoint(id: 'q', position: const Vec2(2, 6));
      final circle = CircleCenterPoint(id: 'o', center: p, onCircle: q);
      final tool = TransformObjectTool.reflectAboutLine(newId: newId);

      tool.onInput(ToolInput(p.position, hit: p));
      expect(
        tool.onInput(const ToolInput(Vec2(9, 9))),
        isA<ToolIgnored>(),
        reason: 'empty canvas is a missed tap',
      );
      expect(
        tool.onInput(ToolInput(q.position, hit: q)),
        isA<ToolIgnored>(),
        reason: 'a second point is ignored',
      );
      expect(
        tool.onInput(ToolInput(const Vec2(1, 0), hit: circle)),
        isA<ToolIgnored>(),
        reason: 'a circle cannot be the mirror',
      );
      expect(
        tool.onInput(ToolInput(const Vec2(2, 0), hit: xAxis)),
        isA<ToolCommitted>(),
      );
    });

    test('reflect about point: existing point + center commit a bare add', () {
      final p = FreePoint(id: 'p', position: const Vec2(3, 1));
      final c = FreePoint(id: 'c', position: const Vec2(1, 1));
      final tool = TransformObjectTool.reflectAboutPoint(newId: newId);

      expect(tool.onInput(ToolInput(p.position, hit: p)), isA<ToolAccepted>());
      expect(
        tool.onInput(ToolInput(p.position, hit: p)),
        isA<ToolIgnored>(),
        reason: 'the same existing point twice is refused',
      );
      final result = tool.onInput(ToolInput(c.position, hit: c));

      expect(result, isA<ToolCommitted>());
      final command = (result as ToolCommitted).command;
      final image =
          (command as AddObjectCommand).object as CentralReflectionPoint;
      expect(image.parents, [p, c]);
      expect(image.position!.closeTo(const Vec2(-1, 1), 1e-12), isTrue);
    });

    test('rotate: point then center on existing points commits a bare add', () {
      final p = FreePoint(id: 'p', position: const Vec2(1, 0));
      final c = FreePoint(id: 'c', position: const Vec2(0, 0));
      final tool = TransformObjectTool.rotate(newId: newId, angle: math.pi / 2);

      expect(tool.onInput(ToolInput(p.position, hit: p)), isA<ToolAccepted>());
      final result = tool.onInput(ToolInput(c.position, hit: c));

      expect(result, isA<ToolCommitted>());
      final command = (result as ToolCommitted).command;
      final rotated = (command as AddObjectCommand).object as RotatedPoint;
      expect(rotated.parents, [p, c]);
      expect(rotated.angle, math.pi / 2);
      expect(rotated.position!.closeTo(const Vec2(0, 1), 1e-12), isTrue);
    });

    test('rotate: empty-canvas taps create free points, all one undo unit', () {
      final construction = Construction();
      final tool = TransformObjectTool.rotate(newId: newId, angle: math.pi);

      tool.onInput(const ToolInput(Vec2(3, 1)));
      final result = tool.onInput(const ToolInput(Vec2(2, 1))) as ToolCommitted;

      expect(result.command, isA<MacroCommand>());
      result.command.apply(construction);
      expect(construction.length, 3, reason: '2 free points + the rotation');
      final rotated = construction.objects.last as RotatedPoint;
      expect(rotated.position!.closeTo(const Vec2(1, 1), 1e-12), isTrue);

      result.command.undo(construction);
      expect(construction.isEmpty, isTrue);
    });

    test('translate: point, tail, tip on existing points', () {
      final p = FreePoint(id: 'p', position: const Vec2(1, 1));
      final tail = FreePoint(id: 't0', position: const Vec2(0, 0));
      final tip = FreePoint(id: 't1', position: const Vec2(2, 1));
      final tool = TransformObjectTool.translate(newId: newId);

      tool.onInput(ToolInput(p.position, hit: p));
      tool.onInput(ToolInput(tail.position, hit: tail));
      final result = tool.onInput(ToolInput(tip.position, hit: tip));

      expect(result, isA<ToolCommitted>());
      final command = (result as ToolCommitted).command;
      final image = (command as AddObjectCommand).object as TranslatedPoint;
      expect(image.parents, [p, tail, tip]);
      expect(image.position!.closeTo(const Vec2(3, 2), 1e-12), isTrue);
    });

    test('parameter taps still glue to curves (resolution ladder intact)', () {
      final p = FreePoint(id: 'p', position: const Vec2(5, 5));
      final seg = Segment(id: 's', point1: m1, point2: m2);
      final tool = TransformObjectTool.reflectAboutPoint(newId: newId);

      tool.onInput(ToolInput(p.position, hit: p));
      final result =
          tool.onInput(ToolInput(const Vec2(2, 0.1), hit: seg))
              as ToolCommitted;

      final macro = result.command as MacroCommand;
      expect(macro.commands, hasLength(2));
      final center = (macro.commands[0] as AddObjectCommand).object;
      expect(
        center,
        isA<PointOnObject>(),
        reason: 'a center tap on a curve glues, exactly like Phase 15/20',
      );
      final image = (macro.commands[1] as AddObjectCommand).object;
      expect(image, isA<CentralReflectionPoint>());
    });
  });

  group('curve mode', () {
    test('reflect a segment: same kind over mirrored visible image points, '
        'one undo unit, nothing glued', () {
      final a = FreePoint(id: 'a', position: const Vec2(1, 1));
      final b = FreePoint(id: 'b', position: const Vec2(3, 2));
      final seg = Segment(id: 's', point1: a, point2: b);
      final construction = Construction()
        ..add(m1)
        ..add(m2)
        ..add(xAxis)
        ..add(a)
        ..add(b)
        ..add(seg);
      final tool = TransformObjectTool.reflectAboutLine(newId: newId);

      expect(
        tool.onInput(ToolInput(const Vec2(2, 1.5), hit: seg)),
        isA<ToolAccepted>(),
      );
      final result =
          tool.onInput(ToolInput(const Vec2(2, 0), hit: xAxis))
              as ToolCommitted;

      final macro = result.command as MacroCommand;
      expect(macro.commands, hasLength(3), reason: '2 image points + segment');
      macro.apply(construction);
      expect(construction.length, 9);
      expect(
        construction.objects.whereType<PointOnObject>(),
        isEmpty,
        reason: 'the transformee tap must not glue',
      );

      final image = construction.objects.last as Segment;
      final i1 = image.point1 as ReflectedPoint;
      final i2 = image.point2 as ReflectedPoint;
      expect(i1.point, a);
      expect(i2.point, b);
      expect(
        i1.attributes.visible,
        isTrue,
        reason: 'image points are usable geometry, not scaffolding',
      );
      expect(i2.attributes.visible, isTrue);
      expect(i1.position!.closeTo(const Vec2(1, -1), 1e-12), isTrue);
      expect(i2.position!.closeTo(const Vec2(3, -2), 1e-12), isTrue);

      // The image is live: dragging a source endpoint moves it.
      construction.moveFreePoint('a', const Vec2(5, 3));
      expect(i1.position!.closeTo(const Vec2(5, -3), 1e-12), isTrue);

      macro.undo(construction);
      expect(construction.length, 6, reason: 'one undo unit');
    });

    test('reflect: a line tapped first stays the mirror if a point follows '
        '(either-order), and reflecting a line across itself is refused', () {
      final p = FreePoint(id: 'p', position: const Vec2(1, 5));
      final tool = TransformObjectTool.reflectAboutLine(newId: newId);

      tool.onInput(ToolInput(const Vec2(2, 0), hit: xAxis));
      expect(
        tool.onInput(ToolInput(const Vec2(3, 0), hit: xAxis)),
        isA<ToolIgnored>(),
        reason: 'same line as transformee and mirror',
      );
      final result = tool.onInput(ToolInput(p.position, hit: p));

      expect(result, isA<ToolCommitted>());
      final command = (result as ToolCommitted).command;
      final image = (command as AddObjectCommand).object as ReflectedPoint;
      expect(image.parents, [p, xAxis]);
    });

    test('rotate a circle: radius preserved, center imaged', () {
      final cc = FreePoint(id: 'cc', position: const Vec2(1, 0));
      final rim = FreePoint(id: 'rim', position: const Vec2(2, 0));
      final circle = CircleCenterPoint(id: 'o', center: cc, onCircle: rim);
      final o = FreePoint(id: 'ctr', position: const Vec2(0, 0));
      final construction = Construction()
        ..add(cc)
        ..add(rim)
        ..add(circle)
        ..add(o);
      final tool = TransformObjectTool.rotate(newId: newId, angle: math.pi / 2);

      tool.onInput(ToolInput(const Vec2(2, 0.01), hit: circle));
      final result =
          tool.onInput(ToolInput(o.position, hit: o)) as ToolCommitted;

      (result.command as MacroCommand).apply(construction);
      final image = construction.objects.last as CircleCenterPoint;
      expect(image.circle!.radius, closeTo(1, 1e-12));
      expect(image.circle!.center.closeTo(const Vec2(0, 1), 1e-12), isTrue);
      expect(image.center, isA<RotatedPoint>());
    });

    test('translate a compass circle: all three parents imaged, radius '
        'preserved', () {
      final r1 = FreePoint(id: 'r1', position: const Vec2(0, 0));
      final r2 = FreePoint(id: 'r2', position: const Vec2(2, 0));
      final c = FreePoint(id: 'c', position: const Vec2(5, 5));
      final compass = CompassCircle(
        id: 'k',
        radiusPoint1: r1,
        radiusPoint2: r2,
        center: c,
      );
      final tip = FreePoint(id: 'tip', position: const Vec2(1, 1));
      final construction = Construction()
        ..add(r1)
        ..add(r2)
        ..add(c)
        ..add(compass)
        ..add(tip);
      final tool = TransformObjectTool.translate(newId: newId);

      tool.onInput(ToolInput(const Vec2(5, 7), hit: compass));
      tool.onInput(ToolInput(r1.position, hit: r1));
      final result =
          tool.onInput(ToolInput(tip.position, hit: tip)) as ToolCommitted;

      final macro = result.command as MacroCommand;
      expect(macro.commands, hasLength(4), reason: '3 image points + compass');
      macro.apply(construction);
      final image = construction.objects.last as CompassCircle;
      expect(image.circle!.radius, closeTo(2, 1e-12));
      expect(image.circle!.center.closeTo(const Vec2(6, 6), 1e-12), isTrue);
    });

    test('reflect a three-point circle: mirrored center, equal radius', () {
      final p1 = FreePoint(id: 'p1', position: const Vec2(0, 1));
      final p2 = FreePoint(id: 'p2', position: const Vec2(1, 2));
      final p3 = FreePoint(id: 'p3', position: const Vec2(2, 1));
      final circle = ThreePointCircle(
        id: 'o',
        point1: p1,
        point2: p2,
        point3: p3,
      );
      final construction = Construction()
        ..add(m1)
        ..add(m2)
        ..add(xAxis)
        ..add(p1)
        ..add(p2)
        ..add(p3)
        ..add(circle);
      final tool = TransformObjectTool.reflectAboutLine(newId: newId);

      tool.onInput(ToolInput(const Vec2(1, 2), hit: circle));
      final result =
          tool.onInput(ToolInput(const Vec2(2, 0), hit: xAxis))
              as ToolCommitted;

      (result.command as MacroCommand).apply(construction);
      final image = construction.objects.last as ThreePointCircle;
      expect(image.circle!.radius, closeTo(circle.circle!.radius, 1e-12));
      final sourceCenter = circle.circle!.center;
      expect(
        image.circle!.center.closeTo(
          Vec2(sourceCenter.x, -sourceCenter.y),
          1e-12,
        ),
        isTrue,
      );
    });

    test('reflect a five-point conic: the conic through the image points',
        () {
      // A similarity carries a conic to the conic through the images of
      // its points, class included — so the rebuild needs nothing beyond
      // the five image points the tool already makes.
      final points = [
        for (final (i, t) in const [0.4, 1.4, 2.4, 3.6, 5.0].indexed)
          FreePoint(
            id: 'q$i',
            position: Vec2(2 * math.cos(t), 1 + math.sin(t)),
          ),
      ];
      final conic = FivePointConic(id: 'o', points: points);
      final construction = Construction()
        ..add(m1)
        ..add(m2)
        ..add(xAxis);
      for (final point in points) {
        construction.add(point);
      }
      construction.add(conic);
      final tool = TransformObjectTool.reflectAboutLine(newId: newId);

      tool.onInput(ToolInput(points.first.position, hit: conic));
      final result =
          tool.onInput(ToolInput(const Vec2(2, 0), hit: xAxis))
              as ToolCommitted;

      (result.command as MacroCommand).apply(construction);
      final image = construction.objects.last as FivePointConic;
      expect(image.isDefined, isTrue);
      expect(
        ConicShape.of(image.conic!).kind,
        ConicShape.of(conic.conic!).kind,
      );
      final shape = ConicShape.of(image.conic!);
      for (final point in points) {
        final p = point.position;
        expect(shape.distanceTo(Vec2(p.x, -p.y)), lessThan(1e-9));
      }
    });

    test('dilate a nine-point circle: rebuilt over the image triangle', () {
      final p1 = FreePoint(id: 'p1', position: const Vec2(0, 0));
      final p2 = FreePoint(id: 'p2', position: const Vec2(4, 0));
      final p3 = FreePoint(id: 'p3', position: const Vec2(0, 3));
      final circle = NinePointCircle(
        id: 'o',
        vertex1: p1,
        vertex2: p2,
        vertex3: p3,
      );
      final o = FreePoint(id: 'ctr', position: const Vec2(0, 0));
      final construction = Construction()
        ..add(p1)
        ..add(p2)
        ..add(p3)
        ..add(circle)
        ..add(o);
      final tool = TransformObjectTool.dilate(newId: newId, ratio: 2);

      tool.onInput(ToolInput(const Vec2(1, 2), hit: circle));
      final result =
          tool.onInput(ToolInput(o.position, hit: o)) as ToolCommitted;

      (result.command as MacroCommand).apply(construction);
      final image = construction.objects.last as NinePointCircle;
      expect(image.circle!.radius, closeTo(2.5, 1e-12));
      expect(image.circle!.center.closeTo(const Vec2(2, 1.5), 1e-12), isTrue);
      expect(image.vertex1, isA<HomotheticPoint>());
    });

    test('translate an inscribed circle: rebuilt over the image triangle', () {
      final p1 = FreePoint(id: 'p1', position: const Vec2(0, 0));
      final p2 = FreePoint(id: 'p2', position: const Vec2(4, 0));
      final p3 = FreePoint(id: 'p3', position: const Vec2(0, 3));
      final circle = InscribedCircle(
        id: 'o',
        vertex1: p1,
        vertex2: p2,
        vertex3: p3,
      );
      final from = FreePoint(id: 'from', position: const Vec2(0, 0));
      final to = FreePoint(id: 'to', position: const Vec2(10, 1));
      final construction = Construction()
        ..add(p1)
        ..add(p2)
        ..add(p3)
        ..add(circle)
        ..add(from)
        ..add(to);
      final tool = TransformObjectTool.translate(newId: newId);

      tool.onInput(ToolInput(const Vec2(1, 1), hit: circle));
      tool.onInput(ToolInput(from.position, hit: from));
      final result =
          tool.onInput(ToolInput(to.position, hit: to)) as ToolCommitted;

      (result.command as MacroCommand).apply(construction);
      final image = construction.objects.last as InscribedCircle;
      expect(image.circle!.radius, closeTo(1, 1e-12));
      expect(image.circle!.center.closeTo(const Vec2(11, 2), 1e-12), isTrue);
      expect(image.vertex1, isA<TranslatedPoint>());
    });

    test('dilate an Apollonius circle: the distance ratio survives, so the '
        'image is the scaled circle', () {
      final p1 = FreePoint(id: 'p1', position: const Vec2(0, 0));
      final p2 = FreePoint(id: 'p2', position: const Vec2(3, 0));
      final p3 = FreePoint(id: 'p3', position: const Vec2(2, 0));
      final circle = ApolloniusCircle(
        id: 'o',
        point1: p1,
        point2: p2,
        point3: p3,
      );
      final o = FreePoint(id: 'ctr', position: const Vec2(0, 0));
      final construction = Construction()
        ..add(p1)
        ..add(p2)
        ..add(p3)
        ..add(circle)
        ..add(o);
      final tool = TransformObjectTool.dilate(newId: newId, ratio: 2);

      tool.onInput(ToolInput(const Vec2(2, 0), hit: circle));
      final result =
          tool.onInput(ToolInput(o.position, hit: o)) as ToolCommitted;

      // Source circle: center (4, 0), radius 2 — the image doubles both.
      (result.command as MacroCommand).apply(construction);
      final image = construction.objects.last as ApolloniusCircle;
      expect(image.circle!.radius, closeTo(4, 1e-12));
      expect(image.circle!.center.closeTo(const Vec2(8, 0), 1e-12), isTrue);
      expect(image.point1, isA<HomotheticPoint>());
    });

    test('translate a diameter circle: rebuilt over the image endpoints', () {
      final p1 = FreePoint(id: 'p1', position: const Vec2(0, 0));
      final p2 = FreePoint(id: 'p2', position: const Vec2(6, 8));
      final circle = DiameterCircle(id: 'o', point1: p1, point2: p2);
      final from = FreePoint(id: 'from', position: const Vec2(0, 0));
      final to = FreePoint(id: 'to', position: const Vec2(10, 1));
      final construction = Construction()
        ..add(p1)
        ..add(p2)
        ..add(circle)
        ..add(from)
        ..add(to);
      final tool = TransformObjectTool.translate(newId: newId);

      tool.onInput(ToolInput(const Vec2(3, 4), hit: circle));
      tool.onInput(ToolInput(from.position, hit: from));
      final result =
          tool.onInput(ToolInput(to.position, hit: to)) as ToolCommitted;

      (result.command as MacroCommand).apply(construction);
      final image = construction.objects.last as DiameterCircle;
      expect(image.circle!.radius, closeTo(5, 1e-12));
      expect(image.circle!.center.closeTo(const Vec2(13, 5), 1e-12), isTrue);
      expect(image.point1, isA<TranslatedPoint>());
    });

    test('reflect an arc: endpoints mirror, sweep flips sign (via picks the '
        'branch)', () {
      final s = FreePoint(id: 's', position: const Vec2(2, 1));
      final v = FreePoint(id: 'v', position: const Vec2(1, 2));
      final e = FreePoint(id: 'e', position: const Vec2(0, 1));
      final arc = Arc(id: 'arc', start: s, via: v, end: e);
      final construction = Construction()
        ..add(m1)
        ..add(m2)
        ..add(xAxis)
        ..add(s)
        ..add(v)
        ..add(e)
        ..add(arc);
      final tool = TransformObjectTool.reflectAboutLine(newId: newId);

      tool.onInput(ToolInput(const Vec2(1, 2), hit: arc));
      final result =
          tool.onInput(ToolInput(const Vec2(2, 0), hit: xAxis))
              as ToolCommitted;

      (result.command as MacroCommand).apply(construction);
      final image = construction.objects.last as Arc;
      expect(image.startPosition!.closeTo(const Vec2(2, -1), 1e-12), isTrue);
      expect(image.endPosition!.closeTo(const Vec2(0, -1), 1e-12), isTrue);
      expect(
        image.sweep!,
        closeTo(-arc.sweep!, 1e-12),
        reason: 'reflection reverses orientation',
      );
    });

    test('reflect a vertex angle: arms swap, so the marker measures the '
        'same wedge', () {
      final a1 = FreePoint(id: 'a1', position: const Vec2(2, 1));
      final vx = FreePoint(id: 'vx', position: const Vec2(1, 1));
      final a2 = FreePoint(id: 'a2', position: const Vec2(1, 2));
      final angle = VertexAngle(id: 'ang', arm1: a1, vertex: vx, arm2: a2);
      final construction = Construction()
        ..add(m1)
        ..add(m2)
        ..add(xAxis)
        ..add(a1)
        ..add(vx)
        ..add(a2)
        ..add(angle);
      final tool = TransformObjectTool.reflectAboutLine(newId: newId);

      tool.onInput(ToolInput(const Vec2(1, 1), hit: angle));
      final result =
          tool.onInput(ToolInput(const Vec2(2, 0), hit: xAxis))
              as ToolCommitted;

      (result.command as MacroCommand).apply(construction);
      final image = construction.objects.last as VertexAngle;
      expect(
        (image.arm1 as ReflectedPoint).point,
        a2,
        reason: 'arms swapped under the orientation-reversing transform',
      );
      expect((image.arm2 as ReflectedPoint).point, a1);
      expect(image.angle!.sweep, closeTo(angle.angle!.sweep, 1e-12));
    });

    test('rotate a vertex angle: arms keep their order, sweep unchanged', () {
      final a1 = FreePoint(id: 'a1', position: const Vec2(2, 1));
      final vx = FreePoint(id: 'vx', position: const Vec2(1, 1));
      final a2 = FreePoint(id: 'a2', position: const Vec2(1, 2));
      final angle = VertexAngle(id: 'ang', arm1: a1, vertex: vx, arm2: a2);
      final o = FreePoint(id: 'o', position: const Vec2(0, 0));
      final construction = Construction()
        ..add(a1)
        ..add(vx)
        ..add(a2)
        ..add(angle)
        ..add(o);
      final tool = TransformObjectTool.rotate(newId: newId, angle: 1);

      tool.onInput(ToolInput(const Vec2(1, 1), hit: angle));
      final result =
          tool.onInput(ToolInput(o.position, hit: o)) as ToolCommitted;

      (result.command as MacroCommand).apply(construction);
      final image = construction.objects.last as VertexAngle;
      expect((image.arm1 as RotatedPoint).point, a1);
      expect((image.arm2 as RotatedPoint).point, a2);
      expect(image.angle!.sweep, closeTo(angle.angle!.sweep, 1e-12));
    });

    test('sector: rotates fine, but reflect-about-line ignores the tap', () {
      final c = FreePoint(id: 'c', position: const Vec2(0, 0));
      final s = FreePoint(id: 's', position: const Vec2(1, 0));
      final e = FreePoint(id: 'e', position: const Vec2(0, 1));
      final sector = Sector(id: 'sec', center: c, start: s, end: e);
      final o = FreePoint(id: 'o', position: const Vec2(3, 3));
      final construction = Construction()
        ..add(c)
        ..add(s)
        ..add(e)
        ..add(sector)
        ..add(o);

      final reflect = TransformObjectTool.reflectAboutLine(newId: newId);
      expect(
        reflect.onInput(ToolInput(const Vec2(1, 0), hit: sector)),
        isA<ToolIgnored>(),
        reason:
            'rebuilding a reflected sector would give the '
            'complementary wedge — documented limitation',
      );

      final rotate = TransformObjectTool.rotate(newId: newId, angle: 1);
      rotate.onInput(ToolInput(const Vec2(1, 0), hit: sector));
      final result =
          rotate.onInput(ToolInput(o.position, hit: o)) as ToolCommitted;
      (result.command as MacroCommand).apply(construction);
      final image = construction.objects.last as Sector;
      expect(image.sweep!, closeTo(sector.sweep!, 1e-12));
      expect(image.circle!.radius, closeTo(1, 1e-12));
    });

    test('a curve with non-point parents is no transformee: ignored by '
        'rotate, but still reflect\'s mirror', () {
      final p = FreePoint(id: 'p', position: const Vec2(1, 5));
      final perp = PerpendicularLine(id: 'perp', through: m1, reference: xAxis);

      final rotate = TransformObjectTool.rotate(newId: newId, angle: 1);
      expect(
        rotate.onInput(ToolInput(const Vec2(0, 2), hit: perp)),
        isA<ToolIgnored>(),
      );
      expect(rotate.previewPositions, isEmpty);
      expect(rotate.previewObjectIds, isEmpty);

      final reflect = TransformObjectTool.reflectAboutLine(newId: newId);
      expect(
        reflect.onInput(ToolInput(const Vec2(0, 2), hit: perp)),
        isA<ToolAccepted>(),
        reason: 'any line still serves as the mirror (Phase 15 parity)',
      );
      final result = reflect.onInput(ToolInput(p.position, hit: p));
      expect(result, isA<ToolCommitted>());
      final image =
          ((result as ToolCommitted).command as AddObjectCommand).object
              as ReflectedPoint;
      expect(image.parents, [p, perp]);
    });

    test('slot 1: a point hit wins over curves in threshold', () {
      final p = FreePoint(id: 'p', position: const Vec2(0, 0));
      final seg = Segment(id: 's', point1: m1, point2: m2);
      final c = FreePoint(id: 'c', position: const Vec2(1, 1));
      final tool = TransformObjectTool.rotate(newId: newId, angle: 1);

      tool.onInput(ToolInput(p.position, hit: p, extraHits: [seg]));
      final result =
          tool.onInput(ToolInput(c.position, hit: c)) as ToolCommitted;

      expect(
        result.command,
        isA<AddObjectCommand>(),
        reason: 'point mode — the segment was never the transformee',
      );
      expect((result.command as AddObjectCommand).object, isA<RotatedPoint>());
    });

    test('curve mode with a new center: the free point joins the macro '
        'first', () {
      final a = FreePoint(id: 'a', position: const Vec2(1, 1));
      final b = FreePoint(id: 'b', position: const Vec2(3, 1));
      final seg = Segment(id: 's', point1: a, point2: b);
      final construction = Construction()
        ..add(a)
        ..add(b)
        ..add(seg);
      final tool = TransformObjectTool.rotate(newId: newId, angle: math.pi / 2);

      tool.onInput(ToolInput(const Vec2(2, 1), hit: seg));
      final result = tool.onInput(const ToolInput(Vec2(0, 0))) as ToolCommitted;

      final macro = result.command as MacroCommand;
      expect(
        macro.commands,
        hasLength(4),
        reason: 'center + 2 image points + segment',
      );
      expect(
        (macro.commands.first as AddObjectCommand).object,
        isA<FreePoint>(),
      );
      macro.apply(construction);
      final image = construction.objects.last as Segment;
      expect(image.point1.position!.closeTo(const Vec2(-1, 1), 1e-12), isTrue);
      expect(image.point2.position!.closeTo(const Vec2(-1, 3), 1e-12), isTrue);
      macro.undo(construction);
      expect(construction.length, 3, reason: 'one undo unit');
    });

    test('shared defining points image once', () {
      final p = FreePoint(id: 'p', position: const Vec2(2, 1));
      final vx = FreePoint(id: 'vx', position: const Vec2(1, 1));
      final angle = VertexAngle(id: 'ang', arm1: p, vertex: vx, arm2: p);
      final tail = FreePoint(id: 't0', position: const Vec2(0, 0));
      final tip = FreePoint(id: 't1', position: const Vec2(1, 0));
      final tool = TransformObjectTool.translate(newId: newId);

      tool.onInput(ToolInput(const Vec2(1, 1), hit: angle));
      tool.onInput(ToolInput(tail.position, hit: tail));
      final result =
          tool.onInput(ToolInput(tip.position, hit: tip)) as ToolCommitted;

      final macro = result.command as MacroCommand;
      expect(
        macro.commands,
        hasLength(3),
        reason: 'the shared arm point images once: 2 images + angle',
      );
    });

    test('previews: collected curve is haloed, reset clears all slots', () {
      final a = FreePoint(id: 'a', position: const Vec2(1, 1));
      final b = FreePoint(id: 'b', position: const Vec2(3, 1));
      final seg = Segment(id: 's', point1: a, point2: b);
      final tool = TransformObjectTool.rotate(newId: newId, angle: 1);
      expect(tool.previewPositions, isEmpty);
      expect(tool.previewObjectIds, isEmpty);

      tool.onInput(ToolInput(const Vec2(2, 5), hit: seg));
      expect(tool.previewObjectIds, ['s']);
      expect(
        tool.previewPositions,
        isEmpty,
        reason: 'an existing curve is haloed, never marked',
      );

      tool.reset();
      expect(tool.previewObjectIds, isEmpty);

      // A fresh collection still commits from scratch.
      tool.onInput(ToolInput(const Vec2(2, 1), hit: seg));
      expect(tool.onInput(const ToolInput(Vec2(0, 0))), isA<ToolCommitted>());
    });

    test('previews: existing transformee and param points are haloed, '
        'new ones marked', () {
      final p = FreePoint(id: 'p', position: const Vec2(2, 1));
      final c = FreePoint(id: 'c', position: const Vec2(0, 0));
      final existing = TransformObjectTool.translate(newId: newId);

      existing.onInput(ToolInput(p.position, hit: p));
      existing.onInput(ToolInput(c.position, hit: c));
      expect(existing.previewObjectIds, ['p', 'c']);
      expect(existing.previewPositions, isEmpty);

      final fresh = TransformObjectTool.translate(newId: newId);
      fresh.onInput(const ToolInput(Vec2(2, 1)));
      fresh.onInput(const ToolInput(Vec2(0, 0)));
      expect(
        fresh.previewPositions,
        [const Vec2(2, 1), const Vec2(0, 0)],
        reason: 'new free points are not in the construction yet',
      );
      expect(fresh.previewObjectIds, isEmpty);
    });
  });

  group('image reuse across gestures (Phase 40)', () {
    late FreePoint a;
    late FreePoint b;
    late FreePoint c;
    late FreePoint o;
    late Segment ab;
    late Segment bc;
    late Construction construction;

    setUp(() {
      a = FreePoint(id: 'a', position: const Vec2(0, 2));
      b = FreePoint(id: 'b', position: const Vec2(4, 2));
      c = FreePoint(id: 'c', position: const Vec2(4, 6));
      o = FreePoint(id: 'o', position: const Vec2(10, 10));
      ab = Segment(id: 'ab', point1: a, point2: b);
      bc = Segment(id: 'bc', point1: b, point2: c);
      construction = Construction()
        ..add(m1)
        ..add(m2)
        ..add(xAxis)
        ..add(a)
        ..add(b)
        ..add(c)
        ..add(o)
        ..add(ab)
        ..add(bc);
    });

    ToolInput tapOn(GeoObject hit, Vec2 position) =>
        ToolInput(position, hit: hit, objects: construction.objects);

    test(
      'rotating AB then BC about one center images the shared vertex once',
      () {
        final tool = TransformObjectTool.rotate(
          newId: newId,
          angle: math.pi / 2,
        );

        tool.onInput(tapOn(ab, const Vec2(2, 2)));
        final first = tool.onInput(tapOn(o, o.position)) as ToolCommitted;
        first.command.apply(construction);
        final firstImage = construction.objects.last as Segment;

        tool.onInput(tapOn(bc, const Vec2(4, 4)));
        final second = tool.onInput(tapOn(o, o.position)) as ToolCommitted;
        final macro = second.command as MacroCommand;
        expect(
          macro.commands,
          hasLength(2),
          reason: "C's image + the rebuilt segment — B's image is reused",
        );
        second.command.apply(construction);

        expect(
          construction.objects.whereType<RotatedPoint>(),
          hasLength(3),
          reason: 'the shared vertex B is imaged once, not per gesture',
        );
        final secondImage = construction.objects.last as Segment;
        expect(
          identical(secondImage.point1, firstImage.point2),
          isTrue,
          reason: 'the rebuilt segments share the one image instance',
        );
      },
    );

    test('repeating the same transform of the same segment is refused, '
        'the collected transformee survives', () {
      final tool = TransformObjectTool.rotate(newId: newId, angle: math.pi / 2);
      tool.onInput(tapOn(ab, const Vec2(2, 2)));
      final first = tool.onInput(tapOn(o, o.position)) as ToolCommitted;
      first.command.apply(construction);

      tool.onInput(tapOn(ab, const Vec2(2, 2)));
      expect(
        tool.onInput(tapOn(o, o.position)),
        isA<ToolIgnored>(),
        reason: 'the commit would add nothing',
      );
      expect(
        tool.previewObjectIds,
        ['ab'],
        reason: 'the refused center tap unwinds; the transformee stays',
      );

      expect(
        tool.onInput(tapOn(c, c.position)),
        isA<ToolCommitted>(),
        reason: 'a different center is not a duplicate',
      );
    });

    test('a different angle or a different mirror is never falsely reused', () {
      final quarter = TransformObjectTool.rotate(
        newId: newId,
        angle: math.pi / 2,
      );
      quarter.onInput(tapOn(o, o.position));
      final first = quarter.onInput(tapOn(a, a.position)) as ToolCommitted;
      first.command.apply(construction);

      final third = TransformObjectTool.rotate(
        newId: newId,
        angle: math.pi / 3,
      );
      third.onInput(tapOn(o, o.position));
      expect(
        third.onInput(tapOn(a, a.position)),
        isA<ToolCommitted>(),
        reason: 'same point and center, different angle',
      );

      final otherAxis = LineThroughTwoPoints(id: 'y', point1: m1, point2: a);
      construction.add(otherAxis);
      final reflect = TransformObjectTool.reflectAboutLine(newId: newId);
      reflect.onInput(tapOn(o, o.position));
      final across = reflect.onInput(tapOn(xAxis, const Vec2(2, 0)));
      (across as ToolCommitted).command.apply(construction);
      reflect.onInput(tapOn(o, o.position));
      expect(
        reflect.onInput(tapOn(otherAxis, const Vec2(0, 1))),
        isA<ToolCommitted>(),
        reason: 'same point, different mirror',
      );
    });

    test(
      'point mode: the same reflection twice is refused in either order',
      () {
        final tool = TransformObjectTool.reflectAboutLine(newId: newId);
        tool.onInput(tapOn(o, o.position));
        final first =
            tool.onInput(tapOn(xAxis, const Vec2(2, 0))) as ToolCommitted;
        first.command.apply(construction);

        // Point first: the committing mirror tap is refused, the point stays.
        tool.onInput(tapOn(o, o.position));
        expect(
          tool.onInput(tapOn(xAxis, const Vec2(2, 0))),
          isA<ToolIgnored>(),
        );
        expect(tool.previewObjectIds, ['o']);
        tool.reset();

        // Line first: the committing point tap is refused and unwound.
        tool.onInput(tapOn(xAxis, const Vec2(2, 0)));
        expect(tool.onInput(tapOn(o, o.position)), isA<ToolIgnored>());
        expect(
          tool.previewObjectIds,
          ['x'],
          reason: 'the point tap unwound, the pending mirror stays',
        );
        expect(
          tool.onInput(tapOn(c, c.position)),
          isA<ToolCommitted>(),
          reason: 'a different point still commits',
        );
      },
    );

    test('a hidden equivalent image is reused untouched, not revealed', () {
      final hidden = RotatedPoint(
        id: 'h',
        point: a,
        center: o,
        angle: math.pi / 2,
      );
      hidden.attributes = hidden.attributes.copyWith(visible: false);
      construction.add(hidden);

      final tool = TransformObjectTool.rotate(newId: newId, angle: math.pi / 2);
      tool.onInput(tapOn(ab, const Vec2(2, 2)));
      final result = tool.onInput(tapOn(o, o.position)) as ToolCommitted;
      final macro = result.command as MacroCommand;
      expect(
        macro.commands,
        hasLength(2),
        reason: "A's image is reused; only B's image + segment are added",
      );
      result.command.apply(construction);

      final image = construction.objects.last as Segment;
      expect(identical(image.point1, hidden), isTrue);
      expect(
        hidden.attributes.visible,
        isFalse,
        reason: 'a reused equivalent keeps its attributes',
      );
    });
  });

  group('dilate (Phase 68)', () {
    test('point mode: point then center commits a bare HomotheticPoint', () {
      final p = FreePoint(id: 'p', position: const Vec2(3, 1));
      final c = FreePoint(id: 'c', position: const Vec2(1, 1));
      final tool = TransformObjectTool.dilate(newId: newId, ratio: 2);

      expect(tool.onInput(ToolInput(p.position, hit: p)), isA<ToolAccepted>());
      final result = tool.onInput(ToolInput(c.position, hit: c));

      expect(result, isA<ToolCommitted>());
      final command = (result as ToolCommitted).command;
      final image = (command as AddObjectCommand).object as HomotheticPoint;
      expect(image.parents, [p, c]);
      expect(image.ratio, 2);
      expect(image.position!.closeTo(const Vec2(5, 1), 1e-12), isTrue);
    });

    test('a non-finite ratio is rejected at construction', () {
      expect(
        () => TransformObjectTool.dilate(newId: newId, ratio: double.nan),
        throwsArgumentError,
      );
    });

    test('dilate a circle: radius scales by |ratio|, a negative ratio lands '
        'on the far side of the center', () {
      final cc = FreePoint(id: 'cc', position: const Vec2(1, 0));
      final rim = FreePoint(id: 'rim', position: const Vec2(2, 0));
      final circle = CircleCenterPoint(id: 'o', center: cc, onCircle: rim);
      final o = FreePoint(id: 'ctr', position: const Vec2(0, 0));
      final construction = Construction()
        ..add(cc)
        ..add(rim)
        ..add(circle)
        ..add(o);
      final tool = TransformObjectTool.dilate(newId: newId, ratio: -2);

      tool.onInput(ToolInput(const Vec2(2, 0.01), hit: circle));
      final result =
          tool.onInput(ToolInput(o.position, hit: o)) as ToolCommitted;

      (result.command as MacroCommand).apply(construction);
      final image = construction.objects.last as CircleCenterPoint;
      expect(image.circle!.radius, closeTo(2, 1e-12));
      expect(image.circle!.center.closeTo(const Vec2(-2, 0), 1e-12), isTrue);
      expect(image.center, isA<HomotheticPoint>());
    });

    test('sector is supported — homothety preserves orientation even at a '
        'negative ratio', () {
      final c = FreePoint(id: 'c', position: const Vec2(0, 0));
      final s = FreePoint(id: 's', position: const Vec2(1, 0));
      final e = FreePoint(id: 'e', position: const Vec2(0, 1));
      final sector = Sector(id: 'sec', center: c, start: s, end: e);
      final o = FreePoint(id: 'o', position: const Vec2(3, 3));
      final construction = Construction()
        ..add(c)
        ..add(s)
        ..add(e)
        ..add(sector)
        ..add(o);
      final tool = TransformObjectTool.dilate(newId: newId, ratio: -1.5);

      tool.onInput(ToolInput(const Vec2(1, 0), hit: sector));
      final result =
          tool.onInput(ToolInput(o.position, hit: o)) as ToolCommitted;

      (result.command as MacroCommand).apply(construction);
      final image = construction.objects.last as Sector;
      expect(
        image.sweep!,
        closeTo(sector.sweep!, 1e-12),
        reason:
            'det k² > 0: the wedge is the image wedge, not its '
            'complement',
      );
      expect(image.circle!.radius, closeTo(1.5, 1e-12));
    });

    test('vertex angle: arms keep their order, sweep unchanged', () {
      final a1 = FreePoint(id: 'a1', position: const Vec2(2, 1));
      final vx = FreePoint(id: 'vx', position: const Vec2(1, 1));
      final a2 = FreePoint(id: 'a2', position: const Vec2(1, 2));
      final angle = VertexAngle(id: 'ang', arm1: a1, vertex: vx, arm2: a2);
      final o = FreePoint(id: 'o', position: const Vec2(0, 0));
      final construction = Construction()
        ..add(a1)
        ..add(vx)
        ..add(a2)
        ..add(angle)
        ..add(o);
      final tool = TransformObjectTool.dilate(newId: newId, ratio: -1);

      tool.onInput(ToolInput(const Vec2(1, 1), hit: angle));
      final result =
          tool.onInput(ToolInput(o.position, hit: o)) as ToolCommitted;

      (result.command as MacroCommand).apply(construction);
      final image = construction.objects.last as VertexAngle;
      expect(
        (image.arm1 as HomotheticPoint).point,
        a1,
        reason: 'no arm swap — dilation preserves orientation',
      );
      expect((image.arm2 as HomotheticPoint).point, a2);
      expect(image.angle!.sweep, closeTo(angle.angle!.sweep, 1e-12));
    });

    test('images reuse across gestures at the same ratio; a different '
        'ratio commits fresh', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 2));
      final b = FreePoint(id: 'b', position: const Vec2(4, 2));
      final c = FreePoint(id: 'c', position: const Vec2(4, 6));
      final o = FreePoint(id: 'o', position: const Vec2(10, 10));
      final ab = Segment(id: 'ab', point1: a, point2: b);
      final bc = Segment(id: 'bc', point1: b, point2: c);
      final construction = Construction()
        ..add(a)
        ..add(b)
        ..add(c)
        ..add(o)
        ..add(ab)
        ..add(bc);
      ToolInput tapOn(GeoObject hit, Vec2 position) =>
          ToolInput(position, hit: hit, objects: construction.objects);

      final tool = TransformObjectTool.dilate(newId: newId, ratio: 2);
      tool.onInput(tapOn(ab, const Vec2(2, 2)));
      final first = tool.onInput(tapOn(o, o.position)) as ToolCommitted;
      first.command.apply(construction);

      tool.onInput(tapOn(bc, const Vec2(4, 4)));
      final second = tool.onInput(tapOn(o, o.position)) as ToolCommitted;
      expect(
        (second.command as MacroCommand).commands,
        hasLength(2),
        reason: "C's image + the rebuilt segment — B's image is reused",
      );
      second.command.apply(construction);
      expect(
        construction.objects.whereType<HomotheticPoint>(),
        hasLength(3),
        reason: 'the shared vertex B is imaged once',
      );

      tool.onInput(tapOn(ab, const Vec2(2, 2)));
      expect(
        tool.onInput(tapOn(o, o.position)),
        isA<ToolIgnored>(),
        reason: 'repeating the same dilation adds nothing',
      );
      tool.reset();

      final half = TransformObjectTool.dilate(newId: newId, ratio: 0.5);
      half.onInput(tapOn(ab, const Vec2(2, 2)));
      expect(
        half.onInput(tapOn(o, o.position)),
        isA<ToolCommitted>(),
        reason: 'a different ratio is never falsely reused',
      );
    });
  });
}
