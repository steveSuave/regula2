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
/// Both hold in the figure. `tangent_lengths` (Phase 155d) derives the
/// first; the second is out of reach for a **structural** reason rather
/// than a missing rule, and the test below pins which. That distinction
/// is the whole value of the document: it separates "the table is short
/// a theorem" from "the vocabulary cannot say it".
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

  test('tangent_lengths derives the theorem, and one more besides', () {
    final database = exchange();

    expect(database.contains(Fact.of(tangentLengths())), isTrue);
    expect(
      database.derivationOf(Fact.of(tangentLengths()))!.rule,
      'tangent_lengths',
    );

    // The chord of contact is perpendicular to the centre→pole join.
    // Nothing emitted it and no rule is about it: `perp_bisector` reads
    // it off the new `cong` beside the radii `cong`, which is the sort
    // of second theorem a rule with a consumer pays for.
    expect(
      database.contains(
        Fact.of(
          Predicate(PredicateKind.perp, [
            named('S'),
            named('T'),
            named('O'),
            named('P'),
          ]),
        ),
      ),
      isTrue,
    );
  });

  test('power of the point stays out of reach, and the reason is the '
      'orientation split rather than a missing rule', () {
    final database = exchange();
    expect(database.contains(Fact.of(powerOfThePoint())), isFalse);

    // The similarity it needs is *true*: `psa` and `pbs` are similar,
    // and the orientation-free predicate says so.
    expect(
      filter.holds(
        Predicate(PredicateKind.simtri, [
          named('P'),
          named('S'),
          named('A'),
          named('P'),
          named('B'),
          named('S'),
        ]),
      ),
      isTrue,
    );

    // But the two triangles are oppositely oriented, so the shared angle
    // at `P` that `aa_simtri`'s second premise wants is *false* as a
    // mod-π eqangle. That is the direct/reflected split M-P1 defers —
    // no rule added to the table can reach around it, which is why
    // `tangent_chord` was measured and dropped rather than kept in the
    // hope of unlocking this.
    expect(
      filter.holds(
        Predicate(PredicateKind.eqangle, [
          named('P'),
          named('S'),
          named('P'),
          named('A'),
          named('P'),
          named('B'),
          named('P'),
          named('S'),
        ]),
      ),
      isFalse,
    );

    // So the ratio half of 152e's length system still has no input here:
    // the corpus's one `eqratio` is not joined by a second.
    expect(
      database.facts.where((fact) => fact.kind == PredicateKind.eqratio),
      isEmpty,
    );
  });
}
