import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/commands/set_geometry_command.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/document_kernel.dart';
import 'package:regula/domain/construction/objects/five_point_conic.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/intersection_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/math/vec2.dart';

/// Phase 126: switching a document's geometry is a re-addressing event.
///
/// The claim under test is not that the switch redraws the figure — every
/// metric kind does that, and Phase 125 pinned it. It is that a stored
/// `branchIndex` **means something different afterwards**, so a switch
/// that merely assigns the new absolute silently moves intersection points
/// onto other people's crossings. That is the Phase 120c defect arriving
/// from a third direction, and PLAN §"The audit" called it before the code
/// existed.
void main() {
  const hyperbolic = DocumentKernel(metric: FundamentalConic.hyperbolic);
  const euclidean = DocumentKernel();

  /// Five points on a Euclidean circle. A `FivePointConic` is **tier 1** —
  /// five points determine a conic projectively, with no metric anywhere —
  /// so the conic itself is bit-identical in every geometry. That is what
  /// makes this the cleanest possible witness: when the switch re-points
  /// this pair, nothing has moved at all. Only the numbering has.
  FivePointConic concyclic(
    Construction into,
    String id,
    Vec2 centre,
    double radius,
  ) {
    final points = [
      for (var i = 0; i < 5; i++)
        FreePoint(
          id: '$id$i',
          position:
              centre +
              Vec2(radius * math.cos(i * 1.1), radius * math.sin(i * 1.1)),
        ),
    ];
    for (final p in points) {
      into.add(p);
    }
    final conic = FivePointConic(id: id, points: points);
    into.add(conic);
    return conic;
  }

  /// Two concyclic conics that **miss** — the crossings are a complex
  /// conjugate pair — plus one intersection point on the first of them.
  /// Missing is the point: both real crossings are complex, so the
  /// circular points sort *around* them rather than after them, and the
  /// address of a crossing genuinely differs between the two geometries.
  (Construction, IntersectionPoint) missingPair() {
    final construction = Construction();
    final outer = concyclic(construction, 'a', const Vec2(0, 0), 0.5);
    final inner = concyclic(construction, 'b', const Vec2(0, 0.02), 0.2);
    final crossing = IntersectionPoint(
      id: 'x',
      curve1: outer,
      curve2: inner,
      branchIndex: 0,
    );
    construction.add(crossing);
    return (construction, crossing);
  }

  group('the crossing stays put and its address moves', () {
    test('Euclidean drops the circular points, hyperbolic keeps them', () {
      final (construction, crossing) = missingPair();
      expect(
        intersectionCandidates(crossing.curve1, crossing.curve2),
        hasLength(2),
      );
      expect(
        intersectionCandidates(
          crossing.curve1,
          crossing.curve2,
          absolute: hyperbolic.absolute,
        ),
        hasLength(4),
      );
      expect(construction.kernel, euclidean);
    });

    test('the switch re-points it, and reports having done so', () {
      final (construction, crossing) = missingPair();
      final before = crossing.projPoint!;

      final change = construction.switchKernel(hyperbolic);

      expect(construction.kernel, hyperbolic);
      expect(change.readdressed, hasLength(1));
      expect(change.readdressed.single.id, 'x');
      expect(change.readdressed.single.from, 0);
      expect(change.readdressed.single.to, 1);
      expect(change.unmatched, isEmpty);
      expect(change.hasReport, isTrue);

      // The whole point: the conic is projective, so nothing about this
      // crossing changed except which index names it. A switch that kept
      // the number would have left the point on a circular point instead.
      expect(crossing.projPoint!.closeTo(before), isTrue);
    });

    test('keeping the number would have moved the point — the control', () {
      final (construction, crossing) = missingPair();
      final before = crossing.projPoint!;
      // What a plain assignment would have done, spelled out: address 0
      // under the new absolute is a circular point, not the crossing.
      final candidates = intersectionCandidates(
        crossing.curve1,
        crossing.curve2,
        absolute: hyperbolic.absolute,
      );
      expect(candidates[0].closeTo(before), isFalse);
      construction.switchKernel(hyperbolic);
    });
  });

  group('undo restores the address, it does not re-derive it', () {
    test('a round trip through the command is the identity', () {
      final (construction, crossing) = missingPair();
      final before = crossing.projPoint!;
      final command = SetGeometryCommand(hyperbolic);

      command.apply(construction);
      expect(construction.kernel, hyperbolic);
      expect(crossing.branchIndex, 1);

      command.undo(construction);
      expect(construction.kernel, euclidean);
      expect(crossing.branchIndex, 0);
      expect(crossing.projPoint!.closeTo(before), isTrue);

      // Redo replays the recorded end state rather than asking the same
      // question a second time.
      command.apply(construction);
      expect(construction.kernel, hyperbolic);
      expect(crossing.branchIndex, 1);
    });

    test('the report survives for the UI to read after the fact', () {
      final (construction, _) = missingPair();
      final command = SetGeometryCommand(hyperbolic);
      expect(command.change, isNull);
      command.apply(construction);
      expect(command.change!.from, euclidean);
      expect(command.change!.to, hyperbolic);
      expect(command.change!.readdressed, hasLength(1));
    });

    test('undoing before applying is a programmer error, not a guess', () {
      final (construction, _) = missingPair();
      expect(
        () => SetGeometryCommand(hyperbolic).undo(construction),
        throwsStateError,
      );
    });
  });

  group('the quiet cases stay quiet', () {
    test('switching to the geometry already in force does nothing', () {
      final (construction, crossing) = missingPair();
      final change = construction.switchKernel(euclidean);
      expect(change.isEmpty, isTrue);
      expect(change.hasReport, isFalse);
      expect(crossing.branchIndex, 0);
    });

    test('a pair whose real crossings stay first needs no re-addressing', () {
      // Two conics that genuinely cross: the real crossings are tier 1 of
      // canonical order in either geometry, so they hold indices 0 and 1
      // whether or not the circular points are filtered out behind them.
      // Most of a document is in this case, which is why the report is
      // usually empty — and why an unconditional warning would be noise.
      final construction = Construction();
      final left = concyclic(construction, 'a', const Vec2(0, 0), 0.4);
      final right = concyclic(construction, 'b', const Vec2(0.3, 0), 0.4);
      final crossing = IntersectionPoint(
        id: 'x',
        curve1: left,
        curve2: right,
        branchIndex: 0,
      );
      construction.add(crossing);
      final before = crossing.position!;

      final change = construction.switchKernel(hyperbolic);

      expect(change.readdressed, isEmpty);
      expect(change.unmatched, isEmpty);
      expect(crossing.position!.distanceTo(before), lessThan(1e-12));
    });
  });

  group('what cannot be matched is reported, not hidden', () {
    test('an intersection with no candidates either side is unmatched', () {
      final construction = Construction();
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(0.5, 0.1));
      construction
        ..add(a)
        ..add(b);
      // Coincident carriers: the meet is every point of the line, so
      // there is no candidate list at all — in either geometry, incidence
      // being tier 1. Nothing to match on, so the address passes through
      // and says so.
      final l1 = LineThroughTwoPoints(id: 'l1', point1: a, point2: b);
      final l2 = LineThroughTwoPoints(id: 'l2', point1: b, point2: a);
      construction
        ..add(l1)
        ..add(l2);
      final crossing = IntersectionPoint(
        id: 'x',
        curve1: l1,
        curve2: l2,
        branchIndex: 0,
      );
      construction.add(crossing);
      expect(crossing.projPoint, isNull);

      final change = construction.switchKernel(hyperbolic);

      expect(change.readdressed, isEmpty);
      expect(change.unmatched, ['x']);
      expect(change.hasReport, isTrue);
      expect(crossing.branchIndex, 0);
    });
  });
}
