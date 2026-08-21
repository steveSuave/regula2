import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/prover/rule.dart';

void main() {
  group('the rule table', () {
    test('parses in full, with unique names', () {
      expect(ddCoreRules, hasLength(26));
      expect({
        for (final rule in ddCoreRules) rule.name,
      }, hasLength(ddCoreRules.length));
    });

    test('a conclusion over an unbound variable is refused', () {
      expect(
        () => Rule.parse('bad', 'coll(a,b,c) => coll(a,b,d)'),
        throwsArgumentError,
      );
    });

    test('a wrong arity is refused', () {
      expect(
        () => Rule.parse('bad', 'coll(a,b) => coll(a,b,a)'),
        throwsArgumentError,
      );
    });

    test('an unknown kind is refused', () {
      expect(
        () => Rule.parse('bad', 'lineary(a,b,c) => coll(a,b,c)'),
        throwsArgumentError,
      );
    });

    test('a spec without exactly one conclusion is refused', () {
      expect(() => Rule.parse('bad', 'coll(a,b,c)'), throwsArgumentError);
      expect(
        () => Rule.parse('bad', 'coll(a,b,c) => coll(a,c,b) => coll(b,a,c)'),
        throwsArgumentError,
      );
    });

    test('round-trips through toString readably', () {
      final rule = Rule.parse('mid', 'midp(m,a,b) => coll(m,a,b)');
      expect('$rule', 'mid: midp(m,a,b) => coll(m,a,b)');
    });
  });
}
