// Phase 122: where a chain solve actually goes.
//
// The unit that matters in this engine is the *chain solve* — one recompute
// of the affected subgraph (PLAN §"The engine says what it costs"). A drag
// frame is hundreds of them and a locus sweep is hundreds more, so anything
// worth optimizing has to be visible here. This breaks one down.
//
// The reason it exists is that Phase 122 was planned as "the tracing inner
// loop onto SoA `Float64List`", and the first measurement said that path is
// ~1.4% of a traced recompute while `intersectionCandidates` is the rest.
// Re-run this before spending anything on representation: the split, not the
// prior, is what should decide.
//
// Run on VM (`dart run`), AOT, dart2js and dart2wasm via
// `benchmark/run_chain_solve.sh`. Keep this file Flutter-free (domain
// imports only) or the js/wasm targets break.
//
// ignore_for_file: avoid_print

import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/fixed_radius_circle.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/intersection_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/proj_point.dart';

/// Nanoseconds per call, after a warmup of a tenth of the run.
double nanos(int reps, void Function() body) {
  for (var i = 0; i < reps ~/ 10; i++) {
    body();
  }
  final watch = Stopwatch()..start();
  for (var i = 0; i < reps; i++) {
    body();
  }
  watch.stop();
  return watch.elapsedMicroseconds * 1000 / reps;
}

void main(List<String> args) {
  final scale = args.isEmpty ? 1 : int.parse(args.first);
  final reps = 200000 * scale;

  final construction = Construction();
  final a = FreePoint(id: 'a', position: const Vec2(0, 0));
  final b = FreePoint(id: 'b', position: const Vec2(3, 1));
  final circleA = FixedRadiusCircle(id: 'ka', center: a, radius: 2.5);
  final circleB = FixedRadiusCircle(id: 'kb', center: b, radius: 2.0);
  final line = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
  final onCircles = IntersectionPoint(
    id: 'p',
    curve1: circleA,
    curve2: circleB,
    branchIndex: 0,
  );
  final onLine = IntersectionPoint(
    id: 'q',
    curve1: line,
    curve2: circleA,
    branchIndex: 0,
  );
  construction
    ..add(a)
    ..add(b)
    ..add(circleA)
    ..add(circleB)
    ..add(line)
    ..add(onCircles)
    ..add(onLine);

  final circleCandidates = intersectionCandidates(circleA, circleB);
  final lineCandidates = intersectionCandidates(line, circleA);

  // The kernel solve: the two shapes every document is mostly made of.
  final tCircles = nanos(reps, () => intersectionCandidates(circleA, circleB));
  final tLine = nanos(reps, () => intersectionCandidates(line, circleA));

  // The tracing slot: nearest-root match plus the step controller's
  // bookkeeping, per seeded branch per substep.
  onCircles.tracedBranch.seed(
    circleCandidates.first,
    candidates: circleCandidates,
  );
  onLine.tracedBranch.seed(lineCandidates.first, candidates: lineCandidates);
  final tFollowCircles = nanos(
    reps,
    () => onCircles.tracedBranch.follow(circleCandidates),
  );
  final tFollowLine = nanos(
    reps,
    () => onLine.tracedBranch.follow(lineCandidates),
  );
  final checkpoint = onCircles.tracedBranch.checkpoint();
  final tCheckpoint = nanos(reps, onCircles.tracedBranch.checkpoint);
  final tRestore = nanos(
    reps,
    () => onCircles.tracedBranch.restore(checkpoint),
  );

  // The whole recompute, traced and static, for the shares below.
  final tTraced = nanos(reps, onCircles.recompute);
  onCircles.tracedBranch.clear();
  final tStatic = nanos(reps, onCircles.recompute);

  String ns(double v) => '${v.toStringAsFixed(0).padLeft(6)} ns';
  String pct(double part, double whole) =>
      '${(100 * part / whole).toStringAsFixed(1).padLeft(5)}%';

  print('one chain solve, broken down (per call):');
  print('  intersectionCandidates  circle∩circle   ${ns(tCircles)}');
  print('  intersectionCandidates  line∩circle     ${ns(tLine)}');
  print('  TracedBranch.follow     circle∩circle   ${ns(tFollowCircles)}');
  print('  TracedBranch.follow     line∩circle     ${ns(tFollowLine)}');
  print('  TracedBranch.checkpoint                 ${ns(tCheckpoint)}');
  print('  TracedBranch.restore                    ${ns(tRestore)}');
  print('  IntersectionPoint.recompute  traced     ${ns(tTraced)}');
  print('  IntersectionPoint.recompute  static     ${ns(tStatic)}');
  print('');
  print('shares of a traced circle∩circle recompute:');
  print('  kernel solve  ${pct(tCircles, tTraced)}');
  print(
    '  tracing slot  ${pct(tFollowCircles + tCheckpoint + tRestore, tTraced)}'
    '   (follow + checkpoint + restore)',
  );
  print('');
  // A guard against the breakdown quietly becoming meaningless.
  final points = <ProjPoint>[...circleCandidates, ...lineCandidates];
  var checksum = 0.0;
  for (final p in points) {
    final v = p.toVec2();
    if (v != null) checksum += v.x + v.y;
  }
  print('checksum ${checksum.toStringAsFixed(6)}');
}
