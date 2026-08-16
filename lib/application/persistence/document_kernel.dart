/// The fundamental conic a document's *measurement* is founded on
/// (PLAN §M-CK). Incidence is projective and needs none of this; distance,
/// angle and perpendicularity are cross-ratios against the conic named
/// here, which is why it is a property of the document rather than of any
/// object in it.
///
/// Only [euclidean] is implemented. The other two are named — not left as
/// free-form strings — because the save format has to *reserve* them: a
/// build that silently read a hyperbolic document as Euclidean would draw
/// the wrong geometry rather than refuse the file, which is precisely what
/// the v2 version stamp exists to prevent.
enum FundamentalConic {
  /// The degenerate conic {I, J} — the circular points at infinity.
  euclidean('euclidean'),

  /// The unit circle: Beltrami–Klein hyperbolic geometry.
  hyperbolic('hyperbolic'),

  /// The imaginary unit conic: elliptic geometry.
  elliptic('elliptic');

  const FundamentalConic(this.name);

  /// The token written to and read from the save format. Kept separate
  /// from the Dart identifier so renaming the latter cannot silently
  /// change the file format.
  final String name;

  static FundamentalConic? byName(String name) {
    for (final value in values) {
      if (value.name == name) {
        return value;
      }
    }
    return null;
  }
}

/// Per-document kernel settings: the geometry the document is drawn in.
///
/// Carried through decode and encode as a unit so M-CK adds fields here
/// rather than reopening the schema. A document whose kernel is anything
/// but the default requires format version 2 — see
/// `construction_codec.dart`'s version rule.
class DocumentKernel {
  const DocumentKernel({this.metric = FundamentalConic.euclidean});

  final FundamentalConic metric;

  /// Whether this is the geometry every pre-M-CK document is in. The
  /// version rule and the encoder both key off this: a default kernel is
  /// not written to the file at all, so ordinary documents stay v1.
  bool get isDefault => metric == FundamentalConic.euclidean;

  @override
  bool operator ==(Object other) =>
      other is DocumentKernel && other.metric == metric;

  @override
  int get hashCode => metric.hashCode;

  @override
  String toString() => 'DocumentKernel(metric: ${metric.name})';
}
