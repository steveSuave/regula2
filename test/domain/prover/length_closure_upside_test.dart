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

/// What a length closure over `cong` would buy, measured rather than
/// argued — and therefore what keeps Phase 152e's deferral of it alive.
///
/// 152e deferred `cong`/`eqratio` over log-lengths on the observation
/// that, fed only `cong`, the closure **is** a union-find over segments,
/// so its whole upside can be simulated without writing it. That came
/// back 0 new `cong` on five fixtures — but the deferral's premise was a
/// fact about *that corpus*, and Phase 155 was sequenced ahead of it
/// precisely because tangency changes the corpus.
///
/// It does change it: `tangent_lengths` manufactures a `cong` that was
/// not there before. The closure still buys nothing, and the numbers say
/// why: `entailed == cong` on every fixture, so the stored facts are
/// already the pairwise closure of their classes and a union-find has no
/// work left to do.
///
/// This is a tripwire, not a claim that the closure is worthless. The
/// day a document makes `newCong` non-zero, this test fails and that is
/// the signal to build the thing.
void main() {
  const fixtures = [
    'test/fixtures/locus3.json',
    'test/fixtures/apatitos-topos.rgl',
    'test/fixtures/no-locus.rgl',
    'test/fixtures/perp-true-unproved.rgl',
    'test/fixtures/provoleas2.json',
    'test/fixtures/tangent-chase.rgl',
  ];

  Construction load(String path) => decodeDocument(
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>,
  ).construction;

  /// Segments in one equivalence class, keyed by unordered point pair.
  ({int entailed, int novel}) closureUpside(
    FactDatabase database,
    Map<String, GeoObject> byId,
  ) {
    final parent = <String, String>{};
    String find(String x) {
      parent.putIfAbsent(x, () => x);
      while (parent[x] != x) {
        parent[x] = parent[parent[x]!]!;
        x = parent[x]!;
      }
      return x;
    }

    void union(String a, String b) {
      final rootA = find(a);
      final rootB = find(b);
      if (rootA != rootB) parent[rootA] = rootB;
    }

    String segment(String a, String b) =>
        a.compareTo(b) <= 0 ? '$a|$b' : '$b|$a';

    for (final fact in database.facts) {
      if (fact.kind != PredicateKind.cong) continue;
      final points = fact.points;
      union(
        segment(points[0].id, points[1].id),
        segment(points[2].id, points[3].id),
      );
    }
    final classes = <String, List<String>>{};
    for (final s in parent.keys) {
      classes.putIfAbsent(find(s), () => []).add(s);
    }
    var entailed = 0;
    var novel = 0;
    for (final members in classes.values) {
      for (var i = 0; i < members.length; i++) {
        for (var j = i + 1; j < members.length; j++) {
          entailed++;
          final left = members[i].split('|');
          final right = members[j].split('|');
          final fact = Fact.of(
            Predicate(PredicateKind.cong, [
              byId[left[0]]! as GeoPoint,
              byId[left[1]]! as GeoPoint,
              byId[right[0]]! as GeoPoint,
              byId[right[1]]! as GeoPoint,
            ]),
          );
          if (!database.contains(fact)) novel++;
        }
      }
    }
    return (entailed: entailed, novel: novel);
  }

  test('a length closure entails no cong the exchange does not hold, on '
      'any fixture in the corpus', () {
    var totalEqratio = 0;
    for (final path in fixtures) {
      final construction = load(path);
      final filter = DiagramFilter.probe(construction.objects);
      final database = FactDatabase();
      seedHypotheses(database, hypotheses(construction.objects), filter);
      // `provoleas2.json` never reaches a fixpoint (measured: still
      // deriving after 200 000 applications), so it is compared at a
      // budget rather than at quiescence.
      Prover(
        database: database,
        filter: filter,
      ).run(maxApplications: path.contains('provoleas2') ? 20000 : null);
      final byId = {
        for (final object in construction.objects) object.id: object,
      };
      final upside = closureUpside(database, byId);
      final congs = database.facts
          .where((fact) => fact.kind == PredicateKind.cong)
          .length;

      expect(upside.novel, 0, reason: '$path entails new cong');
      // The sharper form of the same finding: the stored facts *are* the
      // pairwise closure of their classes, so there is nothing to close.
      expect(upside.entailed, congs, reason: '$path is not saturated');

      totalEqratio += database.facts
          .where((fact) => fact.kind == PredicateKind.eqratio)
          .length;
    }

    // And the ratio half, which is the genuinely ℚ content: still one
    // `eqratio` in the whole corpus, `perp-true-unproved.rgl`'s. The
    // tangency document contributes none — not for want of a rule but
    // because power of the point needs the direct/reflected split M-P1
    // defers (pinned in `tangent_chase_test.dart`).
    expect(totalEqratio, 1);
  });
}
