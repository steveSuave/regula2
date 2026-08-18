import 'dart:math' as math;

import '../projective/absolute.dart';
import 'geo_object.dart';

export '../projective/absolute.dart' show FundamentalConic;

/// Per-document kernel settings: the geometry the document is drawn in.
///
/// Carried through decode and encode as a unit so M-CK adds fields here
/// rather than reopening the schema. A document whose kernel is anything
/// but the default requires format version 2 — see
/// `construction_codec.dart`'s version rule.
///
/// This lives in the domain layer because [Construction] holds one: the
/// absolute is an input to every metric recompute, not a presentation
/// setting (PLAN §"The threading decision"). The save format is where it
/// is *written*, not where it belongs.
class DocumentKernel {
  const DocumentKernel({
    this.metric = FundamentalConic.euclidean,
    this.radius = 1,
  }) : assert(radius > 0, 'the absolute has a positive radius or none');

  final FundamentalConic metric;

  /// The chart radius of the proper absolute (Phase 131), 1 by default
  /// and always 1 under [FundamentalConic.euclidean], whose absolute has
  /// no scale.
  ///
  /// **A chart quantity, not a geometric one** — see [Absolute.scaled].
  /// The plane of radius R is the unit plane drawn R times larger, with
  /// the same distances and angles between corresponding points, which is
  /// why setting it is safe and why it is what makes switching an
  /// existing figure meaningful: a construction at world coordinates of
  /// tens or hundreds lands *inside* the plane rather than outside it,
  /// with no point moved.
  final double radius;

  /// The absolute this kernel names — the value the metric kernels read.
  Absolute get absolute => Absolute.of(
    metric,
    radius: metric == FundamentalConic.euclidean ? 1 : radius,
  );

  /// Whether this is the geometry every pre-M-CK document is in. The
  /// version rule and the encoder both key off this: a default kernel is
  /// not written to the file at all, so ordinary documents stay v1.
  ///
  /// [radius] does not enter, because a Euclidean absolute has no scale
  /// to differ in — a Euclidean kernel with a stray radius is still the
  /// default one, and [absolute] answers the unit instance for it.
  bool get isDefault => metric == FundamentalConic.euclidean;

  /// Whether the radius is the canonical one — what keeps a hyperbolic or
  /// elliptic document at format version 2 rather than 3.
  bool get isUnitRadius => isDefault || radius == 1;

  /// This kernel with [radius] instead — the switch's route to framing a
  /// figure that was drawn at a Euclidean scale.
  DocumentKernel withRadius(double radius) =>
      DocumentKernel(metric: metric, radius: radius);

  @override
  bool operator ==(Object other) =>
      other is DocumentKernel &&
      other.metric == metric &&
      (isDefault || other.radius == radius);

  @override
  int get hashCode => Object.hash(metric, isDefault ? 1 : radius);

  @override
  String toString() => isUnitRadius
      ? 'DocumentKernel(metric: ${metric.name})'
      : 'DocumentKernel(metric: ${metric.name}, radius: $radius)';
}

/// An absolute radius whose disc comfortably contains every real finite
/// point of [objects] — what entering a proper geometry should size its
/// plane to (Phase 131).
///
/// Never below 1, so a document with nothing in it, or nothing off the
/// origin, gets the canonical plane rather than a degenerate one.
///
/// [margin] is how much room the figure is given: at the default 2 it
/// occupies the inner half of the disc, which is far enough from the
/// boundary that the construction is comfortably *in* the plane and near
/// enough that the geometry is visibly not flat. Framing tighter would
/// make every point extreme; framing looser would make the whole figure
/// look Euclidean, which is the mode being invisible in a new way.
///
/// Points only. A line has no bounded extent, and a conic that has one
/// is bounded by points of the construction in every case a macro
/// builds — the radius is a rough framing decision, not a bounding box.
double absoluteRadiusContaining(
  Iterable<GeoObject> objects, {
  double margin = 2,
}) {
  var reach = 0.0;
  for (final object in objects) {
    if (object is! GeoPoint) {
      continue;
    }
    final position = object.position;
    if (position == null || !position.norm.isFinite) {
      continue;
    }
    reach = math.max(reach, position.norm);
  }
  return math.max(1, reach * margin);
}
