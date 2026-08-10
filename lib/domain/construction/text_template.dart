import '../math/expression.dart';

/// The text tool's content template (Phase 58): literal runs interleaved
/// with `{…}` expression slots. Parsing validates everything a dialog can
/// meaningfully reject — brace matching, expression syntax, function names
/// and arities — so evaluation later never needs to throw. Knows the
/// expression language but no [GeoObject]s; the geometry side lives in
/// `text_evaluator.dart`.

/// Geometry accessor names: calls whose arguments are object *names*
/// (never numbers), resolved by the env against the construction.
const Set<String> objectFunctionNames = {
  'dist',
  'len',
  'angle',
  'area',
  'radius',
  'perimeter',
  'x',
  'y',
};

const Map<String, int> _objectFunctionArity = {
  'dist': 2,
  'len': 1,
  'angle': 3,
  'area': 1,
  'radius': 1,
  'perimeter': 1,
  'x': 1,
  'y': 1,
};

/// How a `{…}` slot's value renders: [decimals] digits, null = 2 — the
/// same default as the presentation layer's `formatLength`, but
/// domain-side: the rendered string is built inside `recompute()`, where
/// presentation code is unreachable. The count is fixed per text
/// (`valueDecimals`, Phase 72), which keeps the width from jittering
/// during drags.
String formatComputedValue(double value, {int? decimals}) {
  final text = value.toStringAsFixed(decimals ?? 2);
  // toStringAsFixed of a tiny negative rounds to '-0.00' ('-0' at zero
  // decimals): a parsed-zero result drops the sign.
  return text.startsWith('-') && double.parse(text) == 0
      ? text.substring(1)
      : text;
}

sealed class TextSegment {
  const TextSegment();
}

class LiteralSegment extends TextSegment {
  const LiteralSegment(this.text);

  final String text;
}

class ExpressionSegment extends TextSegment {
  const ExpressionSegment(this.expr, this.source);

  final Expr expr;

  /// The slot's raw source between the braces, for error messages.
  final String source;
}

class TextTemplate {
  TextTemplate._(this.content, this.segments, this.referenceNames);

  /// Splits [content] on `{…}` slots and parses each slot's expression.
  ///
  /// Throws [FormatException] on an unmatched brace, an empty slot, a
  /// malformed expression, an unknown function, a wrong arity, or a
  /// geometry accessor whose argument isn't a bare object name.
  factory TextTemplate.parse(String content) {
    final segments = <TextSegment>[];
    final names = <String>{};
    var literalStart = 0;
    var i = 0;
    while (i < content.length) {
      final ch = content[i];
      if (ch == '}') {
        throw FormatException("'}' without a matching '{'", content, i);
      }
      if (ch != '{') {
        i++;
        continue;
      }
      final close = content.indexOf('}', i + 1);
      if (close < 0) {
        throw FormatException("'{' without a matching '}'", content, i);
      }
      if (literalStart < i) {
        segments.add(LiteralSegment(content.substring(literalStart, i)));
      }
      final source = content.substring(i + 1, close);
      if (source.trim().isEmpty) {
        throw FormatException('Empty expression slot', content, i);
      }
      final expr = parseExpression(source);
      _validateCalls(expr, content, i + 1);
      names.addAll(referenceNamesIn(expr, objectFunctionNames.contains));
      segments.add(ExpressionSegment(expr, source));
      i = close + 1;
      literalStart = i;
    }
    if (literalStart < content.length) {
      segments.add(LiteralSegment(content.substring(literalStart)));
    }
    return TextTemplate._(content, segments, List.unmodifiable(names));
  }

  final String content;
  final List<TextSegment> segments;

  /// Every object name the template references — bare names plus geometry
  /// accessor arguments — unique, in first-occurrence order across all
  /// slots. This order is the contract the codec re-binds parents by.
  final List<String> referenceNames;

  bool get hasExpressions => segments.any((s) => s is ExpressionSegment);

  /// The content with each slot replaced by its value ([decimals]
  /// digits, null = 2 — see [formatComputedValue]) or `?` when the
  /// expression is currently undefined. Never throws.
  String render(ExpressionEnv env, {int? decimals}) {
    final buffer = StringBuffer();
    for (final segment in segments) {
      switch (segment) {
        case LiteralSegment(:final text):
          buffer.write(text);
        case ExpressionSegment(:final expr):
          final value = evaluateExpression(expr, env);
          buffer.write(value == null
              ? '?'
              : formatComputedValue(value, decimals: decimals));
      }
    }
    return buffer.toString();
  }
}

void _validateCalls(Expr expr, String content, int slotOffset) {
  void fail(String message) =>
      throw FormatException(message, content, slotOffset);
  void walk(Expr e) {
    switch (e) {
      case NumberLiteral() || NameRef():
        break;
      case UnaryMinus(:final operand):
        walk(operand);
      case BinaryOp(:final left, :final right):
        walk(left);
        walk(right);
      case Call(:final name, :final args):
        final objectArity = _objectFunctionArity[name];
        if (objectArity != null) {
          if (args.length != objectArity) {
            fail("'$name' takes $objectArity "
                '${objectArity == 1 ? 'argument' : 'arguments'}');
          }
          for (final arg in args) {
            if (arg is! NameRef) {
              fail("Arguments of '$name' must be object names");
            }
          }
          return;
        }
        switch (numericFunctionArity(name)) {
          case null:
            fail("Unknown function '$name'");
          case (final min, final max):
            if (args.length < min || (max != null && args.length > max)) {
              fail(max == null
                  ? "'$name' takes at least $min arguments"
                  : "'$name' takes $min "
                      '${min == 1 ? 'argument' : 'arguments'}');
            }
        }
        args.forEach(walk);
    }
  }

  walk(expr);
}
