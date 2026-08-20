import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/commands/move_free_point_command.dart';
import 'package:regula/domain/commands/translate_objects_command.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/five_point_conic.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/point_on_object.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/tools/drag_session.dart';

/// Session-level coverage for pencil-angle re-anchoring (Phase 132d).
///
/// A conic-glued point's parameter names a point only through
/// `ConicShape`'s canonical frame, whose discrete choices switch as the
/// host moves. The engine-level carry is pinned in
/// `conic_shape_test.dart`; what lives here is the command path — the
/// gesture re-anchors per preview frame, the command carries the net
/// re-expressions, and cancel/undo/redo restore them bitwise. The two
/// drag paths were probed for their switch counts before being pinned:
/// the rigid translation crosses two frame switches and the single-point
/// drag one, with no class change on either.
void main() {
  /// Five points on `x'²/16 + y'² = 1` centred (0.4, 0.7) — the same
  /// elongated ellipse the engine-level tests measure, whose frame
  /// switches under ordinary motion.
  List<Vec2> ellipsePoints() => [
    for (final t in [0.3, 1.2, 2.1, 3.6, 5.1])
      Vec2(0.4 + 4 * math.cos(t), 0.7 + math.sin(t)),
  ];

  late Construction construction;
  late List<FreePoint> points;
  late FivePointConic conic;
  late PointOnObject glued;

  setUp(() {
    construction = Construction();
    points = [
      for (final (i, p) in ellipsePoints().indexed)
        FreePoint(id: 'p$i', position: p),
    ];
    conic = FivePointConic(id: 'k', points: points);
    for (final p in points) {
      construction.add(p);
    }
    construction.add(conic);
    glued = PointOnObject(id: 'g', curve: conic, parameter: 0.9);
    construction.add(glued);
  });

  /// Drives [session] along [delta] in [steps] uniform frames from
  /// [grabStart], recording the glued point's largest per-frame motion.
  double drive(DragSession session, Vec2 grabStart, Vec2 delta, int steps) {
    var previous = glued.position!;
    var worst = 0.0;
    for (var i = 1; i <= steps; i++) {
      session.update(grabStart + delta * (i / steps));
      final current = glued.position;
      expect(current, isNotNull);
      worst = math.max(worst, current!.distanceTo(previous));
      previous = current;
    }
    return worst;
  }

  group('rigid translation across a frame switch', () {
    const delta = Vec2(6, 0);
    const grab = Vec2(0, 0);

    test('the glued point stays continuous and the command carries the '
        're-expression', () {
      final startParameter = glued.parameter;
      final session = DragSession.start(construction, conic, grab)!;
      final worst = drive(session, grab, delta, 60);
      // Each frame translates the figure by 0.1; without re-anchoring the
      // switch frames move the glued point by world units (pinned at the
      // engine level, 4.4 on this figure).
      expect(worst, lessThan(0.5));
      expect(glued.parameter, isNot(startParameter), reason: 'switched');

      final endParameter = glued.parameter;
      final endPosition = glued.position!;
      final command = session.end()! as TranslateObjectsCommand;
      expect(command.glueChanges, isNotEmpty);
      expect(command.glueChanges.single.id, 'g');
      expect(command.glueChanges.single.from, startParameter);
      expect(command.glueChanges.single.to, endParameter);

      // end() rolled the preview back — bitwise, like every session.
      expect(glued.parameter, startParameter);

      // Apply lands on the preview's end state; undo and redo replay the
      // re-expression exactly, not just the positions.
      command.apply(construction);
      expect(glued.parameter, endParameter);
      expect(glued.position!.x, closeTo(endPosition.x, 1e-12));
      expect(glued.position!.y, closeTo(endPosition.y, 1e-12));
      command.undo(construction);
      expect(glued.parameter, startParameter);
      command.apply(construction);
      expect(glued.parameter, endParameter);
    });

    test('cancel restores the pre-drag parameter bitwise', () {
      final startParameter = glued.parameter;
      final startPosition = glued.position!;
      final session = DragSession.start(construction, conic, grab)!;
      drive(session, grab, delta, 60);
      expect(glued.parameter, isNot(startParameter));
      session.cancel();
      expect(glued.parameter, startParameter);
      expect(glued.position, startPosition);
    });

    test('a drag that crosses no switch commits no glue changes', () {
      final session = DragSession.start(construction, conic, grab)!;
      drive(session, grab, const Vec2(-2, 0), 20);
      final command = session.end()! as TranslateObjectsCommand;
      expect(command.glueChanges, isEmpty);
    });
  });

  group('single-free-point drag across a frame switch', () {
    const delta = Vec2(0, 2);

    test('the glued point stays continuous and the command carries the '
        're-expression', () {
      final startParameter = glued.parameter;
      final grab = points[1].position;
      final session = DragSession.start(construction, points[1], grab)!;
      final worst = drive(session, grab, delta, 60);
      expect(worst, lessThan(0.5));
      expect(glued.parameter, isNot(startParameter), reason: 'switched');

      final endParameter = glued.parameter;
      final command = session.end()! as MoveFreePointCommand;
      expect(command.glueChanges, isNotEmpty);
      expect(command.glueChanges.single.from, startParameter);
      expect(command.glueChanges.single.to, endParameter);
      expect(glued.parameter, startParameter, reason: 'rolled back');

      command.apply(construction);
      expect(glued.parameter, endParameter);
      command.undo(construction);
      expect(glued.parameter, startParameter);
    });
  });
}
