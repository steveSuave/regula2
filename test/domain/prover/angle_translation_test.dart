import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/construction/geo_object.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/prover/angle_translation.dart';
import 'package:regula/domain/prover/carriers.dart';
import 'package:regula/domain/prover/fact.dart';
import 'package:regula/domain/prover/predicate.dart';
import 'package:regula/domain/prover/rational.dart';

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

  Fact fact(PredicateKind kind, List<GeoPoint> points) => Fact(kind, points);
  Fact para(List<GeoPoint> p) => fact(PredicateKind.para, p);
  Fact perp(List<GeoPoint> p) => fact(PredicateKind.perp, p);
  Fact coll(List<GeoPoint> p) => fact(PredicateKind.coll, p);
  Fact eqangle(List<GeoPoint> p) => fact(PredicateKind.eqangle, p);

  CarrierIndex carriersOver(Iterable<Fact> facts) => CarrierIndex.over(facts);

  group('what it reads and what it leaves alone', () {
    test('para, perp, eqangle and coll speak; nothing else does', () {
      final translation = AngleTranslation();
      expect(translation.absorb(para([a, b, c, d])), isTrue);
      expect(translation.absorb(perp([a, b, e, f])), isTrue);
      expect(translation.absorb(eqangle([a, b, c, d, e, f, g, h])), isTrue);
      expect(translation.absorb(coll([a, b, c])), isTrue);

      // The length system's, and the ones about points.
      expect(
        translation.absorb(fact(PredicateKind.cong, [a, b, c, d])),
        isFalse,
      );
      expect(
        translation.absorb(
          fact(PredicateKind.eqratio, [a, b, c, d, e, f, g, h]),
        ),
        isFalse,
      );
      expect(translation.absorb(fact(PredicateKind.midp, [a, b, c])), isFalse);
      expect(
        translation.absorb(fact(PredicateKind.cyclic, [a, b, c, d])),
        isFalse,
      );
    });

    test('a pair written either way round is one variable', () {
      expect(
        AngleTranslation.lineVariable(a, b),
        AngleTranslation.lineVariable(b, a),
      );
      expect(
        AngleTranslation.lineVariable(a, b) ==
            AngleTranslation.lineVariable(a, c),
        isFalse,
      );
      expect(() => AngleTranslation.lineVariable(a, a), throwsArgumentError);
    });

    test('perp is a half and para is a zero', () {
      final translation = AngleTranslation()
        ..absorb(perp([a, b, c, d]))
        ..absorb(para([e, f, g, h]));
      expect(translation.closure.inputs[0].constant, Rational.fromInts(1, 2));
      expect(translation.closure.inputs[1].constant, Rational.zero);
    });

    test('coll contributes two equalities, not three', () {
      // The third pair's equality is the sum of the other two, so
      // stating it would only be called redundant.
      final translation = AngleTranslation()..absorb(coll([a, b, c]));
      expect(translation.closure.inputs.length, 2);
      expect(translation.closure.rank, 2);
      for (final equation in translation.closure.inputs) {
        expect(equation.constant, Rational.zero);
      }
    });
  });

  group('rules that fall out as arithmetic', () {
    test('perp_perp_para', () {
      final translation = AngleTranslation()
        ..absorb(perp([a, b, c, d]))
        ..absorb(perp([c, d, e, f]));
      final found = translation
          .conclusions(carriersOver(const []))
          .map((conclusion) => conclusion.fact)
          .toList();
      expect(found, contains(para([a, b, e, f])));
    });

    test('para_perp_perp', () {
      final translation = AngleTranslation()
        ..absorb(para([a, b, c, d]))
        ..absorb(perp([c, d, e, f]));
      final found = translation
          .conclusions(carriersOver(const []))
          .map((conclusion) => conclusion.fact)
          .toList();
      expect(found, contains(perp([a, b, e, f])));
    });

    test('para_transitive', () {
      final translation = AngleTranslation()
        ..absorb(para([a, b, c, d]))
        ..absorb(para([c, d, e, f]));
      final found = translation
          .conclusions(carriersOver(const []))
          .map((conclusion) => conclusion.fact)
          .toList();
      expect(found, contains(para([a, b, e, f])));
    });

    test('perp_coll — the rule Phase 151 could not delete', () {
      // `perp(a,b,c,d) & coll(a,b,e) & coll(a,b,f) => perp(e,f,c,d)`,
      // written into the table in Phase 150 because a line has many
      // names and a derived fact holds only one of them. Here the names
      // are variables and `coll` says they are equal, so re-spelling is
      // what elimination does — no rule, no premise enumeration, no
      // budget.
      final line = coll([a, b, c]);
      final translation = AngleTranslation()
        ..absorb(line)
        ..absorb(perp([a, b, e, f]));
      final found = translation
          .conclusions(carriersOver([line]))
          .map((conclusion) => conclusion.fact)
          .toList();
      // Every spelling of the line, at once.
      expect(found, contains(perp([a, c, e, f])));
      expect(found, contains(perp([b, c, e, f])));
    });

    test('but incidence does not reduce to the algebra', () {
      // The boundary, exactly. `coll(a,b,c)` and `coll(a,b,d)` leave the
      // closure holding theta_ab = theta_ac = theta_bc = theta_ad =
      // theta_bd, and saying nothing whatever about theta_cd — because
      // the pair `cd` names no variable: no fact mentions it. That c and
      // d are *each* on line ab, and so that line cd is line ab, is an
      // incidence statement, and directions cannot express it.
      //
      // `CarrierIndex` is what knows it, and applying the bridge eagerly
      // would mean a variable and a published fact for every pair on
      // every line — the spelling explosion of Phase 151b at a new
      // address. So it is applied at query time, in M-P3c.
      final lines = [
        coll([a, b, c]),
        coll([a, b, d]),
      ];
      final translation = AngleTranslation()
        ..absorbAll(lines)
        ..absorb(perp([a, b, e, f]));
      expect(
        translation.variables,
        isNot(contains(AngleTranslation.lineVariable(c, d))),
      );
      final found = translation
          .conclusions(carriersOver(lines))
          .map((conclusion) => conclusion.fact)
          .toList();
      expect(found, isNot(contains(perp([c, d, e, f]))));

      // And the incidence closure does know it — which is what makes
      // this a boundary rather than a hole.
      expect(carriersOver(lines).lineThrough(c, d).contains(a), isTrue);
    });
  });

  group('what it refuses to publish', () {
    test('a line is not parallel to itself', () {
      // Two pairs on one carrier satisfy the parallel relation
      // trivially. Publishing it would be true and useless, and would
      // flood the fact set with one entry per spelling — which is the
      // problem AR is here to remove.
      final line = coll([a, b, c]);
      final translation = AngleTranslation()..absorb(line);
      final found = translation
          .conclusions(carriersOver([line]))
          .map((conclusion) => conclusion.fact)
          .toList();
      expect(found, isEmpty);
    });

    test('and pairs sharing a point are left alone', () {
      final translation = AngleTranslation()
        ..absorb(para([a, b, c, d]))
        ..absorb(para([a, e, c, d]));
      // ab and ae are now parallel and share a, so they are the same
      // line; either way it is not news.
      final found = translation
          .conclusions(carriersOver(const []))
          .map((conclusion) => conclusion.fact)
          .toList();
      expect(found.any((f) => f == para([a, b, a, e])), isFalse);
    });

    test('the 2θ ambiguity publishes nothing', () {
      // The same counterexample as `angle_closure_test`, now through the
      // vocabulary: two eqangles that pin twice the angle and neither
      // reading of it.
      final translation = AngleTranslation()
        ..absorb(eqangle([a, b, c, d, e, f, g, h]))
        ..absorb(eqangle([a, b, c, d, g, h, e, f]));
      final found = translation
          .conclusions(carriersOver(const []))
          .map((conclusion) => conclusion.fact)
          .toList();
      expect(found.any((f) => f == para([a, b, c, d])), isFalse);
      expect(found.any((f) => f == perp([a, b, c, d])), isFalse);
    });
  });

  group('a conclusion carries why', () {
    test('the certificate recombines to the relation it proves', () {
      final translation = AngleTranslation()
        ..absorb(perp([a, b, c, d]))
        ..absorb(perp([c, d, e, f]));
      final conclusions = translation
          .conclusions(carriersOver(const []))
          .toList();
      expect(conclusions, isNotEmpty);
      for (final conclusion in conclusions) {
        expect(
          translation.closure.recombine(conclusion.certificate),
          conclusion.equation,
        );
      }
    });

    test('and names the facts a proof would cite', () {
      final first = perp([a, b, c, d]);
      final second = perp([c, d, e, f]);
      final noise = para([g, h, a, e]);
      final translation = AngleTranslation()
        ..absorb(first)
        ..absorb(noise)
        ..absorb(second);
      final conclusion = translation
          .conclusions(carriersOver(const []))
          .firstWhere((found) => found.fact == para([a, b, e, f]));
      expect(translation.sourcesOf(conclusion.certificate), [first, second]);
    });

    test('a coll cited once, however many equalities it contributed', () {
      final line = coll([a, b, c]);
      final translation = AngleTranslation()
        ..absorb(line)
        ..absorb(perp([a, b, e, f]));
      final conclusion = translation
          .conclusions(carriersOver([line]))
          .firstWhere((found) => found.fact == perp([b, c, e, f]));
      final sources = translation.sourcesOf(conclusion.certificate);
      expect(sources.where((source) => source == line).length, 1);
      expect(sources, contains(perp([a, b, e, f])));
    });
  });

  group('a published fact is a fact', () {
    test('conclusions are well-formed predicates over the right points', () {
      final translation = AngleTranslation()
        ..absorb(perp([a, b, c, d]))
        ..absorb(perp([c, d, e, f]));
      for (final conclusion in translation.conclusions(
        carriersOver(const []),
      )) {
        expect(conclusion.fact.points.length, 4);
        expect(
          {for (final point in conclusion.fact.points) point.id}.length,
          4,
          reason: 'a published relation names four distinct points',
        );
        expect(
          conclusion.fact.kind == PredicateKind.para ||
              conclusion.fact.kind == PredicateKind.perp,
          isTrue,
        );
      }
    });

    test('nothing is published from an empty closure', () {
      final translation = AngleTranslation();
      expect(translation.conclusions(carriersOver(const [])), isEmpty);
      expect(translation.variables, isEmpty);
    });

    test('one relation alone concludes only itself', () {
      final translation = AngleTranslation()..absorb(perp([a, b, c, d]));
      final found = translation
          .conclusions(carriersOver(const []))
          .map((conclusion) => conclusion.fact)
          .toList();
      expect(found, [
        perp([a, b, c, d]),
      ]);
    });
  });
}
