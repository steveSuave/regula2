import 'package:flutter_test/flutter_test.dart';
import 'package:regula/application/providers/viewport_provider.dart';
import 'package:regula/domain/construction/object_attributes.dart';
import 'package:regula/domain/construction/objects/area_measurement.dart';
import 'package:regula/domain/construction/objects/distance_measurement.dart';
import 'package:regula/domain/construction/objects/expression_text.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/polygon.dart';
import 'package:regula/domain/construction/objects/segment.dart';
import 'package:regula/domain/construction/objects/vertex_angle.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/presentation/canvas/canvas_viewport.dart';
import 'package:regula/presentation/canvas/label_layout.dart';

void main() {
  const viewport = CanvasViewport(ViewportState());

  FreePoint point(ObjectAttributes attributes) =>
      FreePoint(id: 'p', position: const Vec2(10, -20), attributes: attributes);

  // A 3–4–5 hypotenuse, so the value part is a clean '5.00'.
  Segment segment(ObjectAttributes attributes) => Segment(
        id: 's',
        point1: FreePoint(id: 'a', position: const Vec2(0, 0)),
        point2: FreePoint(id: 'b', position: const Vec2(3, 4)),
        attributes: attributes,
      );

  // A right angle at the origin: (5,0) → (0,0) → (0,7), CCW 90°.
  VertexAngle angle(ObjectAttributes attributes) => VertexAngle(
        id: 'v',
        arm1: FreePoint(id: 'a1', position: const Vec2(5, 0)),
        vertex: FreePoint(id: 'vx', position: const Vec2(0, 0)),
        arm2: FreePoint(id: 'a2', position: const Vec2(0, 7)),
        attributes: attributes,
      );

  group('labelText', () {
    test('named + labelVisible without showValue: bare name', () {
      expect(labelText(segment(const ObjectAttributes(name: 'c'))), 'c');
    });

    test('named + showValue: name = value', () {
      expect(
        labelText(segment(const ObjectAttributes(name: 'c', showValue: true))),
        'c = 5.00',
      );
      expect(
        labelText(angle(const ObjectAttributes(name: 'α', showValue: true))),
        'α = 90.0°',
      );
    });

    test('showValue with the name part hidden: bare value', () {
      expect(
        labelText(segment(const ObjectAttributes(showValue: true))),
        '5.00',
        reason: 'unnamed',
      );
      expect(
        labelText(
          segment(const ObjectAttributes(
            name: 'c',
            labelVisible: false,
            showValue: true,
          )),
        ),
        '5.00',
        reason: 'labelVisible off hides only the name part',
      );
    });

    test('no part at all: null', () {
      expect(labelText(segment(const ObjectAttributes())), isNull);
      expect(
        labelText(
          segment(const ObjectAttributes(name: 'c', labelVisible: false)),
        ),
        isNull,
      );
    });

    test('showValue on a kind without a value never adds a part', () {
      expect(
        labelText(point(const ObjectAttributes(name: 'A', showValue: true))),
        'A',
      );
      expect(labelText(point(const ObjectAttributes(showValue: true))), isNull);
    });

    test('a measurement always has a value part, showValue or not', () {
      // The same 3–4–5 endpoints as the segment fixture: value '5.00'.
      DistanceMeasurement distance(ObjectAttributes attributes) =>
          DistanceMeasurement(
            id: 'd',
            point1: FreePoint(id: 'a', position: const Vec2(0, 0)),
            point2: FreePoint(id: 'b', position: const Vec2(3, 4)),
            attributes: attributes,
          );
      expect(labelText(distance(const ObjectAttributes())), '5.00');
      expect(
        labelText(distance(const ObjectAttributes(name: 'a'))),
        'a = 5.00',
      );
      expect(
        labelText(
          distance(const ObjectAttributes(name: 'a', labelVisible: false)),
        ),
        '5.00',
        reason: 'labelVisible off hides only the name part',
      );
    });

    test('valueDecimals overrides the kind-default decimal count', () {
      expect(
        labelText(
          segment(const ObjectAttributes(showValue: true, valueDecimals: 4)),
        ),
        '5.0000',
      );
      expect(
        labelText(
          angle(const ObjectAttributes(showValue: true, valueDecimals: 0)),
        ),
        '90°',
      );
      // The same 3–4–5 endpoints as the segment fixture.
      final distance = DistanceMeasurement(
        id: 'd',
        point1: FreePoint(id: 'a', position: const Vec2(0, 0)),
        point2: FreePoint(id: 'b', position: const Vec2(3, 4)),
        attributes: const ObjectAttributes(valueDecimals: 1),
      );
      expect(labelText(distance), '5.0');
    });

    test('a text renders its content only — the name never composes', () {
      final text = ExpressionText(
        id: 't',
        content: 'AB = 5.00 cm',
        anchor: Vec2.zero,
        references: const [],
        attributes: const ObjectAttributes(name: 'a', labelVisible: true),
      );
      expect(labelText(text), 'AB = 5.00 cm',
          reason: 'prefixing the name would read as a bogus equation chain');
    });

    test('an area measurement formats through formatArea', () {
      final square = Polygon(
        id: 'p',
        vertices: [
          FreePoint(id: 'a', position: const Vec2(0, 0)),
          FreePoint(id: 'b', position: const Vec2(4, 0)),
          FreePoint(id: 'c', position: const Vec2(4, 3)),
          FreePoint(id: 'd', position: const Vec2(0, 3)),
        ],
      );
      final area = AreaMeasurement(id: 'ar', subject: square);
      expect(labelText(area), '12.00');
    });
  });

  test('the rect sits at worldToScreen(anchor) + the stored offset', () {
    final named = point(
      const ObjectAttributes(name: 'A', labelDx: 14, labelDy: 9),
    );
    final rect = labelScreenRect(named, viewport)!;
    final anchor = viewport.worldToScreen(const Vec2(10, -20));
    expect(rect.topLeft, anchor + const Offset(14, 9));
    expect(rect.width, greaterThan(0));
    expect(rect.height, greaterThan(0));
  });

  test('the default offset matches the painter\'s historical (6, -18)', () {
    final named = point(const ObjectAttributes(name: 'A'));
    final rect = labelScreenRect(named, viewport)!;
    expect(
      rect.topLeft,
      viewport.worldToScreen(const Vec2(10, -20)) + const Offset(6, -18),
    );
  });

  test('a longer name widens the rect', () {
    final short = labelScreenRect(
      point(const ObjectAttributes(name: 'A')),
      viewport,
    )!;
    final long = labelScreenRect(
      point(const ObjectAttributes(name: 'circumcircle')),
      viewport,
    )!;
    expect(long.width, greaterThan(short.width));
  });

  test('a non-default labelFontSize grows the rect', () {
    final normal = labelScreenRect(
      point(const ObjectAttributes(name: 'A')),
      viewport,
    )!;
    final large = labelScreenRect(
      point(const ObjectAttributes(name: 'A', labelFontSize: 22)),
      viewport,
    )!;
    expect(large.width, greaterThan(normal.width));
    expect(large.height, greaterThan(normal.height));
    expect(large.topLeft, normal.topLeft,
        reason: 'size changes the extent, not the anchor offset');
  });

  group('angle labels sit on the bisector past the arc (Phase 63)', () {
    // The fixture angle opens from +x to +y, so the world bisector is 45°
    // up-right; on the default (unrotated, y-flipped) viewport that's
    // screen direction (√2/2, −√2/2).
    ObjectAttributes attrs({double radius = 28, double dx = 0, double dy = 0}) =>
        ObjectAttributes(
          showValue: true,
          angleMarkerRadius: radius,
          labelDx: dx,
          labelDy: dy,
        );

    Offset vertexScreen() => viewport.worldToScreen(const Vec2(0, 0));

    test('the text is centered on the bisector, clear of the marker', () {
      final rect = labelScreenRect(angle(attrs()), viewport)!;
      final toCenter = rect.center - vertexScreen();
      expect(toCenter.dx, greaterThan(0));
      expect(toCenter.dy, lessThan(0), reason: 'up-right on screen');
      expect(toCenter.dx, closeTo(-toCenter.dy, 0.001),
          reason: 'centered on the 45° bisector');
      // The rect's nearest corner to the vertex must clear the arc.
      final near = Offset(rect.left, rect.bottom) - vertexScreen();
      expect(near.distance, greaterThanOrEqualTo(28),
          reason: 'the near edge sits past the marker radius');
    });

    test('a larger marker radius pushes the label farther out', () {
      final small = labelScreenRect(angle(attrs()), viewport)!;
      final large = labelScreenRect(angle(attrs(radius: 48)), viewport)!;
      expect(
        (large.center - vertexScreen()).distance,
        greaterThan((small.center - vertexScreen()).distance + 15),
      );
    });

    test('labelDx/labelDy still nudge from the bisector base', () {
      final base = labelScreenRect(angle(attrs()), viewport)!;
      final nudged = labelScreenRect(angle(attrs(dx: 10, dy: 5)), viewport)!;
      expect(nudged.topLeft, base.topLeft + const Offset(10, 5));
    });
  });

  test('a value-only label has a rect (unnamed segment, showValue on)', () {
    final rect = labelScreenRect(
      segment(const ObjectAttributes(showValue: true)),
      viewport,
    );
    expect(rect, isNotNull,
        reason: 'the value text must be grabbable for label dragging');
  });

  test('an undefined segment paints no value rect', () {
    final degenerate = Segment(
      id: 's0',
      point1: FreePoint(id: 'a', position: const Vec2(1, 1)),
      point2: FreePoint(id: 'b', position: const Vec2(1, 1)),
      attributes: const ObjectAttributes(showValue: true),
    );
    expect(labelScreenRect(degenerate, viewport), isNull);
  });

  test('unpainted labels have no rect', () {
    expect(
      labelScreenRect(point(const ObjectAttributes()), viewport),
      isNull,
      reason: 'unnamed',
    );
    expect(
      labelScreenRect(
        point(const ObjectAttributes(name: 'A', labelVisible: false)),
        viewport,
      ),
      isNull,
      reason: 'label hidden',
    );
    expect(
      labelScreenRect(
        point(const ObjectAttributes(name: 'A', visible: false)),
        viewport,
      ),
      isNull,
      reason: 'object hidden',
    );
  });
}
