import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/construction/objects/arc.dart';
import 'package:regula/domain/construction/objects/centroid.dart';
import 'package:regula/domain/construction/objects/circle_center.dart';
import 'package:regula/domain/construction/objects/circle_center_point.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/harmonic_conjugate_point.dart';
import 'package:regula/domain/construction/objects/homothetic_point.dart';
import 'package:regula/domain/construction/objects/intersection_point.dart';
import 'package:regula/domain/construction/objects/line_angle.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/midpoint.dart';
import 'package:regula/domain/construction/objects/perpendicular_line.dart';
import 'package:regula/domain/construction/objects/projection_point.dart';
import 'package:regula/domain/construction/objects/ray.dart';
import 'package:regula/domain/construction/objects/sector.dart';
import 'package:regula/domain/construction/objects/segment.dart';
import 'package:regula/domain/construction/objects/vertex_angle.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/presentation/panels/object_kind_label.dart';

void main() {
  final a = FreePoint(id: 'a', position: Vec2.zero);
  final b = FreePoint(id: 'b', position: const Vec2(4, 0));
  final c = FreePoint(id: 'c', position: const Vec2(2, 3));
  final line1 = LineThroughTwoPoints(id: 'l1', point1: a, point2: b);
  final line2 = LineThroughTwoPoints(id: 'l2', point1: a, point2: c);

  test('concrete types shadow their kind fallback', () {
    expect(objectKindLabel(a), 'Point');
    expect(
      objectKindLabel(Midpoint(id: 'm', point1: a, point2: b)),
      'Midpoint',
    );
    expect(
      objectKindLabel(
        IntersectionPoint(
          id: 'x',
          curve1: line1,
          curve2: line2,
          branchIndex: 0,
        ),
      ),
      'Intersection point',
    );
    expect(
      objectKindLabel(Centroid(id: 'g', vertex1: a, vertex2: b, vertex3: c)),
      'Centroid',
    );
    expect(
      objectKindLabel(
        CircleCenter(
          id: 'cc',
          circle: CircleCenterPoint(id: 'k2', center: a, onCircle: b),
        ),
      ),
      'Circle center',
    );
    expect(
      objectKindLabel(ProjectionPoint(id: 'pr', point: c, line: line1)),
      'Projection point',
    );
    expect(
      objectKindLabel(HomotheticPoint(id: 'ho', point: c, center: a, ratio: 2)),
      'Homothetic point',
    );
    expect(
      objectKindLabel(
        HarmonicConjugatePoint(id: 'hc', point1: a, point2: b, point3: c),
      ),
      'Harmonic conjugate',
    );
  });

  test('line kinds', () {
    expect(objectKindLabel(line1), 'Line');
    expect(objectKindLabel(Segment(id: 's', point1: a, point2: b)), 'Segment');
    expect(objectKindLabel(Ray(id: 'r', origin: a, through: b)), 'Ray');
    expect(
      objectKindLabel(PerpendicularLine(id: 'p', through: c, reference: line1)),
      'Perpendicular line',
    );
  });

  test('circle and angle kinds', () {
    expect(
      objectKindLabel(CircleCenterPoint(id: 'k', center: a, onCircle: b)),
      'Circle',
    );
    expect(objectKindLabel(Arc(id: 'arc', start: a, via: c, end: b)), 'Arc');
    expect(
      objectKindLabel(Sector(id: 'sec', center: a, start: b, end: c)),
      'Sector',
    );
    expect(
      objectKindLabel(VertexAngle(id: 'v', arm1: a, vertex: b, arm2: c)),
      'Angle',
    );
    expect(
      objectKindLabel(LineAngle(id: 'la', line1: line1, line2: line2)),
      'Angle between lines',
    );
  });
}
