import 'dart:math' as math;

import 'package:glados/glados.dart';
import 'package:regula/domain/math/expression.dart';

/// Env exposing a fixed variable table and one object function `two()` that
/// returns 2.0 regardless of its (name) arguments — enough to exercise every
/// evaluator path without construction types.
class _TableEnv implements ExpressionEnv {
  const _TableEnv([this.variables = const {}]);

  final Map<String, double> variables;

  @override
  double? variable(String name) => variables[name];

  @override
  bool isObjectFunction(String name) => name == 'two';

  @override
  double? objectFunction(String name, List<String> argNames) =>
      name == 'two' ? 2.0 : null;
}

double? eval(String source, [ExpressionEnv env = const EmptyExpressionEnv()]) =>
    evaluateExpression(parseExpression(source), env);

void main() {
  group('parser + evaluator basics', () {
    test('number literals', () {
      expect(eval('42'), 42);
      expect(eval('3.5'), 3.5);
      expect(eval('.5'), 0.5);
      expect(eval(' 7 '), 7);
    });

    test('arithmetic precedence', () {
      expect(eval('2+3*4'), 14);
      expect(eval('(2+3)*4'), 20);
      expect(eval('10-4-3'), 3); // left assoc
      expect(eval('12/4/3'), 1); // left assoc
      expect(eval('1+6/2'), 4);
    });

    test('power is right-associative and above unary minus', () {
      expect(eval('2^3^2'), 512); // 2^(3^2)
      expect(eval('-2^2'), -4); // -(2^2), the math convention
      expect(eval('(-2)^2'), 4);
      expect(eval('2^-3'), 0.125); // exponent re-enters at unary
      expect(eval('-2^-2'), -0.25);
    });

    test('unary minus', () {
      expect(eval('-5'), -5);
      expect(eval('--5'), 5);
      expect(eval('3*-2'), -6);
    });

    test('typed math symbols normalize', () {
      expect(eval('3×4'), 12);
      expect(eval('3·4'), 12);
      expect(eval('8÷2'), 4);
      expect(eval('5−2'), 3); // U+2212
      // Implicit multiplication stays a parse error.
      expect(
        () => parseExpression('2π'),
        throwsA(isA<ExpressionFormatException>()),
      );
      expect(eval('2*π'), closeTo(2 * math.pi, 1e-12));
    });
  });

  group('constants and variables', () {
    test('pi and e resolve before the env', () {
      // The env deliberately shadows both — the constants must win.
      const env = _TableEnv({'pi': 1.0, 'e': 1.0, 'a': 3.0});
      expect(eval('pi', env), math.pi);
      expect(eval('e', env), math.e);
      expect(eval('a', env), 3);
    });

    test('unknown variable is null, not an exception', () {
      expect(eval('nope'), isNull);
      expect(eval('1 + nope'), isNull);
    });
  });

  group('numeric functions', () {
    test('single-argument functions', () {
      expect(eval('sqrt(9)'), 3);
      expect(eval('abs(-3.5)'), 3.5);
      expect(eval('round(2.5)'), 3);
      expect(eval('floor(2.9)'), 2);
      expect(eval('ceil(2.1)'), 3);
    });

    test('trig works in degrees', () {
      expect(eval('sin(30)'), closeTo(0.5, 1e-12));
      expect(eval('cos(60)'), closeTo(0.5, 1e-12));
      expect(eval('tan(45)'), closeTo(1, 1e-12));
      expect(eval('asin(0.5)'), closeTo(30, 1e-12));
      expect(eval('acos(0.5)'), closeTo(60, 1e-12));
      expect(eval('atan(1)'), closeTo(45, 1e-12));
    });

    test('min and max are variadic with at least two arguments', () {
      expect(eval('min(3, 1, 2)'), 1);
      expect(eval('max(3, 1, 2)'), 3);
      expect(eval('min(5)'), isNull);
    });

    test('arity mismatch and unknown function yield null', () {
      expect(eval('sqrt(1, 2)'), isNull);
      expect(eval('sqrt()'), isNull);
      expect(eval('mystery(3)'), isNull);
    });

    test('registry metadata is exposed for validation', () {
      expect(numericFunctionNames, contains('sqrt'));
      expect(numericFunctionArity('sqrt'), (1, 1));
      expect(numericFunctionArity('min'), (2, null));
      expect(numericFunctionArity('mystery'), isNull);
    });
  });

  group('null propagation — evaluation never throws', () {
    test('non-finite results become null', () {
      expect(eval('1/0'), isNull);
      expect(eval('-1/0'), isNull);
      expect(eval('0/0'), isNull);
      expect(eval('sqrt(-1)'), isNull);
      expect(eval('asin(2)'), isNull);
      expect(eval('10^10000'), isNull);
    });

    test('null in any operand propagates', () {
      expect(eval('sqrt(nope)'), isNull);
      expect(eval('min(1, nope)'), isNull);
      expect(eval('-(nope)'), isNull);
    });
  });

  group('object functions', () {
    test('arguments are names, passed unevaluated', () {
      const env = _TableEnv();
      expect(eval('two(A, B)', env), 2);
      expect(eval('two(A) + two(B, C)', env), 4);
    });

    test('non-name arguments make the call undefined', () {
      const env = _TableEnv();
      expect(eval('two(1 + 2)', env), isNull);
      expect(eval('two(3)', env), isNull);
    });

    test('object-name arguments are not shadowed by constants', () {
      // `two` ignores its arg names, but the parse shape matters: `two(e)`
      // must reach objectFunction with the *name* e, not Euler's number.
      var seen = <String>[];
      final env = _RecordingEnv((name, args) {
        seen = args;
        return 2.0;
      });
      expect(eval('two(e)', env), 2);
      expect(seen, ['e']);
    });
  });

  group('parse errors', () {
    void expectParseError(String source) {
      expect(
        () => parseExpression(source),
        throwsA(isA<ExpressionFormatException>()),
        reason: source,
      );
    }

    test('malformed inputs throw ExpressionFormatException', () {
      expectParseError('');
      expectParseError('   ');
      expectParseError('1 +');
      expectParseError('* 2');
      expectParseError('(1 + 2');
      expectParseError('1 + 2)');
      expectParseError('f(1,)');
      expectParseError('f(,1)');
      expectParseError('1 2');
      expectParseError('a b');
      expectParseError('3.');
      expectParseError('1 @ 2');
      expectParseError('{1}');
    });

    test('exception carries source and offset', () {
      try {
        parseExpression('1 + @');
        fail('expected ExpressionFormatException');
      } on ExpressionFormatException catch (e) {
        expect(e.source, '1 + @');
        expect(e.offset, 4);
      }
    });

    Glados<String>(any.stringOf(r'01a+-*/^(), .{}@πe$')).test(
      'random strings only ever throw ExpressionFormatException',
      (source) {
        try {
          final expr = parseExpression(source);
          evaluateExpression(expr, const _TableEnv({'a': 1.0}));
        } on ExpressionFormatException {
          // The only permitted exception.
        }
      },
    );
  });

  group('referenceNamesIn', () {
    List<String> refs(String source) => referenceNamesIn(
      parseExpression(source),
      (name) => name == 'dist' || name == 'len',
    );

    test('collects bare names and accessor arguments, in order, deduped', () {
      expect(refs('dist(A, B) + a * len(c) + a'), ['A', 'B', 'a', 'c']);
    });

    test('excludes constants and numeric-function heads', () {
      expect(refs('pi * e + sqrt(x)'), ['x']);
      expect(refs('min(a, b)'), ['a', 'b']);
    });

    test('accessor args count even when shadowing constants', () {
      expect(refs('len(e) + e'), ['e']);
    });
  });

  group('random AST round-trip (glados)', () {
    Glados(any.int, ExploreConfig(numRuns: 60)).test(
      'generated arithmetic ASTs evaluate to the directly computed value',
      (seed) {
        final random = math.Random(seed);
        final (expr, expected) = _randomArithmetic(random, 0);
        final actual = evaluateExpression(expr, const EmptyExpressionEnv());
        if (expected == null || !expected.isFinite) {
          expect(actual, isNull);
        } else {
          expect(actual, isNotNull);
          expect(actual, closeTo(expected, expected.abs() * 1e-9 + 1e-9));
        }
      },
    );
  });
}

class _RecordingEnv implements ExpressionEnv {
  _RecordingEnv(this.onCall);

  final double? Function(String name, List<String> argNames) onCall;

  @override
  double? variable(String name) => null;

  @override
  bool isObjectFunction(String name) => name == 'two';

  @override
  double? objectFunction(String name, List<String> argNames) =>
      onCall(name, argNames);
}

/// Builds a random +/-/*/unary-minus AST and its directly computed value
/// (no `^` or `/` — their non-finite escapes are pinned separately above).
(Expr, double?) _randomArithmetic(math.Random random, int depth) {
  if (depth >= 4 || random.nextInt(3) == 0) {
    final value = (random.nextDouble() - 0.5) * 200;
    return (NumberLiteral(value), value);
  }
  switch (random.nextInt(4)) {
    case 0:
      final (operand, value) = _randomArithmetic(random, depth + 1);
      return (UnaryMinus(operand), value == null ? null : -value);
    case 1:
      final (l, lv) = _randomArithmetic(random, depth + 1);
      final (r, rv) = _randomArithmetic(random, depth + 1);
      return (
        BinaryOp(BinOp.add, l, r),
        lv == null || rv == null ? null : lv + rv,
      );
    case 2:
      final (l, lv) = _randomArithmetic(random, depth + 1);
      final (r, rv) = _randomArithmetic(random, depth + 1);
      return (
        BinaryOp(BinOp.subtract, l, r),
        lv == null || rv == null ? null : lv - rv,
      );
    default:
      final (l, lv) = _randomArithmetic(random, depth + 1);
      final (r, rv) = _randomArithmetic(random, depth + 1);
      return (
        BinaryOp(BinOp.multiply, l, r),
        lv == null || rv == null ? null : lv * rv,
      );
  }
}
