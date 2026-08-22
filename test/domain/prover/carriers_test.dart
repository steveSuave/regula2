import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:regula/application/persistence/construction_codec.dart';
import 'package:regula/domain/construction/geo_object.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/midpoint.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/prover/carriers.dart';
import 'package:regula/domain/prover/diagram_filter.dart';
import 'package:regula/domain/prover/fact.dart';
import 'package:regula/domain/prover/fact_database.dart';
import 'package:regula/domain/prover/hypotheses.dart';
import 'package:regula/domain/prover/predicate.dart';
import 'package:regula/domain/prover/rule_engine.dart';

void main() {
  FreePoint free(String id) => FreePoint(id: id, position: Vec2.zero);

  final a = free('a');
  final b = free('b');
  final c = free('c');
  final d = free('d');
  final e = free('e');
  final f = free('f');
  final g = free('g');
  final h = free('h');

  Fact coll(GeoPoint x, GeoPoint y, GeoPoint z) =>
      Fact(PredicateKind.coll, [x, y, z]);
  Fact cyclic(GeoPoint w, GeoPoint x, GeoPoint y, GeoPoint z) =>
      Fact(PredicateKind.cyclic, [w, x, y, z]);
  Fact para(GeoPoint w, GeoPoint x, GeoPoint y, GeoPoint z) =>
      Fact(PredicateKind.para, [w, x, y, z]);

  List<String> ids(Carrier carrier) => [
    for (final point in carrier.points) point.id,
  ];

  group('lineSlots — the table, pinned against the evaluators', () {
    // The one place the closure can be unsound. A slot listed here is a
    // claim that swapping its witness pair for any other pair on the
    // same line preserves the predicate's truth; only the evaluators can
    // adjudicate that, so they do, over a seeded sweep rather than one
    // hand-picked rig.
    //
    // The negatives matter as much as the positives: `cong` and
    // `eqratio` have exactly the same *shape* as `perp` and `eqangle`
    // and are exactly the entries that must stay empty, because a pair
    // names a segment and a segment has a length its carrier does not.

    Vec2 along(Vec2 origin, Vec2 direction, double t) => origin + direction * t;

    /// [count] configurations, deterministic.
    Iterable<math.Random> sweep(int count) sync* {
      for (var i = 0; i < count; i++) {
        yield math.Random(9_000 + i);
      }
    }

    Vec2 randomPoint(math.Random rng) =>
        Vec2(rng.nextDouble() * 12 - 6, rng.nextDouble() * 12 - 6);

    Vec2 randomDirection(math.Random rng) {
      final angle = rng.nextDouble() * math.pi;
      return Vec2(math.cos(angle), math.sin(angle));
    }

    /// A parameter far enough from [avoid] that the substituted point is
    /// a genuinely different one — otherwise the sweep would pass by
    /// substituting a point for itself.
    double otherParameter(math.Random rng, double avoid) {
      var t = rng.nextDouble() * 8 - 4;
      while ((t - avoid).abs() < 1) {
        t += 2;
      }
      return t;
    }

    test('para and perp resolve through either line slot', () {
      for (final rng in sweep(40)) {
        final d1 = randomDirection(rng);
        final d2 = Vec2(-d1.y, d1.x);
        final o1 = randomPoint(rng);
        final o2 = randomPoint(rng);
        final tb = otherParameter(rng, 0);
        final td = otherParameter(rng, 0);

        for (final entry in {
          PredicateKind.para: d1,
          PredicateKind.perp: d2,
        }.entries) {
          final points = [
            o1,
            along(o1, d1, tb),
            o2,
            along(o2, entry.value, td),
          ];
          final base = Predicate(entry.key, [a, b, c, d]);
          expect(
            base.holdsOn(points),
            isTrue,
            reason: 'bad rig: ${entry.key.name} is not true here',
          );
          for (final slot in lineSlots(entry.key)) {
            final moved = [...points];
            final origin = points[slot[0]];
            final direction = slot[0] == 0 ? d1 : entry.value;
            moved[slot[1]] = along(
              origin,
              direction,
              otherParameter(rng, slot[0] == 0 ? tb : td),
            );
            expect(
              base.holdsOn(moved),
              isTrue,
              reason: '${entry.key.name} slot $slot is not a line slot',
            );
          }
        }
      }
    });

    test('eqangle resolves through all four, because it reads mod pi', () {
      for (final rng in sweep(40)) {
        final d1 = randomDirection(rng);
        final theta = rng.nextDouble() * math.pi;
        Vec2 turned(Vec2 v) => Vec2(
          v.x * math.cos(theta) - v.y * math.sin(theta),
          v.x * math.sin(theta) + v.y * math.cos(theta),
        );
        final d3 = randomDirection(rng);
        final directions = [d1, turned(d1), d3, turned(d3)];
        final origins = [for (var i = 0; i < 4; i++) randomPoint(rng)];
        final parameters = [for (var i = 0; i < 4; i++) otherParameter(rng, 0)];
        final points = <Vec2>[
          for (var i = 0; i < 4; i++) ...[
            origins[i],
            along(origins[i], directions[i], parameters[i]),
          ],
        ];
        final base = Predicate(PredicateKind.eqangle, [a, b, c, d, e, f, g, h]);
        expect(
          base.holdsOn(points),
          isTrue,
          reason: 'bad rig: eqangle is not true here',
        );
        expect(lineSlots(PredicateKind.eqangle).length, 4);
        for (final slot in lineSlots(PredicateKind.eqangle)) {
          final index = slot[0] ~/ 2;
          final moved = [...points];
          moved[slot[1]] = along(
            origins[index],
            directions[index],
            otherParameter(rng, parameters[index]),
          );
          expect(
            base.holdsOn(moved),
            isTrue,
            reason: 'eqangle slot $slot is not a line slot',
          );
        }
      }
    });

    test('cong and eqratio have no line slot, and here is why', () {
      // Driven off the table rather than restating it: for every pair
      // slot of these two kinds, substituting another point on the same
      // line must preserve truth *exactly when the table lists the
      // slot*. It lists none, so every substitution must break the
      // predicate — and adding an entry here would fail on a numeric
      // counterexample rather than on an `isEmpty`.
      const origin = Vec2(0, 0);
      const unit = Vec2(1, 0);
      const other = Vec2(0, 2);
      final near = along(origin, unit, 4);
      final far = along(origin, unit, 9);
      final otherEnd = along(other, unit, 4);
      final otherFar = along(other, unit, 9);
      final ends = [origin, near, other, otherEnd];
      final replacements = {1: far, 3: otherFar};

      for (final kind in [PredicateKind.cong, PredicateKind.eqratio]) {
        final points = kind == PredicateKind.cong ? ends : [...ends, ...ends];
        final base = Predicate(kind, [
          for (var i = 0; i < kind.arity; i++) [a, b, c, d, e, f, g, h][i],
        ]);
        expect(
          base.holdsOn(points),
          isTrue,
          reason: 'bad rig: ${kind.name} is not true here',
        );
        for (var slot = 0; slot * 2 < kind.arity; slot++) {
          final moved = [...points];
          moved[slot * 2 + 1] = replacements[(slot * 2 + 1) % 4]!;
          final listed = lineSlots(kind).any((entry) => entry[0] == slot * 2);
          expect(
            base.holdsOn(moved),
            listed,
            reason:
                '${kind.name} slot ${slot * 2}: a segment is not its '
                'carrier, so this substitution must break it',
          );
        }
      }
    });

    test('coll and cyclic are empty for a different reason', () {
      // Not "the substitution would be unsound" but "the substitution is
      // circular": these predicates are what *builds* the closure.
      expect(lineSlots(PredicateKind.coll), isEmpty);
      expect(lineSlots(PredicateKind.cyclic), isEmpty);
      expect(lineSlots(PredicateKind.midp), isEmpty);
      expect(lineSlots(PredicateKind.simtri), isEmpty);
      expect(lineSlots(PredicateKind.contri), isEmpty);
    });

    test('every listed slot is a well-formed pair of the kind', () {
      for (final kind in PredicateKind.values) {
        final seen = <int>{};
        for (final slot in lineSlots(kind)) {
          expect(slot.length, 2);
          expect(slot[1], slot[0] + 1, reason: '$kind slots are adjacent');
          expect(slot[0].isEven, isTrue);
          expect(slot[0], lessThan(kind.arity));
          expect(seen.add(slot[0]), isTrue, reason: '$kind repeats a slot');
        }
      }
    });
  });

  group('an empty closure', () {
    test('a pair no coll has mentioned names exactly itself', () {
      // Total, and honestly so: every two distinct points name a line,
      // and what the closure knows about this one is that it has two
      // points on it. That is why the matcher can resolve unconditionally
      // instead of branching on "is this line known".
      final index = CarrierIndex();
      final line = index.lineThrough(a, b);
      expect(ids(line), ['a', 'b']);
      expect(line.isNamed, isFalse);
      expect(line.contains(a), isTrue);
      expect(line.contains(c), isFalse);
    });

    test('a lookup materializes nothing', () {
      final index = CarrierIndex();
      index.lineThrough(a, b);
      index.circleThrough(a, b, c);
      expect(index.lines, isEmpty);
      expect(index.circles, isEmpty);
    });

    test('two different pairs are two different lines', () {
      final index = CarrierIndex();
      expect(index.sameLine(a, b, c, d), isFalse);
      expect(index.sameLine(a, b, b, a), isTrue);
    });

    test('a carrier needs distinct points to be named by', () {
      final index = CarrierIndex();
      expect(() => index.lineThrough(a, a), throwsArgumentError);
      expect(() => index.circleThrough(a, b, b), throwsArgumentError);
    });
  });

  group('lines', () {
    test('one coll names one line, by any of its three pairs', () {
      final index = CarrierIndex();
      expect(index.absorb(coll(a, b, c)), isTrue);
      for (final pair in [
        [a, b],
        [a, c],
        [b, c],
        [c, a],
      ]) {
        expect(ids(index.lineThrough(pair[0], pair[1])), ['a', 'b', 'c']);
      }
      expect(index.lines.map(ids), [
        ['a', 'b', 'c'],
      ]);
    });

    test('a shared pair merges; a shared point does not', () {
      // The soundness argument, as a test: two distinct points determine
      // a line, one point determines nothing. `coll(a,b,c)` and
      // `coll(c,d,e)` meet at c and stay two lines — a pencil through a
      // point, not a line with five points on it.
      final index = CarrierIndex()
        ..absorb(coll(a, b, c))
        ..absorb(coll(c, d, e));
      expect(index.lines.length, 2);
      expect(index.sameLine(a, b, d, e), isFalse);

      // `coll(b,c,d)` shares bc with the first and cd with the second,
      // so all three are one line.
      expect(index.absorb(coll(b, c, d)), isTrue);
      expect(index.lines.map(ids), [
        ['a', 'b', 'c', 'd', 'e'],
      ]);
      expect(index.sameLine(a, b, d, e), isTrue);
    });

    test('this is what coll_transitive derives, as a union', () {
      // `coll(a,b,c) & coll(a,b,d) => coll(a,c,d)` — one derivation, at
      // the engine's per-application cost, for one spelling. The closure
      // answers every spelling at once and answers `coll(b,c,d)` too,
      // which the rule needs a second application to reach.
      final index = CarrierIndex()
        ..absorb(coll(a, b, c))
        ..absorb(coll(a, b, d));
      final line = index.lineThrough(c, d);
      expect(ids(line), ['a', 'b', 'c', 'd']);
      expect(index.sameLine(c, d, a, b), isTrue);
      expect(index.sameLine(b, c, b, d), isTrue);
    });

    test('a merge only the re-keying finds', () {
      // The case the expansion exists for. `coll(a,e,f)` shares no pair
      // with the line {a,b,c,d}: its own generators are ae, af and ef.
      // Absorbing it makes {a,d,e,f}, whose pair ad *already* names the
      // first line — so the two share two points and are one line, and
      // nothing but re-keying the merged point set discovers that.
      final index = CarrierIndex()
        ..absorb(coll(a, b, c))
        ..absorb(coll(d, e, f))
        ..absorb(coll(a, b, d));
      expect(index.lines.length, 2);

      expect(index.absorb(coll(a, e, f)), isTrue);
      expect(index.lines.map(ids), [
        ['a', 'b', 'c', 'd', 'e', 'f'],
      ]);
      expect(index.sameLine(b, c, e, f), isTrue);
    });

    test('absorbing the same coll twice grows nothing', () {
      final index = CarrierIndex();
      expect(index.absorb(coll(a, b, c)), isTrue);
      expect(index.absorb(coll(a, b, c)), isFalse);
      expect(index.absorb(coll(c, b, a)), isFalse);
      expect(index.lines.length, 1);
    });

    test('a coll implied by one already absorbed grows nothing', () {
      final index = CarrierIndex()
        ..absorb(coll(a, b, c))
        ..absorb(coll(a, b, d));
      // acd is a consequence, so re-stating it is a no-op — which is
      // exactly the signal that the rule deriving it adds nothing.
      expect(index.absorb(coll(a, c, d)), isFalse);
      expect(index.absorb(coll(b, c, d)), isFalse);
    });
  });

  group('circles', () {
    test('one cyclic names one circle, by any of its four triples', () {
      final index = CarrierIndex();
      expect(index.absorb(cyclic(a, b, c, d)), isTrue);
      for (final triple in [
        [a, b, c],
        [a, b, d],
        [a, c, d],
        [b, c, d],
        [d, b, a],
      ]) {
        expect(ids(index.circleThrough(triple[0], triple[1], triple[2])), [
          'a',
          'b',
          'c',
          'd',
        ]);
      }
      expect(index.lines, isEmpty);
    });

    test('a shared triple merges; a shared pair does not', () {
      // Three points determine a circle, two do not — the arity is the
      // whole difference from the line case, and this is
      // `cyclic_fifth_point` as a union.
      final index = CarrierIndex()
        ..absorb(cyclic(a, b, c, d))
        ..absorb(cyclic(a, b, e, f));
      expect(index.circles.length, 2);

      expect(index.absorb(cyclic(a, b, c, e)), isTrue);
      expect(index.circles.map(ids), [
        ['a', 'b', 'c', 'd', 'e', 'f'],
      ]);
      expect(index.circleThrough(d, e, f), index.circleThrough(a, b, c));
    });

    test('lines and circles are separate closures', () {
      final index = CarrierIndex()
        ..absorb(coll(a, b, c))
        ..absorb(cyclic(a, b, c, d));
      expect(index.lines.map(ids), [
        ['a', 'b', 'c'],
      ]);
      expect(index.circles.map(ids), [
        ['a', 'b', 'c', 'd'],
      ]);
    });
  });

  group('what it refuses', () {
    test('only coll and cyclic say anything about incidence', () {
      // `midp(m,a,b)` does put m on line ab, and it reaches here as the
      // `coll` that `midp_coll` derives — the closure reads incidence,
      // it does not infer it.
      final index = CarrierIndex();
      expect(index.absorb(para(a, b, c, d)), isFalse);
      expect(index.absorb(Fact(PredicateKind.perp, [a, b, c, d])), isFalse);
      expect(index.absorb(Fact(PredicateKind.midp, [a, b, c])), isFalse);
      expect(index.lines, isEmpty);
    });

    test('a coll with a repeated point names no line', () {
      final index = CarrierIndex();
      expect(index.absorb(Fact(PredicateKind.coll, [a, a, b])), isFalse);
      expect(index.lines, isEmpty);
    });
  });

  group('incremental equals rebuilt', () {
    // The property the engine needs: forward chaining absorbs one fact
    // at a time, in an order nothing controls, and must land where a
    // rebuild from the whole database lands.
    final facts = [
      coll(a, b, c),
      cyclic(a, b, d, e),
      coll(d, e, f),
      para(a, b, c, d),
      coll(b, c, d),
      cyclic(a, b, d, f),
      coll(a, e, f),
    ];

    List<List<String>> shape(CarrierIndex index) => [
      for (final carrier in index.lines) ids(carrier),
      for (final carrier in index.circles) ids(carrier),
    ];

    test('one at a time reaches the rebuilt closure', () {
      final incremental = CarrierIndex();
      for (final fact in facts) {
        incremental.absorb(fact);
      }
      expect(shape(incremental), shape(CarrierIndex.over(facts)));
    });

    test('and the order it arrives in does not matter', () {
      final forwards = CarrierIndex.over(facts);
      final backwards = CarrierIndex.over(facts.reversed);
      expect(
        shape(backwards).map((points) => points.join()).toSet(),
        shape(forwards).map((points) => points.join()).toSet(),
      );
    });
  });

  group('against a real run', () {
    test('coll_transitive derives nothing the closure does not hold', () {
      // Phase 150's document, with the auxiliary point its JGEX proof
      // needs — the rig where `coll_transitive` actually fires. Every
      // `coll` the rule derives is checked against a closure built from
      // the facts the rule did *not* derive: if the three points are
      // already on one carrier there, the rule restated a lookup.
      //
      // This is the deletion argument for Phase 151b, made before the
      // matcher moves.
      final construction = decodeDocument(
        jsonDecode(
              File('test/fixtures/perp-true-unproved.rgl').readAsStringSync(),
            )
            as Map<String, dynamic>,
      ).construction;
      GeoPoint named(String name) => construction.objects
          .whereType<GeoPoint>()
          .firstWhere((point) => point.attributes.name == name);
      construction.add(
        Midpoint(id: 'aux', point1: named('B'), point2: named('C')),
      );

      final filter = DiagramFilter.probe(construction.objects);
      final database = FactDatabase();
      seedHypotheses(database, hypotheses(construction.objects), filter);
      ProverEngine(database: database, filter: filter).run();

      final derivedByRule = [
        for (final fact in database.facts)
          if (fact.kind == PredicateKind.coll &&
              database.derivationOf(fact)!.rule == 'coll_transitive')
            fact,
      ];
      expect(
        derivedByRule,
        isNotEmpty,
        reason: 'bad rig: the rule under discussion never fired',
      );

      final withoutTheRule = CarrierIndex.over([
        for (final fact in database.facts)
          if (database.derivationOf(fact)!.rule != 'coll_transitive') fact,
      ]);
      for (final fact in derivedByRule) {
        final carrier = withoutTheRule.lineThrough(
          fact.points[0],
          fact.points[1],
        );
        expect(
          carrier.contains(fact.points[2]),
          isTrue,
          reason: '$fact is not a lookup in the closure',
        );
      }
    });

    test('and the closure is smaller than the facts it stands in for', () {
      // Nine `coll` facts on the same line are one carrier. The count is
      // the cost argument in miniature: the rule set pays per spelling,
      // the closure pays per line.
      final line = [a, b, c, d, e, f];
      final index = CarrierIndex();
      final spellings = <Fact>[];
      for (var i = 0; i + 2 < line.length; i++) {
        spellings.add(coll(line[i], line[i + 1], line[i + 2]));
      }
      index.absorbAll(spellings);
      expect(index.lines.length, 1);
      expect(ids(index.lines.single), ['a', 'b', 'c', 'd', 'e', 'f']);
      expect(
        index.lineThrough(a, f).points.length,
        greaterThan(spellings.length),
      );
    });
  });
}
