import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:regula/application/persistence/construction_codec.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/geo_object.dart';
import 'package:regula/domain/prover/diagram_filter.dart';
import 'package:regula/domain/prover/fact.dart';
import 'package:regula/domain/prover/fact_database.dart';
import 'package:regula/domain/prover/hypotheses.dart';
import 'package:regula/domain/prover/predicate.dart';
import 'package:regula/domain/prover/prover.dart';
import 'package:regula/domain/prover/rule_engine.dart';

/// `test/fixtures/tangent-chase.rgl`, and what it can and cannot yet be
/// asked (Phase 155).
///
/// The corpus had no document whose theorem is a tangency chase, and
/// Phase 152e's four zero measurements were every one of them limited by
/// the corpus rather than by the algebra — so adding the tangency rules
/// without a document that exercises them would repeat that mistake
/// exactly. This is the document. Two tangents from an external point
/// `P` to a circle centred `O`, both points of contact drawn (`S`, `T`),
/// and a secant through `P` meeting the circle at `A` and `B`.
///
/// Its two theorems are the two the phase's rule box names:
///
/// - **tangent-length equality**, `cong(P, S, P, T)` — the `cong` that
///   152e's length-system deferral was measured without;
/// - **power of the point**, `|PA|·|PB| = |PS|²` — an `eqratio`, and the
///   ratio-chain input the whole corpus holds exactly one of.
///
/// Both hold in the figure and **neither is derived**, which is the
/// state this phase's rule box changes. The tests below pin that gap as
/// a measurement rather than describing it, so when a rule lands the
/// number that moves is visible.
void main() {
  late Construction construction;
  late DiagramFilter filter;

  Construction load() => decodeDocument(
    jsonDecode(File('test/fixtures/tangent-chase.rgl').readAsStringSync())
        as Map<String, dynamic>,
  ).construction;

  setUp(() {
    construction = load();
    filter = DiagramFilter.probe(construction.objects);
  });

  GeoPoint named(String name) => construction.objects
      .whereType<GeoPoint>()
      .firstWhere((point) => point.attributes.name == name);

  Predicate tangentLengths() => Predicate(PredicateKind.cong, [
    named('P'),
    named('S'),
    named('P'),
    named('T'),
  ]);

  /// |PA| / |PS| = |PS| / |PB|.
  Predicate powerOfThePoint() => Predicate(PredicateKind.eqratio, [
    named('P'),
    named('A'),
    named('P'),
    named('S'),
    named('P'),
    named('S'),
    named('P'),
    named('B'),
  ]);

  FactDatabase exchange() {
    final database = FactDatabase();
    seedHypotheses(database, hypotheses(construction.objects), filter);
    Prover(database: database, filter: filter).run();
    return database;
  }

  test('the tangency hypotheses reach the document', () {
    final emitted = hypotheses(construction.objects);
    final tangency = emitted.where(
      (predicate) =>
          predicate.kind == PredicateKind.perp &&
          predicate.points.any((point) => identical(point, named('P'))),
    );

    // One per tangent: `perp(O, S, S, P)` and `perp(O, T, T, P)`. Before
    // Phase 155 this document said nothing at all about its tangents.
    expect(tangency, hasLength(2));
    expect(
      emitted,
      contains(
        predicate(
          (Predicate p) =>
              Fact.of(p) ==
              Fact.of(
                Predicate(PredicateKind.perp, [
                  named('O'),
                  named('S'),
                  named('S'),
                  named('P'),
                ]),
              ),
        ),
      ),
    );
  });

  test('both theorems are true in the figure', () {
    // Not a tautology: it is what says the rig is a rig. A statement the
    // filter refuted would make the gap below meaningless.
    expect(filter.holds(tangentLengths()), isTrue);
    expect(filter.holds(powerOfThePoint()), isTrue);
  });

  test('and neither is derived — this is the gap, measured', () {
    final database = exchange();

    expect(database.contains(Fact.of(tangentLengths())), isFalse);
    expect(database.contains(Fact.of(powerOfThePoint())), isFalse);
  });

  test('the ratio half has no input at all, which is the sharper half of '
      'the finding', () {
    final database = exchange();

    // 152e deferred the length system on measured evidence: 0 new `cong`
    // across five fixtures and *one* `eqratio` in the whole corpus. This
    // document adds no `eqratio` either — not because the algebra cannot
    // hold one, but because no rule in the table manufactures one. Power
    // of the point is the rule that would, and until it exists the ratio
    // half of the length system has nothing to work on here.
    expect(
      database.facts.where((fact) => fact.kind == PredicateKind.eqratio),
      isEmpty,
    );
  });
}
