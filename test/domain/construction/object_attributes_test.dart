import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/construction/object_attributes.dart';

void main() {
  group('ObjectAttributes', () {
    test('defaults: visible, labeled, unnamed, theme-default color', () {
      const a = ObjectAttributes();
      expect(a.name, isEmpty);
      expect(a.colorArgb, isNull);
      expect(a.visible, isTrue);
      expect(a.labelVisible, isTrue);
      expect(a.strokeWidth, 2.0);
      expect(a.pointSize, 4.0);
      expect(a.fillAlpha, isNull);
      expect(a.valueDecimals, isNull, reason: 'null = kind default');
    });

    test('copyWith changes only the requested field', () {
      const a = ObjectAttributes(name: 'A');
      final b = a.copyWith(colorArgb: 0xFF112233);
      expect(b.name, 'A');
      expect(b.colorArgb, 0xFF112233);
      expect(a.colorArgb, isNull, reason: 'original must be unchanged');
    });

    test('value equality', () {
      expect(
        const ObjectAttributes(name: 'A', strokeWidth: 3),
        const ObjectAttributes(name: 'A', strokeWidth: 3),
      );
      expect(
        const ObjectAttributes(name: 'A'),
        isNot(const ObjectAttributes(name: 'B')),
      );
    });

    test('JSON round-trip preserves every field', () {
      const a = ObjectAttributes(
        name: 'circumcircle',
        colorArgb: 0xFF00FF00,
        visible: false,
        labelVisible: false,
        strokeWidth: 1.5,
        pointSize: 6,
        fillAlpha: 0.25,
        valueDecimals: 4,
      );
      expect(ObjectAttributes.fromJson(a.toJson()), a);
    });

    test('JSON round-trip preserves nulls (theme-default color, no fill)', () {
      const a = ObjectAttributes();
      expect(ObjectAttributes.fromJson(a.toJson()), a);
    });
  });
}
