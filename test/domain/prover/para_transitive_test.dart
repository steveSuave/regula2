import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:regula/application/persistence/construction_codec.dart';
import 'package:regula/domain/prover/diagram_filter.dart';
import 'package:regula/domain/prover/fact.dart';
import 'package:regula/domain/prover/fact_database.dart';
import 'package:regula/domain/prover/hypotheses.dart';
import 'package:regula/domain/prover/predicate.dart';
import 'package:regula/domain/prover/prover.dart';
import 'package:regula/domain/prover/rule.dart';
import 'package:regula/domain/prover/rule_engine.dart';

/// `para_transitive` was deleted from the table in Phase 166, on the
/// argument Phase 163 made for `eqangle_transitive` (PLAN §"A row sum is
/// not a rule"): it is a row sum, the angle closure publishes `para`,
/// so every composite the rule could store is stored by the exchange
/// anyway. Measured one rule at a time over the seven fixtures: no fact
/// count moves, and applications to quiescence fall 43 % on `locus3`,
/// 31 % on `perp-true-unproved`, 42 % on `provoleas2`.
///
/// What this pins is the argument, on the fixture with the most `para`s:
/// at quiescence, every composite of two stored `para`s sharing a side
/// is itself stored — by the publisher, without the rule.
void main() {
  test('para transitivity is the closure\'s, not a rule\'s', () {
    expect(ddCoreRules.map((r) => r.name), isNot(contains('para_transitive')));

    final construction = decodeDocument(
      jsonDecode(File('test/fixtures/provoleas2.json').readAsStringSync())
          as Map<String, dynamic>,
    ).construction;
    final filter = DiagramFilter.probe(construction.objects);
    final database = FactDatabase();
    seedHypotheses(database, hypotheses(construction.objects), filter);
    final prover = Prover(database: database, filter: filter)..run();
    expect(prover.isComplete, isTrue);

    final paras = database.facts
        .where((fact) => fact.kind == PredicateKind.para)
        .toList();
    // 46 stored `para`s — the count the rule's presence did not change.
    expect(paras, hasLength(46));

    var composites = 0;
    for (final first in paras) {
      for (final second in paras) {
        if (identical(first, second)) continue;
        // Every way the two can share a line, in either orientation:
        // first = (p, q), second = (r, s); a shared side named by the
        // same unordered pair composes the other two.
        final fp = [first.points.sublist(0, 2), first.points.sublist(2, 4)];
        final sp = [second.points.sublist(0, 2), second.points.sublist(2, 4)];
        for (var i = 0; i < 2; i++) {
          for (var j = 0; j < 2; j++) {
            final sharedA = fp[i];
            final sharedB = sp[j];
            final same =
                (identical(sharedA[0], sharedB[0]) &&
                    identical(sharedA[1], sharedB[1])) ||
                (identical(sharedA[0], sharedB[1]) &&
                    identical(sharedA[1], sharedB[0]));
            if (!same) continue;
            final left = fp[1 - i];
            final right = sp[1 - j];
            final composite = Fact(PredicateKind.para, [...left, ...right]);
            // The composite of `para(l, m)` and `para(m, l)` is
            // `para(l, l)`, which is no statement; skip it.
            if ((identical(left[0], right[0]) &&
                    identical(left[1], right[1])) ||
                (identical(left[0], right[1]) &&
                    identical(left[1], right[0]))) {
              continue;
            }
            composites++;
            expect(
              database.contains(composite),
              isTrue,
              reason: '$composite from $first and $second',
            );
          }
        }
      }
    }
    // The property is vacuous without chains; there are plenty.
    expect(composites, greaterThan(100));
  });
}
