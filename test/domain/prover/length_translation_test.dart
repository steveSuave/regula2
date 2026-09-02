/// The boundary between the fact vocabulary and the length algebra:
/// which predicates speak, which may be *concluded* (a narrower set,
/// deliberately), what the publisher enumerates, and what it leaves for
/// an ask.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/construction/geo_object.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/math/rational.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/prover/fact.dart';
import 'package:regula/domain/prover/length_closure.dart';
import 'package:regula/domain/prover/length_translation.dart';
import 'package:regula/domain/prover/predicate.dart';

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
  Fact cong(List<GeoPoint> p) => fact(PredicateKind.cong, p);
  Fact eqratio(List<GeoPoint> p) => fact(PredicateKind.eqratio, p);
  Fact midp(List<GeoPoint> p) => fact(PredicateKind.midp, p);

  group('a variable is an unordered point pair', () {
    test('either way round names one segment', () {
      expect(
        LengthTranslation.segmentVariable(a, b),
        LengthTranslation.segmentVariable(b, a),
      );
      expect(
        LengthTranslation.segmentVariable(a, b) ==
            LengthTranslation.segmentVariable(a, c),
        isFalse,
      );
    });

    test('a repeated point names no segment', () {
      // `log|aa|` is `log 0`, which is not a number — the contract is
      // programmer-error, and `_equationsOf` screens rather than
      // catching.
      expect(
        () => LengthTranslation.segmentVariable(a, a),
        throwsArgumentError,
      );
    });
  });

  group('what it reads and what it leaves alone', () {
    test('cong, eqratio and midp speak; the angle and incidence kinds '
        'do not', () {
      final translation = LengthTranslation();
      expect(translation.absorb(cong([a, b, c, d])), isTrue);
      expect(translation.absorb(eqratio([a, b, c, d, e, f, g, h])), isTrue);
      expect(translation.absorb(midp([a, b, c])), isTrue);

      // The angle system's, and the ones about incidence.
      for (final silent in {
        PredicateKind.para: [a, b, c, d],
        PredicateKind.perp: [a, b, c, d],
        PredicateKind.coll: [a, b, c],
        PredicateKind.cyclic: [a, b, c, d],
        PredicateKind.eqangle: [a, b, c, d, e, f, g, h],
        PredicateKind.simtri: [a, b, c, d, e, f],
        PredicateKind.contri: [a, b, c, d, e, f],
      }.entries) {
        expect(
          translation.absorb(fact(silent.key, silent.value)),
          isFalse,
          reason: '${silent.key.name} said something about lengths',
        );
      }
    });

    test('a fact naming a zero-length segment states nothing', () {
      final translation = LengthTranslation();
      expect(translation.absorb(cong([a, a, c, d])), isFalse);
      expect(translation.absorb(cong([a, b, c, c])), isFalse);
      expect(translation.absorb(eqratio([a, b, c, d, e, e, g, h])), isFalse);
      expect(translation.absorb(midp([a, a, c])), isFalse);
      expect(translation.closure.inputs, isEmpty);
      expect(translation.variables, isEmpty);
    });

    test('a cong of a segment with itself is absorbed as nothing', () {
      final translation = LengthTranslation();
      // `|ab| = |ba|` is true and empty: the row is trivial, so there is
      // no input and no source to cite.
      expect(translation.absorb(cong([a, b, b, a])), isFalse);
      expect(translation.closure.rank, 0);
      expect(translation.sources, isEmpty);
    });

    test('the vocabulary reaches the rows the closure expects', () {
      final translation = LengthTranslation()
        ..absorb(cong([a, b, c, d]))
        ..absorb(eqratio([a, b, c, d, e, f, g, h]))
        ..absorb(midp([a, b, c]));
      expect(translation.closure.inputs.length, 3);
      expect(
        translation.closure.inputs[0],
        LengthEquation.difference(
          LengthTranslation.segmentVariable(a, b),
          LengthTranslation.segmentVariable(c, d),
        ),
      );
      expect(
        translation.closure.inputs[2],
        LengthEquation.difference(
          LengthTranslation.segmentVariable(a, b),
          LengthTranslation.segmentVariable(a, c),
        ),
        reason: 'midp contributes its equal halves',
      );
    });
  });

  group('the constant kinds speak, at their stated value', () {
    Rational q(int n, [int d = 1]) => Rational.fromInts(n, d);
    Fact rconst(List<GeoPoint> p, Rational value) =>
        Fact(PredicateKind.rconst, p, value: value);
    Fact lconst(List<GeoPoint> p, Rational value) =>
        Fact(PredicateKind.lconst, p, value: value);

    test('rconst and lconst absorb as the rows their values make', () {
      final translation = LengthTranslation();
      expect(translation.absorb(rconst([a, b, c, d], q(2))), isTrue);
      expect(translation.absorb(lconst([e, f], q(3))), isTrue);
      expect(
        translation.closure.inputs[0],
        LengthEquation.rconst(
          LengthTranslation.segmentVariable(a, b),
          LengthTranslation.segmentVariable(c, d),
          q(2),
        ),
      );
      expect(
        translation.closure.inputs[1],
        LengthEquation.lconst(LengthTranslation.segmentVariable(e, f), q(3)),
      );
    });

    test('two stated lengths entail their cong exactly at equality', () {
      final translation = LengthTranslation()
        ..absorb(lconst([a, b], q(2)))
        ..absorb(lconst([c, d], q(2)));
      expect(translation.entailmentOf(cong([a, b, c, d])), isNotNull);
      final unequal = LengthTranslation()
        ..absorb(lconst([a, b], q(2)))
        ..absorb(lconst([c, d], q(3)));
      expect(unequal.entailmentOf(cong([a, b, c, d])), isNull);
    });

    test('rconst and lconst are conclusions, with certificates', () {
      final translation = LengthTranslation()
        ..absorb(lconst([a, b], q(2)))
        ..absorb(lconst([c, d], q(3)));
      final goal = rconst([a, b, c, d], q(2, 3));
      final certificate = translation.entailmentOf(goal)!;
      expect(
        translation.closure.recombine(certificate),
        translation.equationOf(goal),
      );
      // A cong carries a stated length across, and only the true value.
      final carried = LengthTranslation()
        ..absorb(lconst([a, b], q(2)))
        ..absorb(cong([a, b, c, d]));
      expect(carried.entailmentOf(lconst([c, d], q(2))), isNotNull);
      expect(carried.entailmentOf(lconst([c, d], q(5))), isNull);
    });

    test('a degenerate constant fact states nothing', () {
      final translation = LengthTranslation();
      expect(translation.absorb(rconst([a, a, c, d], q(2))), isFalse);
      expect(translation.absorb(lconst([a, a], q(2))), isFalse);
      expect(translation.closure.inputs, isEmpty);
    });

    test('disagreeing stated lengths make the closure inconsistent', () {
      final translation = LengthTranslation()
        ..absorb(lconst([a, b], q(2)))
        ..absorb(lconst([a, b], q(3)));
      expect(translation.closure.isInconsistent, isTrue);
      // Both are still inputs with sources — certificates index by
      // position, and the contradiction is part of the record.
      expect(translation.closure.inputs.length, 2);
      expect(translation.sources.length, 2);
    });
  });

  group('what may be concluded is narrower than what may be absorbed', () {
    test('cong and eqratio are conclusions; midp is not', () {
      final translation = LengthTranslation();
      expect(translation.equationOf(cong([a, b, c, d])), isNotNull);
      expect(
        translation.equationOf(eqratio([a, b, c, d, e, f, g, h])),
        isNotNull,
      );
      // The asymmetry, and it is soundness rather than tidiness:
      // `midp(m,a,b)` implies |ma| = |mb|, and equal distances do not
      // put `m` on the segment. Exactly the angle side's `coll`.
      expect(translation.equationOf(midp([a, b, c])), isNull);
      expect(
        translation.equationOf(fact(PredicateKind.para, [a, b, c, d])),
        isNull,
      );
    });

    test('asking what a fact would say registers nothing', () {
      final translation = LengthTranslation();
      expect(translation.equationOf(cong([a, b, c, d])), isNotNull);
      expect(translation.variables, isEmpty);
      expect(translation.closure.inputs, isEmpty);
    });

    test('a trivial conclusion is not an entailment', () {
      // `|ab| = |ba|` is a tautology, and answering "proved, from
      // nothing" would put a step in a proof that says nothing.
      final translation = LengthTranslation()..absorb(cong([a, b, c, d]));
      expect(translation.entailmentOf(cong([a, b, b, a])), isNull);
    });
  });

  group('the publisher enumerates cong, and only cong', () {
    test('a chain of congs publishes the pair it closes', () {
      final translation = LengthTranslation()
        ..absorb(cong([a, b, c, d]))
        ..absorb(cong([c, d, e, f]));
      final published = translation.conclusions().toList();
      final statements = published.map((c) => c.fact).toList();
      expect(statements, contains(Fact(PredicateKind.cong, [a, b, e, f])));
      expect(
        statements.every((fact) => fact.kind == PredicateKind.cong),
        isTrue,
        reason: 'eqratio is answered on ask, never enumerated',
      );
      for (final conclusion in published) {
        expect(
          translation.closure.recombine(conclusion.certificate),
          conclusion.equation,
        );
      }
    });

    test('two segments sharing a point are not refused', () {
      // The angle side skips them — `para` between two lines through one
      // point is a degeneracy. `|AB| = |AC|` is an isoceles triangle,
      // which is news.
      final translation = LengthTranslation()
        ..absorb(cong([a, b, c, d]))
        ..absorb(cong([c, d, a, e]));
      expect(
        translation.conclusions().map((c) => c.fact),
        contains(Fact(PredicateKind.cong, [a, b, a, e])),
      );
    });

    test(
      'an eqratio the closure entails is answered on ask, not published',
      () {
        final translation = LengthTranslation()
          ..absorb(eqratio([a, b, c, d, e, f, g, h]))
          ..absorb(cong([a, b, e, f]));
        // Entailed: with |ab| = |ef| the ratio equation gives |cd| = |gh|,
        // and |ab|/|ef| = |cd|/|gh| is the eqratio spelling of it.
        final asked = eqratio([a, b, e, f, c, d, g, h]);
        expect(translation.entailmentOf(asked), isNotNull);
        expect(
          translation.conclusions().map((c) => c.fact),
          isNot(contains(asked)),
        );
        // The cong it *does* publish, for the same reason.
        expect(
          translation.conclusions().map((c) => c.fact),
          contains(Fact(PredicateKind.cong, [c, d, g, h])),
        );
      },
    );

    test('nothing is published from a closure that heard nothing', () {
      expect(LengthTranslation().conclusions(), isEmpty);
    });
  });

  group('provenance survives the boundary', () {
    test('a certificate names the facts, deduplicated and in order', () {
      final translation = LengthTranslation()
        ..absorb(cong([a, b, c, d]))
        ..absorb(cong([e, f, g, h]))
        ..absorb(cong([c, d, e, f]));
      final conclusion = translation.conclusions().firstWhere(
        (c) => c.fact == Fact(PredicateKind.cong, [a, b, e, f]),
      );
      final cited = translation.sourcesOf(conclusion.certificate);
      expect(cited, [
        cong([a, b, c, d]),
        cong([c, d, e, f]),
      ]);
      expect(cited, isNot(contains(cong([e, f, g, h]))));
    });

    test('the ends of a variable read back as the points that named it', () {
      final translation = LengthTranslation()..absorb(cong([a, b, c, d]));
      final variable = LengthTranslation.segmentVariable(a, b);
      final ends = translation.endsOf(variable)!;
      expect({ends.$1.id, ends.$2.id}, {'a', 'b'});
      expect(
        translation.endsOf(LengthTranslation.segmentVariable(e, f)),
        isNull,
      );
    });
  });

  group('readRatio and readLength — the reader (Phase 185)', () {
    Fact stated(PredicateKind kind, List<GeoPoint> p, Rational value) =>
        Fact(kind, p, value: value);
    final translation = LengthTranslation()
      ..absorb(stated(PredicateKind.lconst, [a, b], Rational.fromInts(5, 2)))
      ..absorb(stated(PredicateKind.rconst, [c, d, a, b], Rational.whole(3)))
      ..absorb(cong([e, f, c, d]));

    test('reads lengths and ratios the rows entail, composed', () {
      expect(translation.readLength(a, b), Rational.fromInts(5, 2));
      expect(translation.readLength(b, a), Rational.fromInts(5, 2));
      expect(translation.readRatio(c, d, a, b), Rational.whole(3));
      expect(translation.readRatio(a, b, c, d), Rational.fromInts(1, 3));
      expect(translation.readLength(e, f), Rational.fromInts(15, 2));
      expect(translation.readRatio(e, f, a, b), Rational.whole(3));
    });

    test('what the rows do not determine, or cannot state, reads null', () {
      expect(translation.readLength(g, h), isNull);
      expect(translation.readRatio(a, b, g, h), isNull);
      expect(translation.readLength(a, a), isNull);
      // A ratio of a segment to itself is 1 by arithmetic alone.
      expect(translation.readRatio(a, b, b, a), Rational.one);
    });

    test('reading registers nothing, and the value read is provable', () {
      final before = translation.variables.length;
      expect(translation.readLength(g, h), isNull);
      expect(translation.variables.length, before);
      final value = translation.readLength(e, f)!;
      expect(
        translation.entailmentOf(stated(PredicateKind.lconst, [e, f], value)),
        isNotNull,
      );
    });
  });
}
