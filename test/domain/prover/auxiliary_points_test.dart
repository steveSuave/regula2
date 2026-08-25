/// The candidate enumerator (Phase 153): what a search would have to try.
///
/// The list is the search's input, so what is pinned here is the three
/// properties a search rests on — it is deterministic, it is a function
/// of the document alone, and it proposes nothing that is already
/// drawn — plus the two silences that are decisions rather than
/// omissions: a point on a line is not a foot worth proposing, and a
/// coincidence no structural test can see is dropped anyway.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:regula/application/persistence/construction_codec.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/geo_object.dart';
import 'package:regula/domain/construction/objects/circle_center.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/three_point_circle.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/prover/auxiliary_points.dart';

void main() {
  Construction build(Iterable<GeoObject> objects) {
    final construction = Construction();
    for (final object in objects) {
      construction.add(object);
    }
    return construction;
  }

  Construction load(String path) => decodeDocument(
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>,
  ).construction;

  /// A chord and the circle around it, so the foot of the centre on the
  /// chord *is* the chord's midpoint — a coincidence that is a theorem,
  /// not a spelling.
  Construction chordRig() {
    final a = FreePoint(id: 'a', position: const Vec2(-3, 0));
    final b = FreePoint(id: 'b', position: const Vec2(3, 0));
    final c = FreePoint(id: 'c', position: const Vec2(0, 5));
    final circle = ThreePointCircle(id: 'k', point1: a, point2: b, point3: c);
    final centre = CircleCenter(id: 'o', circle: circle);
    final chord = LineThroughTwoPoints(id: 'ab', point1: a, point2: b);
    return build([a, b, c, circle, centre, chord]);
  }

  group('auxiliaryCandidates', () {
    test('is a function of the document alone', () {
      final once = auxiliaryCandidates(
        load('test/fixtures/locus3.json').objects,
      );
      final twice = auxiliaryCandidates(
        load('test/fixtures/locus3.json').objects,
      );
      expect(once.length, twice.length);
      expect(
        [for (final candidate in once) '$candidate'],
        [for (final candidate in twice) '$candidate'],
        reason:
            'index i must name the same point in every copy — that is '
            'what lets a search resume and a measurement cite a candidate',
      );
    });

    test('families are filtered, and enumerated in declaration order', () {
      final construction = load('test/fixtures/locus3.json');
      final all = auxiliaryCandidates(construction.objects);
      final midpoints = auxiliaryCandidates(
        construction.objects,
        families: {AuxiliaryFamily.midpoint},
      );
      expect(midpoints, isNotEmpty);
      expect(
        midpoints.every((c) => c.family == AuxiliaryFamily.midpoint),
        isTrue,
      );
      final families = [for (final candidate in all) candidate.family.index];
      expect(
        families,
        orderedEquals(List.of(families)..sort()),
        reason: 'midpoints first is the order Phase 153 measured',
      );
    });

    test('a point the document already draws is not proposed', () {
      // `perp-true-unproved.rgl` has six points, so fifteen pairs — and
      // two of the points *are* midpoints of pairs among them (D of AB,
      // E of DB), which leaves thirteen.
      final construction = load('test/fixtures/perp-true-unproved.rgl');
      final midpoints = auxiliaryCandidates(
        construction.objects,
        families: {AuxiliaryFamily.midpoint},
      );
      expect(construction.objects.whereType<GeoPoint>().length, 6);
      expect(midpoints.length, 13);
    });

    test('a coincidence no structural test can see is dropped too', () {
      // The foot of the centre on the chord is the chord's midpoint.
      // Nothing about `CircleCenter` and `LineThroughTwoPoints` says so;
      // it is the perpendicular-bisector theorem, which is why the
      // dedup reads the diagram.
      final construction = chordRig();
      final candidates = auxiliaryCandidates(construction.objects);
      final chordMidpoint = candidates
          .where((c) => c.family == AuxiliaryFamily.midpoint)
          .where((c) => c.parents[0].id == 'a' && c.parents[1].id == 'b');
      expect(chordMidpoint, hasLength(1));
      expect(
        candidates.where(
          (c) => c.family == AuxiliaryFamily.foot && c.parents[0].id == 'o',
        ),
        isEmpty,
        reason: 'the foot of o on ab is the midpoint already proposed',
      );
    });

    test('a point on the line is its own foot, and the dedup knows it', () {
      final construction = chordRig();
      final feet = auxiliaryCandidates(
        construction.objects,
        families: {AuxiliaryFamily.foot},
      );
      expect(
        feet.where(
          (c) =>
              c.parents[1].id == 'ab' && {'a', 'b'}.contains(c.parents[0].id),
        ),
        isEmpty,
      );
    });

    test('what it proposes, the construction accepts', () {
      final construction = chordRig();
      final candidates = auxiliaryCandidates(construction.objects);
      expect(candidates, isNotEmpty);
      for (var i = 0; i < candidates.length; i++) {
        final fresh = chordRig();
        final proposal = auxiliaryCandidates(fresh.objects)[i].build('aux');
        fresh.add(proposal);
        expect(
          (fresh.objects.firstWhere((o) => o.id == 'aux') as GeoPoint).position,
          isNotNull,
          reason: 'a proposal with no real finite position is not offered',
        );
      }
    });
  });
}
