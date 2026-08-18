import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regula/application/persistence/construction_codec.dart';
import 'package:regula/application/providers/viewport_provider.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/document_kernel.dart';
import 'package:regula/domain/construction/geometry_change.dart';
import 'package:regula/presentation/panels/intersection_report.dart';

/// Phase 126e: the two silent re-addressing events say the same kind of
/// thing, in the same place.
///
/// These are string tests, which is unusual and deliberate: the sentence
/// *is* the feature. Everything else about both events is already pinned
/// — `geometry_switch_test` proves the switch re-points correctly and
/// `construction_codec_test` proves the reader separates duplicates — and
/// what was missing for the whole of M-CK was that either one told the
/// user. A report that is built but never phrased, or phrased but never
/// shown, is the Phase 126b failure mode with a different subject.
void main() {
  const euclidean = DocumentKernel();
  const hyperbolic = DocumentKernel(metric: FundamentalConic.hyperbolic);

  DecodedDocument decoded({
    List<String> repaired = const [],
    List<String> unrepaired = const [],
  }) => DecodedDocument(
    construction: Construction(),
    viewport: const ViewportState(),
    repairedIntersections: repaired,
    unrepairedIntersections: unrepaired,
  );

  group('the geometry switch', () {
    test('says nothing when nothing was re-addressed', () {
      // The usual answer, and correct: most of a document is real
      // transverse crossings that keep their indices in every geometry.
      // An unconditional "your points may have moved" is noise, and it
      // trains the user to dismiss the one time it matters.
      expect(
        geometryChangeMessage(
          const GeometryChange(from: euclidean, to: hyperbolic),
          geometry: 'Hyperbolic',
        ),
        isNull,
      );
    });

    test('names the geometry and counts what moved', () {
      final message = geometryChangeMessage(
        const GeometryChange(
          from: euclidean,
          to: hyperbolic,
          readdressed: [(id: 'x', from: 0, to: 1)],
        ),
        geometry: 'Hyperbolic',
      );
      expect(
        message,
        'Hyperbolic geometry: 1 intersection point kept its crossing '
        'under a new branch number.',
      );
    });

    test('the unmatched remainder is reported, not hidden', () {
      // A point with no crossing to match on either side of the switch is
      // not repairable — there is no evidence of what the user meant — so
      // the honest move is to say its address may now name something else.
      final message = geometryChangeMessage(
        const GeometryChange(
          from: euclidean,
          to: hyperbolic,
          readdressed: [(id: 'x', from: 0, to: 1), (id: 'y', from: 1, to: 0)],
          unmatched: ['z'],
        ),
        geometry: 'Hyperbolic',
      );
      expect(
        message,
        'Hyperbolic geometry: 2 intersection points kept their crossing '
        'under a new branch number; 1 had no crossing to match on and may '
        'now sit on a different branch.',
      );
    });

    test('an object that has no value in the new geometry names the fix', () {
      // Different news from the other two, and worse: those points are
      // still there under a new number, while these have gone blank and
      // no repair exists — a switch reinterprets a construction, it does
      // not re-author one.
      expect(
        geometryChangeMessage(
          const GeometryChange(
            from: euclidean,
            to: hyperbolic,
            undefined: ['p'],
          ),
          geometry: 'Hyperbolic',
        ),
        'Hyperbolic geometry: 1 object has no value here and is no longer '
        'drawn — switch back to restore it.',
      );
      expect(
        geometryChangeMessage(
          const GeometryChange(
            from: euclidean,
            to: hyperbolic,
            readdressed: [(id: 'x', from: 0, to: 1)],
            undefined: ['p', 'q', 'r'],
          ),
          geometry: 'Hyperbolic',
        ),
        'Hyperbolic geometry: 1 intersection point kept its crossing under '
        'a new branch number; 3 objects have no value here and are no '
        'longer drawn — switch back to restore them.',
      );
    });
  });

  group('the decoder repair', () {
    test('a well-formed document says nothing at all', () {
      expect(decodeRepairMessage(decoded()), isNull);
    });

    test('a repaired duplicate is announced, because something moved', () {
      expect(
        decodeRepairMessage(decoded(repaired: ['p2'])),
        'Opened with a repair: 1 intersection point was stacked on a '
        'crossing another point already held, and moved to a free one.',
      );
    });

    test('an unrepairable duplicate names the only remaining fix', () {
      // The half that matters more. A repaired point is a defect the
      // reader fixed; an unrepaired one is still there, and no drag can
      // separate it — the pair has no crossing left to give it.
      expect(
        decodeRepairMessage(decoded(unrepaired: ['p3'])),
        'Opened with a repair: 1 had no free crossing to move to and is '
        'still stacked — deleting the surplus point is the only fix.',
      );
    });

    test('both halves, plural', () {
      expect(
        decodeRepairMessage(
          decoded(repaired: ['p2', 'p3'], unrepaired: ['p4', 'p5']),
        ),
        'Opened with a repair: 2 intersection points were stacked on a '
        'crossing another point already held, and moved to a free one; '
        '2 had no free crossing to move to and are still stacked — '
        'deleting the surplus points is the only fix.',
      );
    });
  });

  testWidgets('the message reaches the screen', (tester) async {
    // The whole obligation is that a user reads this. `hasReport` was
    // true and correctly computed for three phases while nothing showed
    // it, which is exactly the shape of the Phase 126b defects.
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (inner) {
              context = inner;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    showIntersectionReport(context, 'Opened with a repair: something.');
    await tester.pump();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('Opened with a repair: something.'), findsOneWidget);
  });
}
