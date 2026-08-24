import 'predicate.dart';

/// One DD rule: premises over pattern variables, entailing a conclusion
/// whose variables are all bound by the premises — a rule can only name
/// points its premises already found, never conjure new ones, which is
/// what keeps matching a join rather than a search.
///
/// Rules are *data* the engine matches (PLAN §M-P2: "rules, not code"),
/// written in the DD sources' own notation so the table reads against
/// them: `'cong(o,a,o,b) & cong(p,a,p,b) => perp(o,p,a,b)'`.
///
/// **A rule's implicit non-degeneracy conditions are carried by the
/// numeric screen, not by the pattern.** The DD sources attach `ncoll`
/// side conditions to rules like the inscribed-angle converse; here
/// every candidate conclusion is screened through the `DiagramFilter`
/// before insertion, which refuses exactly the degenerate instances
/// those side conditions name — a collinear "cyclic" is numerically
/// false in every configuration. The engine additionally refuses
/// *structural* degeneracy at binding time (a zero-length segment, a
/// repeated point of a `coll`/`cyclic`, an identical triangle pair),
/// which is a property of the tuple, not the configuration.
class Rule {
  Rule(this.name, this.premises, this.conclusion) {
    final bound = <String>{
      for (final premise in premises) ...premise.variables,
    };
    final free = conclusion.variables.where((v) => !bound.contains(v));
    if (free.isNotEmpty) {
      throw ArgumentError.value(
        conclusion,
        'conclusion',
        '$name concludes over unbound variables: ${free.join(', ')}',
      );
    }
  }

  /// Parses `'kind(v,…) & kind(v,…) => kind(v,…)'`. Throws
  /// [ArgumentError] on an unknown kind, a wrong arity, or a conclusion
  /// variable no premise binds — a malformed rule is a programmer error
  /// caught when the table is built, not a match that silently never
  /// fires.
  factory Rule.parse(String name, String spec) {
    final sides = spec.split('=>');
    if (sides.length != 2) {
      throw ArgumentError.value(spec, 'spec', 'expected exactly one =>');
    }
    return Rule(name, [
      for (final atom in sides[0].split('&')) RulePattern.parse(atom),
    ], RulePattern.parse(sides[1]));
  }

  final String name;
  final List<RulePattern> premises;
  final RulePattern conclusion;

  @override
  String toString() => '$name: ${premises.join(' & ')} => $conclusion';
}

/// A predicate kind over pattern variables instead of points.
class RulePattern {
  RulePattern(this.kind, List<String> variables)
    : variables = List.unmodifiable(variables) {
    if (variables.length != kind.arity) {
      throw ArgumentError.value(
        variables,
        'variables',
        '${kind.name} takes ${kind.arity} variables, '
            'got ${variables.length}',
      );
    }
  }

  factory RulePattern.parse(String atom) {
    final match = RegExp(r'^\s*(\w+)\s*\(([^)]*)\)\s*$').firstMatch(atom);
    if (match == null) {
      throw ArgumentError.value(atom, 'atom', 'expected kind(v, …)');
    }
    final kindName = match.group(1)!;
    final kind = PredicateKind.values.asNameMap()[kindName];
    if (kind == null) {
      throw ArgumentError.value(atom, 'atom', 'unknown kind $kindName');
    }
    return RulePattern(kind, [
      for (final variable in match.group(2)!.split(',')) variable.trim(),
    ]);
  }

  final PredicateKind kind;
  final List<String> variables;

  @override
  String toString() => '${kind.name}(${variables.join(',')})';
}

/// The DD core (PLAN §M-P2b): the forward-chaining rule set, from the
/// open DDAR/Newclid sources — their *statements*, restated over this
/// vocabulary, never their code. Kept deliberately small: every rule
/// here is a classical theorem a reader can check line by line, and the
/// per-rule tests check each numerically the same way the fact table is
/// pinned — a rule that is not actually a theorem would let the filter's
/// screen mask an unsound proof step.
final List<Rule> ddCoreRules = List.unmodifiable([
  // Collinearity propagates, and this is the family Phase 143 left out.
  //
  // The vocabulary is point-tuples, so a *line* is named by a pair of
  // points on it — and one line has many such names. `hypotheses` was
  // built to emit every witness pair for that reason, but a fact a
  // *rule* derives gets no such help: without these, `perp(A,B,C,D)` and
  // a `coll` putting E on line CD can never yield `perp(A,B,C,E)`, and
  // the run stalls holding the statement it needs under the wrong name.
  // Phase 150 found this by translating a JGEX proof of a user document
  // (`test/fixtures/perp-true-unproved.rgl`) step by step and watching
  // where ours could not follow.
  //
  // `para_coll`, the exact analogue for parallels, is deliberately
  // *not* here. It was written, rigged and measured: it derives nothing
  // new on any fixture, including the one that motivated the family.
  // The hole it would close is real in principle and it is one line the
  // day a document needs it — but a rule with no consumer is a rule
  // whose cost is paid on every pivot for nothing.
  Rule.parse('coll_transitive', 'coll(a,b,c) & coll(a,b,d) => coll(a,c,d)'),
  Rule.parse(
    'perp_coll',
    'perp(a,b,c,d) & coll(a,b,e) & coll(a,b,f) => perp(e,f,c,d)',
  ),
  // The orthocentre, as a closure property rather than as a point: two
  // of a triangle's altitudes force the third. Written on four points
  // because that is what it is — the orthocentric system, in which each
  // point is the orthocentre of the other three.
  Rule.parse('orthocentre', 'perp(a,b,c,d) & perp(a,c,b,d) => perp(a,d,b,c)'),
  // Direction algebra: parallelism and perpendicularity compose.
  Rule.parse(
    'para_transitive',
    'para(a,b,c,d) & para(c,d,e,f) => para(a,b,e,f)',
  ),
  Rule.parse(
    'perp_perp_para',
    'perp(a,b,c,d) & perp(c,d,e,f) => para(a,b,e,f)',
  ),
  Rule.parse(
    'para_perp_perp',
    'para(a,b,c,d) & perp(c,d,e,f) => perp(a,b,e,f)',
  ),
  // Equality chains.
  Rule.parse(
    'cong_transitive',
    'cong(a,b,c,d) & cong(c,d,e,f) => cong(a,b,e,f)',
  ),
  // `eqangle_transitive` — `eqangle(a,b,c,d,e,f,g,h) &
  // eqangle(e,f,g,h,p,q,r,s) => eqangle(a,b,c,d,p,q,r,s)` — is **not
  // here** (Phase 163). It is a row sum, which is to say it is what the
  // angle closure *is*: with M-P3 in the exchange, every statement it
  // could store is already entailed, and `Prover.resolve` answers an
  // ask against the closure. It was also the most expensive line in the
  // table by a wide margin, for a reason PLAN §"Two closures" named
  // before it was measured: an `eqangle` has 128 orbit forms, and a
  // premise pair with no shared variable lets every form of the pivot
  // join every form of every other `eqangle` — 16 384 bind attempts per
  // pair, none of them charged as an application, which is the
  // "uncharged pass" Phase 161 priced without naming.
  //
  // Measured one rule at a time, as 152e asked, over all seven fixtures
  // with the rest of the table unchanged. Dropping it: **no fact of any
  // other kind is lost anywhere**, and the only facts lost at all are 15
  // `eqangle`s on `provoleas2.json`, every one of which the closure
  // resolves. What it buys: `apatitos-topos.rgl` 1 272 → 49 ms to
  // quiescence on the same 31 facts, `tangent-chase.rgl` 5 261 → 186 ms
  // on the same 46, `locus3` 72 → 8 ms — and `provoleas2.json`, which
  // had never reached quiescence, **completes** at 25 810 applications
  // with 115 facts where the capped run held 82: +27 `para`, +4 `perp`,
  // +3 `coll`, +5 `eqratio`, a `midp`, a `simtri` and a `contri` the
  // transitive join had been starving of pivots (and 9 fewer stored
  // `eqangle`s, all of them one `resolve` away).
  //
  // The same measurement on the table's other row sums, recorded and
  // not acted on: `para_transitive` likewise loses nothing on any
  // fixture (and cuts applications 30–45 % on three); `perp_perp_para`
  // and `para_perp_perp` each lose stored `para`/`perp` facts the
  // publisher does not reach (17 and 44 `para` on two fixtures, one
  // `perp` on `locus3`), so they stay.
  Rule.parse(
    'eqratio_transitive',
    'eqratio(a,b,c,d,e,f,g,h) & eqratio(e,f,g,h,p,q,r,s) '
        '=> eqratio(a,b,c,d,p,q,r,s)',
  ),
  // Circles: three points fix the circle, so a fourth and fifth share it.
  Rule.parse(
    'cyclic_fifth_point',
    'cyclic(a,b,c,d) & cyclic(a,b,c,e) => cyclic(b,c,d,e)',
  ),
  // The inscribed angle theorem and its converse — DD's workhorse pair.
  Rule.parse('inscribed_angle', 'cyclic(a,b,p,q) => eqangle(p,a,p,b,q,a,q,b)'),
  Rule.parse(
    'inscribed_converse',
    'eqangle(p,a,p,b,q,a,q,b) => cyclic(a,b,p,q)',
  ),
  // Midpoints.
  Rule.parse('midp_coll', 'midp(m,a,b) => coll(m,a,b)'),
  Rule.parse('midp_cong', 'midp(m,a,b) => cong(m,a,m,b)'),
  Rule.parse('coll_cong_midp', 'coll(m,a,b) & cong(m,a,m,b) => midp(m,a,b)'),
  Rule.parse('midline_para', 'midp(m,a,b) & midp(n,a,c) => para(m,n,b,c)'),
  // Two points equidistant from a segment's ends span its bisector.
  Rule.parse('perp_bisector', 'cong(o,a,o,b) & cong(p,a,p,b) => perp(o,p,a,b)'),
  // Isosceles base angles, both ways.
  Rule.parse('isosceles_base', 'cong(o,a,o,b) => eqangle(o,a,a,b,a,b,o,b)'),
  Rule.parse('isosceles_converse', 'eqangle(o,a,a,b,a,b,o,b) => cong(o,a,o,b)'),
  // The intercept (Thales) theorem on two transversals.
  Rule.parse(
    'intercept_eqratio',
    'coll(o,a,c) & coll(o,b,d) & para(a,b,c,d) => eqratio(o,a,o,c,o,b,o,d)',
  ),
  // Similarity: the three classical criteria in, its invariants out.
  // simtri is orientation-free (M-P1), so the eqangle *conclusion* of a
  // similarity is deliberately absent: a reflected pair satisfies the
  // ratio invariant but negates every mod-π angle, and deriving eqangle
  // from simtri would be unsound until the direct/reflected split
  // exists. eqratio survives reflection and is safe.
  Rule.parse(
    'sas_simtri',
    'eqratio(a,b,a,c,d,e,d,f) & eqangle(a,b,a,c,d,e,d,f) '
        '=> simtri(a,b,c,d,e,f)',
  ),
  Rule.parse(
    'aa_simtri',
    'eqangle(a,b,a,c,d,e,d,f) & eqangle(b,a,b,c,e,d,e,f) '
        '=> simtri(a,b,c,d,e,f)',
  ),
  Rule.parse(
    'sss_simtri',
    'eqratio(a,b,a,c,d,e,d,f) & eqratio(a,b,b,c,d,e,e,f) '
        '=> simtri(a,b,c,d,e,f)',
  ),
  Rule.parse(
    'simtri_eqratio',
    'simtri(a,b,c,d,e,f) => eqratio(a,b,a,c,d,e,d,f)',
  ),
  Rule.parse('contri_cong', 'contri(a,b,c,d,e,f) => cong(a,b,d,e)'),
  Rule.parse(
    'simtri_cong_contri',
    'simtri(a,b,c,d,e,f) & cong(a,b,d,e) => contri(a,b,c,d,e,f)',
  ),
  // Tangent lengths from one external point are equal (Phase 155). Read
  // it as Pythagoras rather than as a circle theorem, which is why the
  // premises name no circle: two right angles at `s` and `t` on lines
  // through `p`, and equal `o`-distances, give
  // `|ps|² = |op|² − |os|² = |op|² − |ot|² = |pt|²`. The tangency itself
  // arrives as `perp(o,t,t,p)` from `hypotheses` — a `TangentLine` whose
  // touch point the figure has named, or a polar meeting its circle.
  //
  // Measured on the corpus before keeping, per Phase 151b: **0 new facts
  // on all five older fixtures**, and on `tangent-chase.rgl` exactly
  // three — the theorem `cong(p,s,p,t)`, the chord of contact
  // `perp(s,t,o,p)` that `perp_bisector` then reaches from it, and one
  // `isosceles_base` angle. A rule with a consumer, which is the bar
  // `para_coll` failed.
  Rule.parse(
    'tangent_lengths',
    'perp(o,s,s,p) & perp(o,t,t,p) & cong(o,s,o,t) => cong(p,s,p,t)',
  ),
  // The tangent–chord (alternate segment) theorem (Phase 163): the angle
  // between a tangent and a chord through its point of contact equals
  // the inscribed angle on the chord from any other point of the
  // circle. `perp(o,t,t,p)` is the tangency as `hypotheses` emits it —
  // a `TangentLine` whose touch point `t` the figure has named, with a
  // named centre `o` and another named point `p` on the line — and the
  // two `cong`s put `a` and `b` on the circle. The conclusion's mod-π
  // spelling is the one the filter accepts; the swapped reading
  // `eqangle(t,p,t,a,b,a,b,t)` is false and the per-rule rig pins that.
  //
  // Phase 155 wrote this rule, measured it and dropped it: on
  // `tangent-chase.rgl` it doubled the run for thirteen `eqangle`s no
  // consumer acted on. Two things changed. The consumer arrived —
  // Phase 159's four-carrier ask is an `eqangle` question, and
  // `test/fixtures/tangent-chord.rgl` is a user's figure whose theorem
  // *is* this one and reachable no other way (the inscribed-angle road
  // needs a fourth point on the circle that the figure does not have).
  // And the cost was never this rule's: re-measured with the premises in
  // either order the timings are identical to the millisecond, because
  // the expense was `eqangle_transitive` pivoting on the new facts
  // through its 128 × 128 forms — see the note above. With that rule
  // gone this one costs `apatitos-topos` 49 → 71 ms (+3 eqangle),
  // `tangent-chase` 186 → 388 ms (+12 eqangle, still quiescent at 1 594
  // applications where the old pair ran past the 30 000 cap), and the
  // user's document 3 → 5 ms, proved.
  Rule.parse(
    'tangent_chord',
    'perp(o,t,t,p) & cong(o,t,o,a) & cong(o,t,o,b) '
        '=> eqangle(t,p,t,a,b,t,b,a)',
  ),
  // **Power of the point is not what tangency was missing**, and the
  // reason is worth keeping because it is structural rather than a gap
  // in the table. `|pa|·|pb| = |ps|²` needs the similarity of `psa` and
  // `pbs`, which is *true* — `simtri(p,s,a,p,b,s)` holds in the figure.
  // But the two triangles are oppositely oriented, so the shared angle
  // at `p` that `aa_simtri`'s second premise wants is **false as a mod-π
  // eqangle** (checked, not assumed). That is the direct/reflected split
  // M-P1 defers, not a rule anyone can add here.
]);
