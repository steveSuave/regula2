/// What a length closure would buy, measured rather than argued — and
/// therefore what keeps, or ends, Phase 152e's deferral of it.
///
/// 152e deferred `cong`/`eqratio` over log-lengths on the observation
/// that, fed only `cong`, the closure **is** a union-find over segments,
/// so its whole upside can be simulated without writing it. That came
/// back 0 new `cong` on five fixtures — but the deferral's premise was a
/// fact about *that corpus*, and Phase 155 was sequenced ahead of it
/// precisely because tangency changes the corpus.
///
/// **The `cong` half** (first test): tangency does change the corpus —
/// `tangent_lengths` manufactures a `cong` that was not there before —
/// and the union-find still buys nothing, and the numbers say why:
/// `entailed == cong` on every fixture, so the stored facts are already
/// the pairwise closure of their classes.
///
/// **The ratio half** (second test, session 174): Phase 163 took
/// `provoleas2.json` to quiescence holding five `eqratio`s sharing a
/// segment, which is the input the deferral was measured without. A
/// ℚ-linear span over log-lengths — the deferred system itself,
/// simulated — entailed **one new `cong` there, `|AB| = |LO|`**, an
/// integer combination of the intercept fact `|MO|/|ON| = |OB|/|LO|`
/// and the similar-triangle fact `|MA|/|AO| = |AO|/|AB|` with a
/// coefficient 2 on `l_AO` that no union-find can form, and 43
/// `eqratio`s chained through it (2 more on `perp-true-unproved.rgl`);
/// the midpoint constant `ln 2` adds nothing on this corpus, and the
/// filter refuses none of it. So the deferral's premise no longer held.
///
/// **Phase 165 then built it, and this file changed job.** The `cong`
/// column is 0 everywhere now — the exchange publishes what the closure
/// entails, so there is no upside left to measure — and a `cong`
/// reappearing here would be a *defect*, a document the publisher is
/// missing. The `eqratio` column stays, because `eqratio` is answered
/// on ask and never published; it fell from 43 to 23 on `provoleas2`
/// when the published `cong` brought 20 of them within reach of the
/// stored `cong`s alone.
///
/// **The third test is the half those two cannot state.** "Nothing is
/// outstanding" is equally true of a publisher that never ran, so it
/// pins what was actually published: one `cong` in the whole corpus,
/// screened by the filter and verifying as a certificate. The fixture
/// list is the full seven from `benchmark/prover_chunk_bench.dart`
/// since Phase 165; it was six before, which left `tangent-chord.rgl`
/// unmeasured here for no reason anyone recorded.
library;

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
import 'package:regula/domain/prover/length_translation.dart';
import 'package:regula/domain/prover/predicate.dart';
import 'package:regula/domain/prover/proof.dart';
import 'package:regula/domain/prover/prover.dart';
import 'package:regula/domain/prover/rational.dart';
import 'package:regula/domain/prover/rule_engine.dart';

/// A ℚ-linear span over log-lengths — what the deferred ratio system
/// *is*, simulated here in the same spirit as the union-find above.
///
/// Each named segment is a variable `l_ab = log|ab|`; `cong(a,b,c,d)` is
/// the row `l_ab − l_cd = 0`, `eqratio(a,b,c,d,e,f,g,h)` is
/// `l_ab − l_cd − l_ef + l_gh = 0`, and `midp(m,a,b)` is `l_ma − l_mb = 0`
/// beside `l_ab − l_ma = ln 2`, with `ln 2` carried as one more
/// variable that no statement may lean on. Lengths are real numbers with
/// no modulus, so — unlike the angle system (PLAN §"AR is a ℤ-module") —
/// rational pivots are sound here: `2·l_ab = 2·l_cd` *does* say
/// `|ab| = |cd|`. Entailment is membership of the row span.
class _LengthSpan {
  /// Reduced rows keyed by their leading variable.
  final Map<String, Map<String, Rational>> _rows = {};

  /// Reduces [row] against the span, in place; empty when entailed.
  Map<String, Rational> _reduce(Map<String, Rational> row) {
    row = Map.of(row)..removeWhere((_, c) => c.isZero);
    while (true) {
      final eliminable = (row.keys.where(_rows.containsKey).toList()..sort());
      if (eliminable.isEmpty) return row;
      final leading = eliminable.first;
      final pivot = _rows[leading]!;
      final scale = row[leading]!;
      for (final entry in pivot.entries) {
        final next =
            (row[entry.key] ?? Rational.whole(0)) - scale * entry.value;
        if (next.isZero) {
          row.remove(entry.key);
        } else {
          row[entry.key] = next;
        }
      }
    }
  }

  void add(Map<String, Rational> row) {
    final reduced = _reduce(row);
    if (reduced.isEmpty) return;
    final leading = (reduced.keys.toList()..sort()).first;
    final scale = reduced[leading]!;
    _rows[leading] = {
      for (final entry in reduced.entries) entry.key: entry.value / scale,
    };
  }

  bool entails(Map<String, Rational> row) => _reduce(row).isEmpty;

  /// A canonical representative of [row]'s coset: two rows reduce to the
  /// same residual exactly when their difference is entailed. Every
  /// pivot variable is eliminated, smallest first, so the residual lives
  /// on the non-pivot variables alone and is unique per coset.
  String residual(Map<String, Rational> row) {
    final reduced = _reduce(row);
    final keys = reduced.keys.toList()..sort();
    return [for (final key in keys) '$key:${reduced[key]}'].join(' ');
  }

  /// The segment variables the span mentions, `ln 2` excluded.
  Set<String> get variables =>
      {for (final row in _rows.values) ...row.keys}..remove(ln2);

  static const ln2 = 'ln 2';

  static Map<String, Rational> row(Map<String, int> coefficients) => {
    for (final entry in coefficients.entries)
      entry.key: Rational.whole(entry.value),
  };
}

void main() {
  const fixtures = [
    'test/fixtures/locus3.json',
    'test/fixtures/apatitos-topos.rgl',
    'test/fixtures/no-locus.rgl',
    'test/fixtures/perp-true-unproved.rgl',
    'test/fixtures/provoleas2.json',
    'test/fixtures/tangent-chase.rgl',
    'test/fixtures/tangent-chord.rgl',
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
      // Every fixture reaches quiescence since Phase 163 deleted
      // `eqangle_transitive` — `provoleas2.json` included, at 25 826
      // applications, where it used to be still deriving after 200 000.
      final prover = Prover(database: database, filter: filter)..run();
      expect(prover.isComplete, isTrue, reason: '$path did not converge');
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

    // And the ratio half, which is the genuinely ℚ content. Until Phase
    // 163 this pinned *one* `eqratio` in the whole corpus,
    // `perp-true-unproved.rgl`'s — the tangency document contributes
    // none, not for want of a rule but because power of the point needs
    // the direct/reflected split M-P1 defers (pinned in
    // `tangent_chase_test.dart`). Then `provoleas2.json` reached
    // quiescence and holds **five**: three spellings of one
    // `simtri_eqratio` and two `intercept_eqratio`s, and they share the
    // segment `AO` — `|MA|/|AO| = |AO|/|AB|` beside
    // `|AO|/|AN| = |ON|/|AO|` is a chain a ratio closure would close.
    // That is the input 152e's deferral was measured without; the next
    // test is the re-measurement, and this pin moves to the new count so
    // it fires again on the next change rather than on this one.
    expect(totalEqratio, 6);
  });

  /// What a ℚ closure over log-lengths would entail beyond the exchange,
  /// on the whole vocabulary it speaks: `cong` (a zero difference the
  /// union-find above cannot always see — `2·l₁ = l₂ + l₃` beside
  /// `2·l₂ = l₁ + l₃` says `l₁ = l₂` only over ℚ) and `eqratio`.
  /// Screened through the filter like every publication; a refusal is
  /// counted rather than hidden, because an entailed statement the
  /// diagram denies would be a soundness finding.
  ({
    int segments,
    int novelCong,
    int novelEqratio,
    int byCongAlone,
    int refused,
    List<Fact> novel,
  })
  ratioUpside(
    FactDatabase database,
    Map<String, GeoObject> byId,
    DiagramFilter filter, {
    bool withConstant = true,
  }) {
    String segment(String a, String b) =>
        a.compareTo(b) <= 0 ? '$a|$b' : '$b|$a';
    Map<String, int> combine(List<(String, int)> terms) {
      final row = <String, int>{};
      for (final (key, c) in terms) {
        row[key] = (row[key] ?? 0) + c;
      }
      return row;
    }

    final span = _LengthSpan();
    final congOnly = _LengthSpan();
    for (final fact in database.facts) {
      final p = fact.points.map((point) => point.id).toList();
      switch (fact.kind) {
        case PredicateKind.cong:
          final row = _LengthSpan.row(
            combine([(segment(p[0], p[1]), 1), (segment(p[2], p[3]), -1)]),
          );
          span.add(row);
          congOnly.add(row);
        case PredicateKind.eqratio:
          span.add(
            _LengthSpan.row(
              combine([
                (segment(p[0], p[1]), 1),
                (segment(p[2], p[3]), -1),
                (segment(p[4], p[5]), -1),
                (segment(p[6], p[7]), 1),
              ]),
            ),
          );
        case PredicateKind.midp:
          span.add(
            _LengthSpan.row(
              combine([(segment(p[0], p[1]), 1), (segment(p[0], p[2]), -1)]),
            ),
          );
          if (withConstant) {
            span.add(
              _LengthSpan.row(
                combine([
                  (segment(p[1], p[2]), 1),
                  (segment(p[0], p[1]), -1),
                  (_LengthSpan.ln2, -1),
                ]),
              ),
            );
          }
        default:
          break;
      }
    }

    final variables = span.variables.toList()..sort();
    List<GeoPoint> ends(String key) => [
      for (final id in key.split('|')) byId[id]! as GeoPoint,
    ];

    var novelCong = 0;
    var novelEqratio = 0;
    var byCongAlone = 0;
    var refused = 0;
    final novel = <Fact>[];
    void consider(Fact fact, Map<String, Rational> row) {
      if (database.contains(fact)) return;
      if (!filter.holds(fact.statement)) {
        refused++;
        return;
      }
      if (fact.kind == PredicateKind.cong) {
        novelCong++;
        novel.add(fact);
      } else if (congOnly.entails(row)) {
        byCongAlone++;
      } else {
        novelEqratio++;
        novel.add(fact);
      }
    }

    // `cong`: every pair of variables whose difference is entailed.
    for (var i = 0; i < variables.length; i++) {
      for (var j = i + 1; j < variables.length; j++) {
        final row = _LengthSpan.row({variables[i]: 1, variables[j]: -1});
        if (!span.entails(row)) continue;
        consider(
          Fact(PredicateKind.cong, [
            ...ends(variables[i]),
            ...ends(variables[j]),
          ]),
          row,
        );
      }
    }

    // `eqratio`: `l₁ − l₂ − l₃ + l₄ = 0` is entailed exactly when the
    // residuals of `l₁ − l₂` and `l₃ − l₄` agree, so bucket the ordered
    // pairs by residual and read the statements off each bucket — n²
    // reductions instead of n⁴. Four distinct segments, or the statement
    // is a `cong` in disguise (`|ab|/|ab| = |cd|/|ef|`) and counted
    // above.
    final buckets = <String, List<(String, String)>>{};
    for (final a in variables) {
      for (final b in variables) {
        if (a == b) continue;
        final key = span.residual(_LengthSpan.row({a: 1, b: -1}));
        buckets.putIfAbsent(key, () => []).add((a, b));
      }
    }
    final seen = <Fact>{};
    for (final pairs in buckets.values) {
      for (var i = 0; i < pairs.length; i++) {
        for (var j = i + 1; j < pairs.length; j++) {
          final (a, b) = pairs[i];
          final (c, d) = pairs[j];
          if ({a, b, c, d}.length != 4) continue;
          final fact = Fact(PredicateKind.eqratio, [
            ...ends(a),
            ...ends(b),
            ...ends(c),
            ...ends(d),
          ]);
          if (!seen.add(fact)) continue;
          consider(
            fact,
            _LengthSpan.row(combine([(a, 1), (b, -1), (c, -1), (d, 1)])),
          );
        }
      }
    }
    return (
      segments: variables.length,
      novelCong: novelCong,
      novelEqratio: novelEqratio,
      byCongAlone: byCongAlone,
      refused: refused,
      novel: novel,
    );
  }

  test('what the publisher actually put there, per fixture', () {
    // The other half of Phase 165's regression, and the one the two
    // tests above cannot state: they measure what is *entailed* and
    // find nothing outstanding, which is equally true of a publisher
    // that never ran. This pins what it published.
    //
    // One fact in the whole corpus, and that is the phase's honest
    // yield: the closure's value is not volume, it is reaching a `cong`
    // the table cannot. Every one is screened by the same filter DD
    // screens with, and every one verifies as a certificate.
    const expected = {
      'test/fixtures/locus3.json': 0,
      'test/fixtures/apatitos-topos.rgl': 0,
      'test/fixtures/no-locus.rgl': 0,
      'test/fixtures/perp-true-unproved.rgl': 0,
      'test/fixtures/provoleas2.json': 1,
      'test/fixtures/tangent-chase.rgl': 0,
      'test/fixtures/tangent-chord.rgl': 0,
    };
    for (final path in fixtures) {
      final construction = load(path);
      final filter = DiagramFilter.probe(construction.objects);
      final database = FactDatabase();
      seedHypotheses(database, hypotheses(construction.objects), filter);
      Prover(database: database, filter: filter).run(maxApplications: 30000);

      final published = [
        for (final fact in database.facts)
          if (database.derivationOf(fact)!.rule == lengthArithmeticRule) fact,
      ];
      expect(published, hasLength(expected[path]!), reason: path);
      for (final fact in published) {
        expect(
          fact.kind,
          PredicateKind.cong,
          reason: '$path: only cong is published',
        );
        expect(
          filter.holds(fact.statement),
          isTrue,
          reason: '$path: an unscreened publication',
        );
        expect(
          Proof.of(fact, database).verify(),
          isEmpty,
          reason: '$path: the published step is not a certificate',
        );
      }
    }
  });

  test('the ratio half entails no cong the exchange does not hold — '
      'which is Phase 165 having landed', () {
    // Per fixture: new `cong`, new `eqratio` beyond what pairs of stored
    // `cong`s already say.
    //
    // **The cong column read 1 on `provoleas2` until Phase 165, and it
    // reading 0 is the phase working**: the exchange now runs the same
    // closure and publishes what it entails, so measuring the upside of
    // a system that is switched on can only come back empty. The
    // tripwire keeps its value in the other direction — a corpus change
    // that puts a `cong` back in this column is a document the
    // publisher is missing, which is a defect and not an opportunity.
    //
    // The `eqratio` column is the half that stays: it is answered on
    // ask through `Prover.resolve` and never published, so these are
    // statements the closure *would* confirm if a question named one.
    const expected = {
      'test/fixtures/locus3.json': (cong: 0, eqratio: 0),
      'test/fixtures/apatitos-topos.rgl': (cong: 0, eqratio: 0),
      'test/fixtures/no-locus.rgl': (cong: 0, eqratio: 0),
      'test/fixtures/perp-true-unproved.rgl': (cong: 0, eqratio: 2),
      // 43 until the publisher landed. Putting `|AB| = |LO|` in the
      // database moved 20 of them into `byCongAlone`: with that one
      // `cong` stored, a union-find over stored `cong`s reaches them,
      // and only 23 still need the ratio rows.
      'test/fixtures/provoleas2.json': (cong: 0, eqratio: 23),
      'test/fixtures/tangent-chase.rgl': (cong: 0, eqratio: 0),
      'test/fixtures/tangent-chord.rgl': (cong: 0, eqratio: 0),
    };
    for (final path in fixtures) {
      final construction = load(path);
      final filter = DiagramFilter.probe(construction.objects);
      final database = FactDatabase();
      seedHypotheses(database, hypotheses(construction.objects), filter);
      Prover(database: database, filter: filter).run();
      final byId = {
        for (final object in construction.objects) object.id: object,
      };
      final upside = ratioUpside(database, byId, filter);
      final want = expected[path]!;

      // Every entailed statement survives the filter: the algebra is
      // sound on this corpus, the same data point 152e's `eqangle`
      // measurement made.
      expect(
        upside.refused,
        0,
        reason: '$path: the filter refused an entailment',
      );
      expect(upside.novelCong, want.cong, reason: '$path: new cong');
      expect(upside.novelEqratio, want.eqratio, reason: '$path: new eqratio');

      // The 1:2 of a midpoint is not what the chain needs — the same
      // count without the `ln 2` row. Recorded because DDAR's ratio
      // table carries constants and ours need not, yet.
      final without = ratioUpside(database, byId, filter, withConstant: false);
      expect(without.novelCong, want.cong, reason: '$path: cong needs ln 2');
      expect(
        without.novelEqratio,
        want.eqratio,
        reason: '$path: eqratio needs ln 2',
      );

      if (path.endsWith('provoleas2.json')) {
        // What used to be the one novel `cong` here is now a fact the
        // exchange holds, under the rule that says how it got there.
        final cong = database.facts.singleWhere(
          (fact) =>
              fact.kind == PredicateKind.cong &&
              fact.points.map(describePoint).join() == 'ABLO',
        );
        expect(
          database.derivationOf(cong)!.rule,
          lengthArithmeticRule,
          reason: 'the publisher is what put |AB| = |LO| there',
        );
      }
    }
  });
}
