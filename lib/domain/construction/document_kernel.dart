import '../projective/absolute.dart';

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
  const DocumentKernel({this.metric = FundamentalConic.euclidean});

  final FundamentalConic metric;

  /// The absolute this kernel names — the value the metric kernels read.
  Absolute get absolute => Absolute.of(metric);

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
