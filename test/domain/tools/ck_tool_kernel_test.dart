import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/document_kernel.dart';
import 'package:regula/domain/construction/geo_object.dart';
import 'package:regula/domain/construction/objects/five_point_conic.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/intersection_point.dart';
import 'package:regula/domain/construction/objects/midpoint.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/absolute.dart';
import 'package:regula/domain/tools/intersection_tool.dart';
import 'package:regula/domain/tools/point_coincidence.dart';
import 'package:regula/domain/tools/point_resolution.dart';
import 'package:regula/domain/tools/tool.dart';

/// Phase 126: the document's geometry reaches the tool layer.
///
/// Phase 125 threaded the absolute through everything the *construction*
/// drives and left one knowing gap: the tools, which had no construction
/// to read a kernel from. That gap was safe only because the codec refused
/// to load a non-Euclidean document at all. Lifting the refusal without
/// closing it first would ship two bugs of quite different character, and
/// this file pins both.
void main() {
  const hyperbolic = Absolute.hyperbolic;
  const kernel = DocumentKernel(metric: FundamentalConic.hyperbolic);

  /// Five points on a Euclidean circle — a *projective* kind, so it is
  /// exactly as buildable in a hyperbolic document as in a Euclidean one
  /// (PLAN §"The audit", tier 1). That is the whole point: a hyperbolic
  /// document can contain conics through the circular points.
  FivePointConic concyclic(String id, Vec2 centre, double radius) =>
      FivePointConic(
        id: id,
        points: [
          for (var i = 0; i < 5; i++)
            FreePoint(
              id: '$id$i',
              position:
                  centre +
                  Vec2(radius * math.cos(i * 1.1), radius * math.sin(i * 1.1)),
            ),
        ],
      );

  group('the address space is a function of the absolute', () {
    test('a branch index names a different crossing in each geometry', () {
      // The premise the rest of this file rests on, checked rather than
      // assumed. Two Euclidean circles share I and J, which the Euclidean
      // filter drops and a proper absolute keeps — I and J are shared by
      // every *Euclidean* circle and by no hyperbolic one, so keeping
      // them is right, and it makes the list a different length.
      final inner = concyclic('a', const Vec2(0, 0), 0.5)
        ..recompute(hyperbolic);
      final outer = concyclic('b', const Vec2(0, 0.02), 0.2)
        ..recompute(hyperbolic);

      final euclidean = intersectionCandidates(inner, outer);
      final proper = intersectionCandidates(inner, outer, absolute: hyperbolic);
      expect(euclidean, hasLength(2));
      expect(proper, hasLength(4));

      // Not merely longer — *interleaved*. The two conics miss, so both
      // real crossings are complex and I and J sort around them: index 0
      // is a crossing under one absolute and a circular point under the
      // other. A `branchIndex` built in the wrong space does not name a
      // nearby crossing, it names an unrelated point.
      expect(proper[0].closeTo(euclidean[0]), isFalse);
      expect(proper[1].closeTo(euclidean[0]), isTrue);
    });
  });

  group('the coincidence probe recomputes the whole construction', () {
    // The observable one, and the reason this had to land before the
    // codec change rather than beside it. `coincidentExistingPoint`
    // perturbs every mutable root, recomputes *everything*, restores the
    // roots and recomputes everything again — so its absolute is not
    // merely the one it answers in, it is the one the document is left
    // in.
    Construction hyperbolicMidpoint() {
      final construction = Construction(kernel: kernel);
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(0.8, 0));
      construction
        ..add(a)
        ..add(b)
        ..add(Midpoint(id: 'm', point1: a, point2: b));
      return construction;
    }

    test('the hyperbolic midpoint is not the Euclidean one, to start', () {
      final construction = hyperbolicMidpoint();
      final m = construction.byId('m')! as GeoPoint;
      // artanh is not linear: the CK midpoint of (0,0)–(0.8,0) sits at
      // 0.5, *further out* than the affine 0.4.
      expect(m.position!.x, closeTo(0.5, 1e-12));
    });

    test('the document stays in its own geometry when told what it is', () {
      final construction = hyperbolicMidpoint();
      final a = construction.byId('a')! as GeoPoint;
      final b = construction.byId('b')! as GeoPoint;
      final probe = Midpoint(id: 'probe', point1: a, point2: b)
        ..recompute(hyperbolic);

      coincidentExistingPoint(
        construction.objects,
        probe,
        absolute: hyperbolic,
      );

      final m = construction.byId('m')! as GeoPoint;
      expect(m.position!.x, closeTo(0.5, 1e-12));
    });

    test('and is left in the wrong one when the absolute is defaulted', () {
      // Not a hypothetical: this is what the tool layer did until this
      // phase. The probe answers a Euclidean question and then leaves the
      // whole document computed Euclidean, silently, until the next
      // mutation happens to recompute it.
      final construction = hyperbolicMidpoint();
      final a = construction.byId('a')! as GeoPoint;
      final b = construction.byId('b')! as GeoPoint;
      final probe = Midpoint(id: 'probe', point1: a, point2: b)
        ..recompute(hyperbolic);

      coincidentExistingPoint(construction.objects, probe);

      final m = construction.byId('m')! as GeoPoint;
      expect(m.position!.x, closeTo(0.4, 1e-12));
    });
  });

  group('the tools carry it from ToolInput', () {
    test('IntersectionTool leaves the document in its own geometry', () {
      final construction = Construction(kernel: kernel);
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(0.8, 0));
      final inner = concyclic('c', const Vec2(0, 0), 0.4);
      final outer = concyclic('d', const Vec2(0.3, 0), 0.4);
      construction
        ..add(a)
        ..add(b)
        ..add(Midpoint(id: 'm', point1: a, point2: b));
      for (final p in inner.points) {
        construction.add(p);
      }
      construction.add(inner);
      for (final p in outer.points) {
        construction.add(p);
      }
      construction.add(outer);

      // A visible point sitting on the crossing, so the tool's dedupe
      // probe actually *runs* — without a match within tolerance
      // `coincidentExistingPoint` returns before recomputing anything and
      // this test would pass whatever absolute it was given.
      final crossing = intersectionCandidates(
        inner,
        outer,
        absolute: hyperbolic,
      ).firstWhere((p) => p.toVec2() != null).toVec2()!;
      construction.add(FreePoint(id: 'onCrossing', position: crossing));

      var next = 0;
      final tool = IntersectionTool(newId: () => 'new${next++}');
      ToolInput at(GeoObject hit, Vec2 where) => ToolInput(
        where,
        hit: hit,
        objects: construction.objects,
        absolute: hyperbolic,
      );
      expect(tool.onInput(at(inner, crossing)), isA<ToolAccepted>());
      tool.onInput(at(outer, crossing));

      // The dedupe probes inside the tool recompute the construction; the
      // midpoint is the witness that they put it back the way they found
      // it, in the geometry the document is in.
      final m = construction.byId('m')! as GeoPoint;
      expect(m.position!.x, closeTo(0.5, 1e-12));
    });

    test('resolvePoint addresses in the input absolute', () {
      final inner = concyclic('c', const Vec2(0, 0), 0.4)
        ..recompute(hyperbolic);
      final outer = concyclic('d', const Vec2(0.3, 0), 0.4)
        ..recompute(hyperbolic);
      final candidates = intersectionCandidates(
        inner,
        outer,
        absolute: hyperbolic,
      );
      final target = candidates.firstWhere((p) => p.toVec2() != null).toVec2()!;

      final resolved = resolvePoint(
        ToolInput(
          target,
          hit: inner,
          extraHits: [outer],
          snapThreshold: 0.05,
          absolute: hyperbolic,
        ),
        () => 'x',
      );
      final point = resolved.point;
      expect(point, isA<IntersectionPoint>());
      point.recompute(hyperbolic);
      expect(point.position!.distanceTo(target), lessThan(1e-9));
    });
  });
}
