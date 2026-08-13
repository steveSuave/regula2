import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regula/application/providers/command_stack_provider.dart';
import 'package:regula/application/providers/construction_provider.dart';
import 'package:regula/application/providers/tool_provider.dart';
import 'package:regula/domain/commands/add_object_command.dart';
import 'package:regula/domain/commands/delete_objects_command.dart';
import 'package:regula/domain/commands/macro_command.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/geo_object.dart';
import 'package:regula/domain/construction/object_attributes.dart';
import 'package:regula/domain/construction/objects/centroid.dart';
import 'package:regula/domain/construction/objects/distance_measurement.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/rotated_point.dart';
import 'package:regula/domain/construction/objects/segment.dart';
import 'package:regula/domain/construction/objects/vertex_angle.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/tools/point_tool.dart';
import 'package:regula/domain/tools/tool.dart';
import 'package:regula/domain/tools/transform_object_tool.dart';
import 'package:regula/domain/tools/triangle_center_tool.dart';

/// Scripted tool for exercising the notifier: replays [results] in order
/// and records calls.
class _StubTool implements Tool {
  _StubTool(this.results);

  final List<ToolResult> results;
  int inputs = 0;
  int resets = 0;

  @override
  bool get hasPartialInput => false;

  @override
  ToolResult onInput(ToolInput input) => results[inputs++];

  @override
  void reset() => resets++;
}

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
  });

  group('toolProvider', () {
    test(
      'starts with no active tool; input in move/select mode is ignored',
      () {
        expect(container.read(toolProvider).tool, isNull);

        final result = container
            .read(toolProvider.notifier)
            .handleInput(const ToolInput(Vec2.zero));

        expect(result, isA<ToolIgnored>());
        expect(container.read(toolProvider).revision, 0);
      },
    );

    test('activate / deactivate swap the tool and reset the outgoing one', () {
      final notifier = container.read(toolProvider.notifier);
      final tool = _StubTool([]);

      notifier.activate(tool);
      expect(container.read(toolProvider).tool, same(tool));

      notifier.deactivate();
      expect(container.read(toolProvider).tool, isNull);
      expect(
        tool.resets,
        1,
        reason: 'partially-collected input must not leak across a switch',
      );
    });

    group('drag vs. activation (Phase 30b)', () {
      late FreePoint p;

      setUp(() {
        p = FreePoint(id: 'p', position: Vec2.zero);
        container
            .read(commandStackProvider.notifier)
            .execute(AddObjectCommand(p));
      });

      test('activating a tool mid-drag commits the move as one undo step', () {
        final notifier = container.read(toolProvider.notifier);
        expect(notifier.startDrag(p, Vec2.zero), isTrue);
        notifier.updateDrag(const Vec2(5, 0));
        expect(p.position, const Vec2(5, 0), reason: 'preview applied');

        notifier.activate(_StubTool([]));

        expect(
          p.position,
          const Vec2(5, 0),
          reason: 'the switch must not discard the move',
        );
        container.read(commandStackProvider.notifier).undo();
        expect(
          p.position,
          Vec2.zero,
          reason: 'the drag-so-far became one command',
        );
      });

      test(
        'deactivating mid-drag still rolls the preview back (Esc abort)',
        () {
          final notifier = container.read(toolProvider.notifier);
          notifier.startDrag(p, Vec2.zero);
          notifier.updateDrag(const Vec2(5, 0));

          notifier.deactivate();

          expect(p.position, Vec2.zero, reason: 'Esc aborts the drag');
          container.read(commandStackProvider.notifier).undo();
          expect(
            container.read(constructionProvider).construction.isEmpty,
            isTrue,
            reason:
                'an aborted drag leaves nothing on the stack — the top '
                'undo step is still the AddObjectCommand',
          );
        },
      );

      test('activating a tool over an unmoved drag commits nothing', () {
        final notifier = container.read(toolProvider.notifier);
        notifier.startDrag(p, Vec2.zero);

        notifier.activate(_StubTool([]));

        expect(p.position, Vec2.zero);
        container.read(commandStackProvider.notifier).undo();
        expect(
          container.read(constructionProvider).construction.isEmpty,
          isTrue,
          reason: 'the only undo step is the AddObjectCommand',
        );
      });
    });

    test('committed command executes on the command stack', () {
      var nextId = 0;
      container
          .read(toolProvider.notifier)
          .activate(PointTool(newId: () => 'p${nextId++}'));

      final result = container
          .read(toolProvider.notifier)
          .handleInput(const ToolInput(Vec2(2, 3)));

      expect(result, isA<ToolCommitted>());
      final construction = container.read(constructionProvider).construction;
      expect(construction.contains('p0'), isTrue);
      expect(
        (construction.byId('p0')! as FreePoint).position,
        const Vec2(2, 3),
      );
      expect(
        container.read(commandStackProvider).canUndo,
        isTrue,
        reason: 'the tool tap must be undoable',
      );
      expect(
        container.read(toolProvider).revision,
        1,
        reason: 'commit resets the tool, so previews must repaint',
      );
    });

    test('accepted input bumps revision, ignored input does not', () {
      final tool = _StubTool([const ToolAccepted(), const ToolIgnored()]);
      final notifier = container.read(toolProvider.notifier)..activate(tool);

      final revisions = <int>[];
      container.listen(toolProvider, (_, next) => revisions.add(next.revision));

      notifier.handleInput(const ToolInput(Vec2.zero)); // accepted
      notifier.handleInput(const ToolInput(Vec2.zero)); // ignored

      expect(revisions, [1], reason: 'ignored input must not notify');
    });

    test('undo, redo, and construction replace discard in-progress input', () {
      final notifier = container.read(toolProvider.notifier);
      final tool = _StubTool([]);
      notifier.activate(tool);

      final stack = container.read(commandStackProvider.notifier);
      stack.execute(AddObjectCommand(FreePoint(id: 'x', position: Vec2.zero)));

      stack.undo();
      expect(tool.resets, 1);
      expect(
        container.read(toolProvider).revision,
        1,
        reason: 'previews of the discarded input must repaint',
      );

      stack.redo();
      expect(tool.resets, 2);

      container.read(constructionProvider.notifier).replace(Construction());
      expect(
        tool.resets,
        3,
        reason: 'a swapped-in construction invalidates collected objects',
      );
      expect(
        container.read(toolProvider).tool,
        same(tool),
        reason: 'the tool itself stays active — only its input is dropped',
      );
    });

    test('undo mid-collection: stale parent cannot poison the next commit', () {
      var nextId = 0;
      final notifier = container.read(toolProvider.notifier);

      // Place a point, then start collecting a centroid on it.
      notifier.activate(PointTool(newId: () => 'p${nextId++}'));
      notifier.handleInput(const ToolInput(Vec2(1, 1)));
      final placed = container
          .read(constructionProvider)
          .construction
          .byId('p0')!;

      final centerTool = TriangleCenterTool(
        newId: () => 'n${nextId++}',
        buildCenter: Centroid.new,
      );
      notifier.activate(centerTool);
      notifier.handleInput(ToolInput(const Vec2(1, 1), hit: placed));
      expect(centerTool.collectedVertices, hasLength(1));

      // Undo removes the collected point out from under the tool.
      container.read(commandStackProvider.notifier).undo();
      expect(centerTool.collectedVertices, isEmpty);

      // Three fresh taps still commit cleanly.
      notifier.handleInput(const ToolInput(Vec2(0, 0)));
      notifier.handleInput(const ToolInput(Vec2(6, 0)));
      final result = notifier.handleInput(const ToolInput(Vec2(0, 6)));
      expect(result, isA<ToolCommitted>());
      expect(
        container.read(constructionProvider).construction.length,
        4,
        reason: '3 free points + the centroid',
      );
    });

    group('automatic naming', () {
      /// Commits [command] through the handleInput funnel via a stub tool.
      void commit(ProviderContainer container, MacroCommand command) {
        final notifier = container.read(toolProvider.notifier)
          ..activate(_StubTool([ToolCommitted(command)]));
        notifier.handleInput(const ToolInput(Vec2.zero));
      }

      String nameOf(ProviderContainer container, String id) => container
          .read(constructionProvider)
          .construction
          .byId(id)!
          .attributes
          .name;

      test('successive points are named A, B; a new segment gets a', () {
        final notifier = container.read(toolProvider.notifier);
        var nextId = 0;
        notifier.activate(PointTool(newId: () => 'p${nextId++}'));
        notifier.handleInput(const ToolInput(Vec2(0, 0)));
        notifier.handleInput(const ToolInput(Vec2(4, 0)));

        expect(nameOf(container, 'p0'), 'A');
        expect(nameOf(container, 'p1'), 'B');

        final construction = container.read(constructionProvider).construction;
        final segment = Segment(
          id: 's0',
          point1: construction.byId('p0')! as FreePoint,
          point2: construction.byId('p1')! as FreePoint,
        );
        commit(container, MacroCommand([AddObjectCommand(segment)]));

        expect(nameOf(container, 's0'), 'a');
        expect(
          segment.attributes.labelVisible,
          isFalse,
          reason: 'lines are named but their canvas label stays hidden',
        );
      });

      test('a measurement joins the lowercase pool but keeps its label — '
          'the on-canvas text is its whole point', () {
        final a = FreePoint(id: 'a', position: Vec2.zero);
        final b = FreePoint(id: 'b', position: const Vec2(3, 4));
        final distance = DistanceMeasurement(id: 'd', point1: a, point2: b);
        commit(
          container,
          MacroCommand([
            AddObjectCommand(a),
            AddObjectCommand(b),
            AddObjectCommand(distance),
          ]),
        );

        expect(nameOf(container, 'd'), 'a');
        expect(
          distance.attributes.labelVisible,
          isTrue,
          reason:
              'unlike lines/circles/polygons, the label stays shown — '
              'it reads as "a = 5.00"',
        );
      });

      test('a new angle is named from the Greek pool but shows only its '
          'value: name label hidden, showValue on', () {
        final a = FreePoint(id: 'a', position: const Vec2(1, 0));
        final v = FreePoint(id: 'v', position: Vec2.zero);
        final b = FreePoint(id: 'b', position: const Vec2(0, 1));
        final angle = VertexAngle(id: 'ang', arm1: a, vertex: v, arm2: b);
        commit(
          container,
          MacroCommand([
            AddObjectCommand(a),
            AddObjectCommand(v),
            AddObjectCommand(b),
            AddObjectCommand(angle),
          ]),
        );

        expect(nameOf(container, 'ang'), 'α');
        expect(
          angle.attributes.labelVisible,
          isFalse,
          reason: 'the name lives in the tree/inspector, not the canvas',
        );
        expect(
          angle.attributes.showValue,
          isTrue,
          reason: 'a fresh angle reads as its measure, e.g. 90.0°',
        );
        expect(angle.attributes.labelDx, 0);
        expect(
          angle.attributes.labelDy,
          0,
          reason: 'the bisector base places the text; no generic nudge',
        );
      });

      test('points keep labelVisible, hidden scaffolding burns no letters', () {
        final visible = FreePoint(id: 'v', position: Vec2.zero);
        final hidden = FreePoint(
          id: 'h',
          position: const Vec2(1, 0),
          attributes: const ObjectAttributes(visible: false),
        );
        final named = FreePoint(
          id: 'n',
          position: const Vec2(2, 0),
          attributes: const ObjectAttributes(name: 'custom'),
        );
        final after = FreePoint(id: 'z', position: const Vec2(3, 0));
        commit(
          container,
          MacroCommand([
            AddObjectCommand(visible),
            AddObjectCommand(hidden),
            AddObjectCommand(named),
            AddObjectCommand(after),
          ]),
        );

        expect(visible.attributes.name, 'A');
        expect(visible.attributes.labelVisible, isTrue);
        expect(hidden.attributes.name, isEmpty);
        expect(
          named.attributes.name,
          'custom',
          reason: 'a pre-set name is never overwritten',
        );
        expect(
          after.attributes.name,
          'B',
          reason: 'the batch-local scan skips the hidden object, not a letter',
        );
      });

      test('deleting B frees the name for the next point', () {
        final notifier = container.read(toolProvider.notifier);
        var nextId = 0;
        notifier.activate(PointTool(newId: () => 'p${nextId++}'));
        notifier.handleInput(const ToolInput(Vec2(0, 0)));
        notifier.handleInput(const ToolInput(Vec2(4, 0)));
        container
            .read(commandStackProvider.notifier)
            .execute(DeleteObjectsCommand(['p1']));

        notifier.handleInput(const ToolInput(Vec2(8, 0)));

        expect(nameOf(container, 'p2'), 'B');
      });

      test('names survive undo/redo', () {
        final notifier = container.read(toolProvider.notifier);
        var nextId = 0;
        notifier.activate(PointTool(newId: () => 'p${nextId++}'));
        notifier.handleInput(const ToolInput(Vec2(0, 0)));
        notifier.handleInput(const ToolInput(Vec2(4, 0)));

        final stack = container.read(commandStackProvider.notifier);
        stack.undo();
        stack.redo();

        expect(nameOf(container, 'p0'), 'A');
        expect(nameOf(container, 'p1'), 'B');
      });

      test('transforming AB then BC about one center names the shared '
          'vertex image once (Phase 40)', () {
        // The reported bug: segment-by-segment transforms re-imaged the
        // shared vertex, so its image was added — and named — per gesture.
        final construction = container.read(constructionProvider).construction;
        final a = FreePoint(id: 'a', position: const Vec2(0, 0));
        final b = FreePoint(id: 'b', position: const Vec2(4, 0));
        final c = FreePoint(id: 'c', position: const Vec2(4, 4));
        final o = FreePoint(id: 'o', position: const Vec2(10, 10));
        final ab = Segment(id: 'ab', point1: a, point2: b);
        final bc = Segment(id: 'bc', point1: b, point2: c);
        construction
          ..add(a)
          ..add(b)
          ..add(c)
          ..add(o)
          ..add(ab)
          ..add(bc);

        final notifier = container.read(toolProvider.notifier);
        var nextId = 0;
        notifier.activate(
          TransformObjectTool.rotate(
            newId: () => 'n${nextId++}',
            angle: math.pi / 2,
          ),
        );
        ToolInput tapOn(GeoObject hit, Vec2 position) =>
            ToolInput(position, hit: hit, objects: construction.objects);
        notifier.handleInput(tapOn(ab, const Vec2(2, 0)));
        notifier.handleInput(tapOn(o, const Vec2(10, 10)));
        notifier.handleInput(tapOn(bc, const Vec2(4, 2)));
        final result = notifier.handleInput(tapOn(o, const Vec2(10, 10)));

        expect(result, isA<ToolCommitted>());
        final images = construction.objects.whereType<RotatedPoint>().toList();
        expect(
          images,
          hasLength(3),
          reason: 'A, B, C images — the shared B imaged once',
        );
        final names = {for (final image in images) image.attributes.name};
        expect(
          names,
          hasLength(3),
          reason: 'three distinct auto-names, none duplicated',
        );
        expect(names, isNot(contains('')));
      });
    });

    test('activating a new tool starts it at revision 0', () {
      final notifier = container.read(toolProvider.notifier);
      notifier.activate(_StubTool([const ToolAccepted()]));
      notifier.handleInput(const ToolInput(Vec2.zero));
      expect(container.read(toolProvider).revision, 1);

      notifier.activate(_StubTool([]));

      expect(container.read(toolProvider).revision, 0);
    });
  });
}
