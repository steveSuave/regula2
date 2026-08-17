import 'dart:math' as math;

/// Numeric expression language for the text tool's `{…}` slots (Phase 58).
///
/// Pure numeric core with zero construction knowledge: geometry accessors
/// (`dist(A,B)`, …) and bare-name sugar reach the construction only through
/// the [ExpressionEnv] the caller supplies. Parsing throws only
/// [ExpressionFormatException]; evaluation never throws — unknown names,
/// bad arities, division by zero and non-finite results all yield null,
/// which the template renders as `?`.
///
/// Grammar (precedence low → high, `^` right-associative):
///
///     additive       := multiplicative (('+' | '-') multiplicative)*
///     multiplicative := unary (('*' | '/') unary)*
///     unary          := '-' unary | power
///     power          := primary ('^' unary)?
///     primary        := number | name | name '(' args ')' | '(' additive ')'
///
/// Unary minus binds looser than `^` (the math convention): `-2^2 = -4`,
/// while `2^-3` still parses because the exponent re-enters at `unary`.
///
/// Trigonometry works in **degrees** (`sin(30) = 0.5`, `atan(1) = 45`) so
/// it composes with the geometry accessor `angle(…)`, which — like the rest
/// of the app — reports degrees.
///
/// The constants `pi` and `e` resolve *before* [ExpressionEnv.variable], so
/// they shadow objects so named (the lowercase auto-name pool contains `e`).
/// Arguments of geometry accessors are always object names — `len(e)` is
/// the object named `e`, never Euler's number.

/// Parse error: the one thing [parseExpression] ever throws.
class ExpressionFormatException extends FormatException {
  const ExpressionFormatException(super.message, super.source, super.offset);
}

/// Expression AST. Sealed so evaluators and reference walkers switch
/// exhaustively.
sealed class Expr {
  const Expr();
}

class NumberLiteral extends Expr {
  const NumberLiteral(this.value);

  final double value;
}

/// A bare identifier: a constant (`pi`, `e`) or an object reference
/// resolved through [ExpressionEnv.variable].
class NameRef extends Expr {
  const NameRef(this.name);

  final String name;
}

class UnaryMinus extends Expr {
  const UnaryMinus(this.operand);

  final Expr operand;
}

enum BinOp { add, subtract, multiply, divide, power }

class BinaryOp extends Expr {
  const BinaryOp(this.op, this.left, this.right);

  final BinOp op;
  final Expr left;
  final Expr right;
}

class Call extends Expr {
  const Call(this.name, this.args);

  final String name;
  final List<Expr> args;
}

/// What an expression evaluates against: the geometry side of the language.
///
/// [variable] is the bare-name sugar (segment → length, measurement →
/// value, angle → degrees); [objectFunction] handles the accessor calls
/// whose arguments are object *names*, not numbers. Both return null for
/// anything unknown, mistyped or currently undefined.
abstract interface class ExpressionEnv {
  double? variable(String name);

  bool isObjectFunction(String name);

  double? objectFunction(String name, List<String> argNames);
}

/// An env with no objects at all: constants and numeric functions only.
class EmptyExpressionEnv implements ExpressionEnv {
  const EmptyExpressionEnv();

  @override
  double? variable(String name) => null;

  @override
  bool isObjectFunction(String name) => false;

  @override
  double? objectFunction(String name, List<String> argNames) => null;
}

const double _degPerRad = 180 / math.pi;

/// Numeric function registry: name → (min arity, max arity or null =
/// unbounded, implementation). Table-driven so later additions (Phase 58's
/// deferred integrals included) are one-line entries.
final Map<String, (int, int?, double Function(List<double>))>
_numericFunctions = {
  'sqrt': (1, 1, (a) => math.sqrt(a[0])),
  'sin': (1, 1, (a) => math.sin(a[0] / _degPerRad)),
  'cos': (1, 1, (a) => math.cos(a[0] / _degPerRad)),
  'tan': (1, 1, (a) => math.tan(a[0] / _degPerRad)),
  'asin': (1, 1, (a) => math.asin(a[0]) * _degPerRad),
  'acos': (1, 1, (a) => math.acos(a[0]) * _degPerRad),
  'atan': (1, 1, (a) => math.atan(a[0]) * _degPerRad),
  'abs': (1, 1, (a) => a[0].abs()),
  'round': (1, 1, (a) => a[0].roundToDouble()),
  'floor': (1, 1, (a) => a[0].floorToDouble()),
  'ceil': (1, 1, (a) => a[0].ceilToDouble()),
  'min': (2, null, (a) => a.reduce(math.min)),
  'max': (2, null, (a) => a.reduce(math.max)),
};

/// The numeric function names, for callers separating function heads from
/// object references (template validation, `referenceNames`).
Set<String> get numericFunctionNames => _numericFunctions.keys.toSet();

/// `(min, max)` arity of a numeric function (max null = unbounded), or
/// null for names that aren't numeric functions. For validation at dialog
/// time — the evaluator itself just yields null on a mismatch.
(int, int?)? numericFunctionArity(String name) {
  final entry = _numericFunctions[name];
  return entry == null ? null : (entry.$1, entry.$2);
}

/// Reserved constant names; resolved before [ExpressionEnv.variable].
const Set<String> constantNames = {'pi', 'e'};

/// Parses [source] into an AST. Throws [ExpressionFormatException] — and
/// nothing else — on malformed input.
Expr parseExpression(String source) => _Parser(source).parse();

/// Evaluates [expr] against [env]. Null means undefined — unknown name,
/// arity/kind mismatch, or a non-finite result — and never an exception.
double? evaluateExpression(Expr expr, ExpressionEnv env) {
  final value = _eval(expr, env);
  return value != null && value.isFinite ? value : null;
}

/// The object references [expr] makes: bare names (constants excluded)
/// plus every geometry-accessor argument, in first-occurrence order,
/// deduplicated. [isObjectFunction] tells accessor calls apart from
/// numeric ones (whose arguments are expressions, not references).
List<String> referenceNamesIn(
  Expr expr,
  bool Function(String name) isObjectFunction,
) {
  final names = <String>{};
  void walk(Expr e) {
    switch (e) {
      case NumberLiteral():
        break;
      case NameRef(:final name):
        if (!constantNames.contains(name)) {
          names.add(name);
        }
      case UnaryMinus(:final operand):
        walk(operand);
      case BinaryOp(:final left, :final right):
        walk(left);
        walk(right);
      case Call(:final name, :final args):
        if (isObjectFunction(name)) {
          for (final arg in args) {
            if (arg case NameRef(name: final argName)) {
              names.add(argName);
            }
          }
        } else {
          args.forEach(walk);
        }
    }
  }

  walk(expr);
  return names.toList();
}

double? _eval(Expr expr, ExpressionEnv env) {
  switch (expr) {
    case NumberLiteral(:final value):
      return value;
    case NameRef(:final name):
      return switch (name) {
        'pi' => math.pi,
        'e' => math.e,
        _ => env.variable(name),
      };
    case UnaryMinus(:final operand):
      final value = _eval(operand, env);
      return value == null ? null : -value;
    case BinaryOp(:final op, :final left, :final right):
      final l = _eval(left, env);
      final r = _eval(right, env);
      if (l == null || r == null) {
        return null;
      }
      return switch (op) {
        BinOp.add => l + r,
        BinOp.subtract => l - r,
        BinOp.multiply => l * r,
        BinOp.divide => l / r,
        BinOp.power => math.pow(l, r).toDouble(),
      };
    case Call(:final name, :final args):
      if (env.isObjectFunction(name)) {
        final argNames = <String>[];
        for (final arg in args) {
          if (arg case NameRef(name: final argName)) {
            argNames.add(argName);
          } else {
            return null;
          }
        }
        return env.objectFunction(name, argNames);
      }
      final entry = _numericFunctions[name];
      if (entry == null) {
        return null;
      }
      final (minArity, maxArity, fn) = entry;
      if (args.length < minArity ||
          (maxArity != null && args.length > maxArity)) {
        return null;
      }
      final values = <double>[];
      for (final arg in args) {
        final value = _eval(arg, env);
        if (value == null) {
          return null;
        }
        values.add(value);
      }
      return fn(values);
  }
}

// ---------------------------------------------------------------------------
// Tokenizer + recursive-descent parser
// ---------------------------------------------------------------------------

enum _TokenType { number, name, symbol, end }

class _Token {
  const _Token(this.type, this.text, this.offset);

  final _TokenType type;
  final String text;
  final int offset;
}

final RegExp _letter = RegExp(r'[\p{L}_]', unicode: true);
final RegExp _letterOrDigit = RegExp(r'[\p{L}\p{Nd}_]', unicode: true);
final RegExp _digit = RegExp(r'[0-9]');

/// Typed alternates users paste from math text, normalized at token level.
const Map<String, String> _symbolAliases = {
  '×': '*',
  '·': '*',
  '÷': '/',
  '−': '-',
};

class _Parser {
  _Parser(this.source) {
    _tokens = _tokenize();
  }

  final String source;
  late final List<_Token> _tokens;
  int _index = 0;

  Never _fail(String message, int offset) =>
      throw ExpressionFormatException(message, source, offset);

  List<_Token> _tokenize() {
    final tokens = <_Token>[];
    var i = 0;
    while (i < source.length) {
      final ch = source[i];
      if (ch.trim().isEmpty) {
        i++;
        continue;
      }
      if (_digit.hasMatch(ch) || (ch == '.' && _peekIsDigit(i + 1))) {
        final start = i;
        while (i < source.length && _digit.hasMatch(source[i])) {
          i++;
        }
        if (i < source.length && source[i] == '.') {
          if (!_peekIsDigit(i + 1)) {
            _fail('Expected digits after the decimal point', i);
          }
          i++;
          while (i < source.length && _digit.hasMatch(source[i])) {
            i++;
          }
        }
        tokens.add(
          _Token(_TokenType.number, source.substring(start, i), start),
        );
        continue;
      }
      if (ch == 'π') {
        tokens.add(_Token(_TokenType.name, 'pi', i));
        i++;
        continue;
      }
      if (_letter.hasMatch(ch)) {
        final start = i;
        while (i < source.length && _letterOrDigit.hasMatch(source[i])) {
          i++;
        }
        tokens.add(_Token(_TokenType.name, source.substring(start, i), start));
        continue;
      }
      final symbol = _symbolAliases[ch] ?? ch;
      if ('+-*/^(),'.contains(symbol)) {
        tokens.add(_Token(_TokenType.symbol, symbol, i));
        i++;
        continue;
      }
      _fail("Unexpected character '$ch'", i);
    }
    tokens.add(_Token(_TokenType.end, '', source.length));
    return tokens;
  }

  bool _peekIsDigit(int i) => i < source.length && _digit.hasMatch(source[i]);

  _Token get _current => _tokens[_index];

  bool _matchSymbol(String text) {
    if (_current.type == _TokenType.symbol && _current.text == text) {
      _index++;
      return true;
    }
    return false;
  }

  Expr parse() {
    final expr = _additive();
    if (_current.type != _TokenType.end) {
      _fail("Unexpected '${_current.text}'", _current.offset);
    }
    return expr;
  }

  Expr _additive() {
    var left = _multiplicative();
    while (true) {
      if (_matchSymbol('+')) {
        left = BinaryOp(BinOp.add, left, _multiplicative());
      } else if (_matchSymbol('-')) {
        left = BinaryOp(BinOp.subtract, left, _multiplicative());
      } else {
        return left;
      }
    }
  }

  Expr _multiplicative() {
    var left = _unary();
    while (true) {
      if (_matchSymbol('*')) {
        left = BinaryOp(BinOp.multiply, left, _unary());
      } else if (_matchSymbol('/')) {
        left = BinaryOp(BinOp.divide, left, _unary());
      } else {
        return left;
      }
    }
  }

  Expr _unary() {
    if (_matchSymbol('-')) {
      return UnaryMinus(_unary());
    }
    return _power();
  }

  Expr _power() {
    final base = _primary();
    if (_matchSymbol('^')) {
      // The exponent re-enters at unary so `2^-3` parses; recursing through
      // _unary → _power also gives `^` its right associativity.
      return BinaryOp(BinOp.power, base, _unary());
    }
    return base;
  }

  Expr _primary() {
    final token = _current;
    switch (token.type) {
      case _TokenType.number:
        _index++;
        return NumberLiteral(double.parse(token.text));
      case _TokenType.name:
        _index++;
        if (_matchSymbol('(')) {
          final args = <Expr>[];
          if (!_matchSymbol(')')) {
            args.add(_additive());
            while (_matchSymbol(',')) {
              args.add(_additive());
            }
            if (!_matchSymbol(')')) {
              _fail("Expected ')' or ','", _current.offset);
            }
          }
          return Call(token.text, args);
        }
        return NameRef(token.text);
      case _TokenType.symbol:
        if (_matchSymbol('(')) {
          final expr = _additive();
          if (!_matchSymbol(')')) {
            _fail("Expected ')'", _current.offset);
          }
          return expr;
        }
        _fail("Unexpected '${token.text}'", token.offset);
      case _TokenType.end:
        _fail('Unexpected end of expression', token.offset);
    }
  }
}
