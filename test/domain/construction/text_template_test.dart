import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/construction/text_template.dart';
import 'package:regula/domain/math/expression.dart';

class _TableEnv implements ExpressionEnv {
  const _TableEnv([this.variables = const {}]);

  final Map<String, double> variables;

  @override
  double? variable(String name) => variables[name];

  @override
  bool isObjectFunction(String name) => objectFunctionNames.contains(name);

  @override
  double? objectFunction(String name, List<String> argNames) =>
      name == 'dist' ? 5.0 : null;
}

void main() {
  group('TextTemplate.parse', () {
    test('pure literal has no expressions and no references', () {
      final template = TextTemplate.parse('Triangle ABC');
      expect(template.hasExpressions, isFalse);
      expect(template.referenceNames, isEmpty);
      expect(template.render(const _TableEnv()), 'Triangle ABC');
    });

    test('splits literal and expression segments', () {
      final template = TextTemplate.parse('a = {1 + 2} end');
      expect(template.segments, hasLength(3));
      expect(template.hasExpressions, isTrue);
    });

    test('adjacent slots and empty literals', () {
      final template = TextTemplate.parse('{1}{2}');
      expect(template.render(const _TableEnv()), '1.002.00');
    });

    test('reference names: unique, first-occurrence order, across slots',
        () {
      final template =
          TextTemplate.parse('{dist(A, B) + a} then {len(c) + a + B}');
      expect(template.referenceNames, ['A', 'B', 'a', 'c']);
    });

    test('constants and function heads are not references', () {
      final template = TextTemplate.parse('{pi * e + sqrt(x)}');
      expect(template.referenceNames, ['x']);
    });

    test('accessor args shadowed by constants still count', () {
      expect(TextTemplate.parse('{len(e) + e}').referenceNames, ['e']);
    });

    void expectParseError(String content, Pattern message) {
      expect(
        () => TextTemplate.parse(content),
        throwsA(isA<FormatException>()
            .having((e) => e.message, 'message', contains(message))),
        reason: content,
      );
    }

    test('brace errors', () {
      expectParseError('open {1 + 2', "without a matching '}'");
      expectParseError('close } here', "without a matching '{'");
      expectParseError('empty {} slot', 'Empty expression');
      expectParseError('blank {  } slot', 'Empty expression');
    });

    test('malformed slot expressions propagate as FormatException', () {
      expect(() => TextTemplate.parse('{1 +}'),
          throwsA(isA<ExpressionFormatException>()));
    });

    test('unknown functions and arities are rejected at parse time', () {
      expectParseError('{foo(1)}', "Unknown function 'foo'");
      expectParseError('{dist(A)}', "'dist' takes 2 arguments");
      expectParseError('{angle(A, B)}', "'angle' takes 3 arguments");
      expectParseError('{x(A, B)}', "'x' takes 1 argument");
      expectParseError('{sqrt(1, 2)}', "'sqrt' takes 1 argument");
      expectParseError('{min(1)}', "'min' takes at least 2");
      expectParseError('{dist(A, 1 + 2)}', 'must be object names');
    });
  });

  group('render', () {
    test('substitutes values at 2 decimals', () {
      final template = TextTemplate.parse('d = {dist(A, B)} cm');
      expect(template.render(const _TableEnv()), 'd = 5.00 cm');
    });

    test('undefined slots render as ?', () {
      final template = TextTemplate.parse('{unknown} and {1/0} but {2*2}');
      expect(template.render(const _TableEnv()), '? and ? but 4.00');
    });

    test('variables resolve through the env', () {
      final template = TextTemplate.parse('{a + a}');
      expect(template.render(const _TableEnv({'a': 1.5})), '3.00');
    });
  });

  group('formatComputedValue', () {
    test('fixed two decimals', () {
      expect(formatComputedValue(3.14159), '3.14');
      expect(formatComputedValue(2), '2.00');
      expect(formatComputedValue(-1.005), '-1.00');
    });

    test('negative zero normalizes', () {
      expect(formatComputedValue(-0.0000001), '0.00');
    });

    test('explicit decimals override the default (Phase 72)', () {
      expect(formatComputedValue(3.14159, decimals: 0), '3');
      expect(formatComputedValue(3.14159, decimals: 4), '3.1416');
      expect(formatComputedValue(2, decimals: 5), '2.00000');
      expect(formatComputedValue(3.14159, decimals: null), '3.14');
    });

    test('negative zero normalizes at every decimal count', () {
      expect(formatComputedValue(-0.0000001, decimals: 0), '0');
      expect(formatComputedValue(-0.0000001, decimals: 4), '0.0000');
    });
  });

  group('render with decimals (Phase 72)', () {
    test('slots render at the requested count, literals untouched', () {
      final template = TextTemplate.parse('d = {2 + 2.5} cm');
      expect(template.render(const _TableEnv(), decimals: 4), 'd = 4.5000 cm');
      expect(template.render(const _TableEnv(), decimals: 0), 'd = 5 cm');
      expect(template.render(const _TableEnv()), 'd = 4.50 cm');
    });
  });
}
