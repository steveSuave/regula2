import 'dart:math' as math;

import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/geo_object.dart';
import 'package:regula/domain/construction/object_attributes.dart';
import 'package:regula/domain/construction/objects/angle_bisector_line.dart';
import 'package:regula/domain/construction/objects/apollonius_circle.dart';
import 'package:regula/domain/construction/objects/arc.dart';
import 'package:regula/domain/construction/objects/area_measurement.dart';
import 'package:regula/domain/construction/objects/bifocal_conic.dart';
import 'package:regula/domain/construction/objects/central_reflection_point.dart';
import 'package:regula/domain/construction/objects/centroid.dart';
import 'package:regula/domain/construction/objects/circle_center.dart';
import 'package:regula/domain/construction/objects/circle_center_point.dart';
import 'package:regula/domain/construction/objects/circumcenter.dart';
import 'package:regula/domain/construction/objects/compass_circle.dart';
import 'package:regula/domain/construction/objects/diameter_circle.dart';
import 'package:regula/domain/construction/objects/distance_measurement.dart';
import 'package:regula/domain/construction/objects/expression_text.dart';
import 'package:regula/domain/construction/objects/five_point_conic.dart';
import 'package:regula/domain/construction/objects/fixed_angle_line.dart';
import 'package:regula/domain/construction/objects/fixed_radius_circle.dart';
import 'package:regula/domain/construction/objects/focal_conic.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/harmonic_conjugate_point.dart';
import 'package:regula/domain/construction/objects/homothetic_point.dart';
import 'package:regula/domain/construction/objects/incenter.dart';
import 'package:regula/domain/construction/objects/inscribed_circle.dart';
import 'package:regula/domain/construction/objects/intersection_point.dart';
import 'package:regula/domain/construction/objects/length_measurement.dart';
import 'package:regula/domain/construction/objects/line_angle.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/locus.dart';
import 'package:regula/domain/construction/objects/midpoint.dart';
import 'package:regula/domain/construction/objects/nine_point_circle.dart';
import 'package:regula/domain/construction/objects/orthocenter.dart';
import 'package:regula/domain/construction/objects/parallel_line.dart';
import 'package:regula/domain/construction/objects/perpendicular_bisector_line.dart';
import 'package:regula/domain/construction/objects/perpendicular_line.dart';
import 'package:regula/domain/construction/objects/point_on_object.dart';
import 'package:regula/domain/construction/objects/polar_line.dart';
import 'package:regula/domain/construction/objects/polygon.dart';
import 'package:regula/domain/construction/objects/projection_point.dart';
import 'package:regula/domain/construction/objects/radical_axis_line.dart';
import 'package:regula/domain/construction/objects/ratio_apollonius_circle.dart';
import 'package:regula/domain/construction/objects/ray.dart';
import 'package:regula/domain/construction/objects/reflected_point.dart';
import 'package:regula/domain/construction/objects/rotated_point.dart';
import 'package:regula/domain/construction/objects/scaled_compass_circle.dart';
import 'package:regula/domain/construction/objects/sector.dart';
import 'package:regula/domain/construction/objects/segment.dart';
import 'package:regula/domain/construction/objects/segment_ratio_point.dart';
import 'package:regula/domain/construction/objects/slope_measurement.dart';
import 'package:regula/domain/construction/objects/stated_radius_circle.dart';
import 'package:regula/domain/construction/objects/tangent_line.dart';
import 'package:regula/domain/construction/objects/three_point_circle.dart';
import 'package:regula/domain/construction/objects/translated_point.dart';
import 'package:regula/domain/construction/objects/two_line_bisector_line.dart';
import 'package:regula/domain/construction/objects/vertex_angle.dart';
import 'package:regula/domain/math/rational.dart';
import 'package:regula/domain/math/vec2.dart';

/// A construction using every concrete [GeoObject] kind at least once,
/// with non-default attributes sprinkled in. Shared safety net: a kind
/// missing from the codec fails its round-trip test, and a kind whose
/// projective bridge disagrees with its affine view fails the bridge test.
Construction buildKitchenSink() {
  final construction = Construction();
  final a = FreePoint(
    id: 'a',
    position: const Vec2(0, 0),
    attributes: const ObjectAttributes(
      name: 'A',
      colorArgb: 0xFFAA3366,
      labelVisible: false,
      labelDx: 14,
      labelDy: 9,
      pointSize: 6,
    ),
  );
  final b = FreePoint(id: 'b', position: const Vec2(4, 0));
  final c = FreePoint(id: 'c', position: const Vec2(1, 3));
  construction
    ..add(a)
    ..add(b)
    ..add(c);

  // Non-default lineClip (Phase 44) so the round-trip must carry it.
  final lineAb = LineThroughTwoPoints(
    id: 'lab',
    point1: a,
    point2: b,
    attributes: const ObjectAttributes(lineClip: 1),
  );
  final ratio = SegmentRatioPoint(
    id: 'ratio',
    point1: a,
    point2: b,
    ratio: 2.25,
  );
  construction
    ..add(Midpoint(id: 'mid', point1: a, point2: b))
    ..add(ratio)
    ..add(lineAb)
    ..add(
      Segment(
        id: 'seg',
        point1: a,
        point2: c,
        attributes: const ObjectAttributes(
          strokeWidth: 4,
          visible: false,
          dashPeriod: 8,
          labelFontSize: 16,
          showValue: true,
          tickMarks: 2,
        ),
      ),
    )
    ..add(Ray(id: 'ray', origin: b, through: c))
    ..add(Centroid(id: 'cent', vertex1: a, vertex2: b, vertex3: c))
    ..add(Orthocenter(id: 'orth', vertex1: a, vertex2: b, vertex3: c))
    ..add(Incenter(id: 'inc', vertex1: a, vertex2: b, vertex3: c))
    ..add(Circumcenter(id: 'circ', vertex1: a, vertex2: b, vertex3: c));

  final perp = PerpendicularLine(id: 'perp', through: c, reference: lineAb);
  final circle = CircleCenterPoint(id: 'cc', center: a, onCircle: b);
  final tpc = ThreePointCircle(id: 'tpc', point1: a, point2: b, point3: c);
  final arc = Arc(id: 'arc', start: a, via: c, end: b);
  final sector = Sector(
    id: 'sec',
    center: a,
    start: b,
    end: c,
    attributes: const ObjectAttributes(fillAlpha: 0.25),
  );
  construction
    ..add(perp)
    ..add(ParallelLine(id: 'par', through: c, reference: lineAb))
    ..add(AngleBisectorLine(id: 'bis', arm1: a, vertex: b, arm2: c))
    ..add(PerpendicularBisectorLine(id: 'pbis', point1: a, point2: c))
    ..add(circle)
    ..add(CircleCenter(id: 'ccen', circle: circle))
    ..add(
      TwoLineBisectorLine(id: 'llbis', line1: lineAb, line2: perp, branch: 1),
    )
    // The ratio point sits at (9, 0), outside the radius-4 circle, so the
    // tangent is defined and its geometry participates in the round-trip.
    ..add(TangentLine(id: 'tan', point: ratio, circle: circle, branch: 1))
    ..add(PolarLine(id: 'pol', point: ratio, circle: circle))
    ..add(tpc)
    ..add(NinePointCircle(id: 'npc', vertex1: a, vertex2: b, vertex3: c))
    ..add(InscribedCircle(id: 'insc', vertex1: a, vertex2: b, vertex3: c))
    ..add(ApolloniusCircle(id: 'apo', point1: a, point2: b, point3: c))
    ..add(RadicalAxisLine(id: 'rax', circle1: circle, circle2: tpc))
    ..add(FixedRadiusCircle(id: 'frc', center: c, radius: 2.5))
    ..add(
      CompassCircle(id: 'comp', radiusPoint1: a, radiusPoint2: b, center: c),
    )
    ..add(DiameterCircle(id: 'dia', point1: a, point2: c))
    ..add(arc)
    ..add(sector)
    ..add(
      VertexAngle(
        id: 'vang',
        arm1: a,
        vertex: b,
        arm2: c,
        attributes: const ObjectAttributes(
          angleMarkerRadius: 28,
          fillAlpha: 0.25,
        ),
      ),
    )
    // One legacy (null signs — must encode with no params and decode back
    // to the acute fold) and one tap-picked wedge.
    ..add(LineAngle(id: 'lang', line1: lineAb, line2: perp))
    ..add(
      LineAngle(id: 'lang2', line1: lineAb, line2: perp, sign1: -1, sign2: 1),
    )
    ..add(
      IntersectionPoint(
        id: 'int',
        curve1: lineAb,
        curve2: circle,
        branchIndex: 1,
      ),
    )
    ..add(PointOnObject(id: 'poo', curve: circle, parameter: 1.25));
  // Non-default locus params, so the round-trip must carry all three;
  // the traced midpoint exercises the constructor's driver-dependency
  // walk on the decode side.
  final locusDriver = PointOnObject(id: 'ldrv', curve: circle, parameter: 0.5);
  final locusTrace = Midpoint(id: 'ltrace', point1: locusDriver, point2: a);
  construction
    ..add(locusDriver)
    ..add(locusTrace)
    ..add(
      Locus(
        id: 'locus',
        driver: locusDriver,
        traced: locusTrace,
        sampleCount: 16,
        center: 0.5,
        halfSpan: 40,
      ),
    );
  // Four vertices, so the round-trip exercises variable arity beyond
  // the minimum three (the ratio point sits at (9, 0)).
  final poly = Polygon(
    id: 'poly',
    vertices: [a, b, ratio, c],
    attributes: const ObjectAttributes(fillAlpha: 0.25),
  );
  construction
    ..add(poly)
    ..add(DistanceMeasurement(id: 'dist', point1: a, point2: c))
    // Both allowed subject kinds, so the any(0) + constructor validation
    // path round-trips each.
    ..add(AreaMeasurement(id: 'parea', subject: poly))
    ..add(AreaMeasurement(id: 'carea', subject: circle))
    // All three circular subject shapes: circumference, arc length,
    // sector perimeter.
    ..add(LengthMeasurement(id: 'clen', subject: circle))
    ..add(LengthMeasurement(id: 'alen', subject: arc))
    ..add(LengthMeasurement(id: 'slen', subject: sector))
    ..add(SlopeMeasurement(id: 'slope', subject: lineAb))
    ..add(ReflectedPoint(id: 'refl', point: c, mirror: lineAb))
    ..add(ProjectionPoint(id: 'proj', point: c, line: lineAb))
    // Non-default negative ratio, so the round-trip must carry it.
    ..add(HomotheticPoint(id: 'homo', point: c, center: a, ratio: -1.5))
    ..add(
      HarmonicConjugatePoint(id: 'harm', point1: a, point2: b, point3: ratio),
    )
    ..add(CentralReflectionPoint(id: 'crefl', point: c, center: a))
    ..add(RotatedPoint(id: 'rot', point: b, center: a, angle: 0.75))
    ..add(TranslatedPoint(id: 'trans', point: c, vectorFrom: a, vectorTo: b))
    // One referencing text (parents re-bound positionally against the
    // content's referenceNames on decode) and one static text (empty
    // parents, pure literal).
    ..add(
      ExpressionText(
        id: 'text',
        content: 'AC = {dist(A, C)} u',
        anchor: const Vec2(2, 5),
        references: [a, c],
      ),
    )
    ..add(
      ExpressionText(
        id: 'text2',
        content: 'plain note',
        anchor: const Vec2(-1, -2),
        references: const [],
      ),
    );
  return construction;
}

/// The kinds added *after* format version 1 — a second construction
/// rather than more of [buildKitchenSink].
///
/// [buildKitchenSink] is frozen bit-for-bit by
/// `test/fixtures/v1/kitchen-sink-v1.json`, which the v1 corpus decodes
/// and compares against the live builder (Phase 118). That file is what a
/// v1 app wrote, so a kind v1 never knew cannot honestly appear in it —
/// and the pin is the point, not an obstacle. Post-v1 kinds live here
/// instead, and the sweeps that mean "every concrete kind" run over both.
///
/// Every kind here still encodes to a v1 *document*: adding an object type
/// is novelty, not misreading (PLAN §"The version field is a requirement,
/// not a build number") — a v1 reader refuses the unknown type outright
/// rather than drawing the wrong thing.
Construction buildPostV1Kinds() {
  final construction = Construction();
  // Five points of the ellipse x²/4 + y² = 1, so the conic is a genuine
  // one: `circle` is null and only the projective view carries it.
  final points = [
    for (final (i, t) in const [0.0, 1.0, 2.0, 3.0, 4.0].indexed)
      FreePoint(id: 'q$i', position: Vec2(2 * math.cos(t), math.sin(t))),
  ];
  for (final point in points) {
    construction.add(point);
  }
  construction.add(
    FivePointConic(
      id: 'conic',
      points: points,
      attributes: const ObjectAttributes(name: 'K', colorArgb: 0xFF2277BB),
    ),
  );

  // The metric conics (Phase 120b). A parabola, so the stored
  // eccentricity is the one a round-trip must carry exactly; and both
  // bifocal branches over the same three points, so the `difference`
  // flag is the only thing telling them apart.
  final focus = FreePoint(id: 'focus', position: const Vec2(2, -1));
  final directrix = LineThroughTwoPoints(
    id: 'directrix',
    point1: FreePoint(id: 'd1', position: const Vec2(-4, -3)),
    point2: FreePoint(id: 'd2', position: const Vec2(-4, 5)),
  );
  final f1 = FreePoint(id: 'f1', position: const Vec2(-3, 0));
  final f2 = FreePoint(id: 'f2', position: const Vec2(3, 0));
  final on = FreePoint(id: 'on', position: const Vec2(1, 4));
  construction
    ..add(focus)
    ..add(directrix.point1)
    ..add(directrix.point2)
    ..add(directrix)
    ..add(
      FocalConic(
        id: 'parabola',
        focus: focus,
        directrix: directrix,
        eccentricity: 1,
        attributes: const ObjectAttributes(name: 'P', strokeWidth: 2),
      ),
    )
    ..add(
      FocalConic(
        id: 'focal',
        focus: focus,
        directrix: directrix,
        eccentricity: 0.5,
      ),
    )
    ..add(f1)
    ..add(f2)
    ..add(on)
    ..add(
      BifocalConic(
        id: 'ellipse',
        focus1: f1,
        focus2: f2,
        point: on,
        difference: false,
      ),
    )
    ..add(
      BifocalConic(
        id: 'hyperbola',
        focus1: f1,
        focus2: f2,
        point: on,
        difference: true,
        attributes: const ObjectAttributes(dashPeriod: 6),
      ),
    );

  // The constant-stating carriers (Phase 182). Values chosen so the
  // exactness pin bites: 1/3 is not a binary double, so a codec that
  // rounded through one would fail the params test.
  final anchorA = FreePoint(id: 'csa', position: const Vec2(6, 0));
  final anchorB = FreePoint(id: 'csb', position: const Vec2(8, 0));
  final anchorC = FreePoint(id: 'csc', position: const Vec2(6, 3));
  final baseline = LineThroughTwoPoints(
    id: 'cline',
    point1: anchorA,
    point2: anchorB,
  );
  construction
    ..add(anchorA)
    ..add(anchorB)
    ..add(anchorC)
    ..add(baseline)
    ..add(
      FixedAngleLine(
        id: 'fal',
        through: anchorC,
        reference: baseline,
        turn: Rational.fromInts(1, 3),
      ),
    )
    ..add(
      StatedRadiusCircle(
        id: 'src',
        center: anchorA,
        radius: Rational.fromInts(5, 3),
      ),
    )
    ..add(
      ScaledCompassCircle(
        id: 'scc',
        center: anchorC,
        radiusPoint1: anchorA,
        radiusPoint2: anchorB,
        factor: Rational.fromInts(2, 3),
      ),
    )
    ..add(
      RatioApolloniusCircle(
        id: 'rac',
        point1: anchorA,
        point2: anchorB,
        ratio: Rational.fromInts(1, 3),
      ),
    );
  return construction;
}

/// The current geometry of [object], by kind — what a round-trip must
/// reproduce exactly (same parent doubles → same recompute output).
Object? geometryOf(GeoObject object) => switch (object) {
  GeoPoint(:final position) => position,
  GeoLine(:final line) => line,
  // A conic-valued kind has no circle projection; its value is the matrix,
  // so that is what a round-trip must reproduce.
  GeoCircle(:final circle) => circle ?? object.conic,
  GeoAngle(:final angle) => angle,
  GeoPolygon(:final polygonVertices) => polygonVertices,
  GeoMeasurement(:final value, :final anchor) => (value, anchor),
  GeoLocus(:final samples) => samples,
  GeoText(:final renderedText, :final anchor) => (renderedText, anchor),
};
