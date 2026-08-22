import 'dart:convert';
import 'dart:io';

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

  Fact coll(GeoPoint x, GeoPoint y, GeoPoint z) =>
      Fact(PredicateKind.coll, [x, y, z]);
  Fact cyclic(GeoPoint w, GeoPoint x, GeoPoint y, GeoPoint z) =>
      Fact(PredicateKind.cyclic, [w, x, y, z]);
  Fact para(GeoPoint w, GeoPoint x, GeoPoint y, GeoPoint z) =>
      Fact(PredicateKind.para, [w, x, y, z]);

  List<String> ids(Carrier carrier) => [
    for (final point in carrier.points) point.id,
  ];

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
