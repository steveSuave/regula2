/// What to tell the user when an intersection point's *address* changed
/// without them touching it.
///
/// There are two such events, and until Phase 126e only one of them said
/// anything. Switching the document's geometry re-addresses every
/// crossing, because `branchIndex` names a position in the candidate list
/// *as ordered against the absolute*. Opening a document repairs points
/// the file left stacked on one crossing. Both are invisible by
/// construction — a re-pointed crossing looks exactly like the one the
/// user tapped — and a silent re-addressing is how the Phase 120c
/// document accumulated points nobody could account for.
///
/// So the two share a report, and the message is built by a plain
/// function that takes no [BuildContext]: what it *says* is the part
/// worth testing, and that should not need a widget tree to read.
library;

import 'package:flutter/material.dart';

import '../../application/persistence/construction_codec.dart';
import '../../domain/construction/geometry_change.dart';

/// What the geometry switch did, or null when it did nothing worth
/// saying — which is the usual answer, and deliberately so. Most of a
/// document is real transverse crossings that keep their indices, and an
/// unconditional "your points may have moved" trains the user to dismiss
/// the one time it matters.
String? geometryChangeMessage(
  GeometryChange change, {
  required String geometry,
}) {
  if (!change.hasReport) {
    return null;
  }
  final parts = <String>[
    if (change.readdressed.isNotEmpty)
      '${change.readdressed.length} intersection '
          '${_points(change.readdressed.length)} kept '
          '${change.readdressed.length == 1 ? 'its' : 'their'} crossing '
          'under a new branch number',
    if (change.unmatched.isNotEmpty)
      '${change.unmatched.length} had no crossing to match on and may now '
          'sit on a different branch',
    // Different news from the other two, and worse: those points are
    // still there and merely re-addressed, while these objects have gone
    // blank. Nothing can repair them — the constructions are correct and
    // this geometry has no answer for them — so the message says what to
    // do, which is to switch back.
    if (change.undefined case final gone when gone.isNotEmpty)
      '${gone.length} ${_objects(gone.length)} '
          '${gone.length == 1 ? 'has' : 'have'} no value here and '
          '${gone.length == 1 ? 'is' : 'are'} no longer drawn — switch '
          'back to restore ${gone.length == 1 ? 'it' : 'them'}',
  ];
  return '$geometry geometry: ${parts.join('; ')}.';
}

/// What opening [document] had to repair, or null when it was well-formed
/// — which every document in `test/fixtures/` is, and every document this
/// build writes.
///
/// The two halves are not the same news. A repaired point is a defect the
/// reader *fixed*, and saying so matters only because the fix moved
/// something the user drew. An unrepaired one is a defect that is still
/// there: the curve pair has no crossing left to give it, so it stays
/// stacked on another point for ever, and the only remaining fix is to
/// delete the surplus — which is why that half names the action.
String? decodeRepairMessage(DecodedDocument document) {
  if (!document.hasIntersectionReport) {
    return null;
  }
  final repaired = document.repairedIntersections.length;
  final unrepaired = document.unrepairedIntersections.length;
  final parts = <String>[
    if (repaired > 0)
      '$repaired intersection ${_points(repaired)} '
          '${repaired == 1 ? 'was' : 'were'} stacked on a crossing another '
          'point already held, and moved to a free one',
    if (unrepaired > 0)
      '$unrepaired had no free crossing to move to and '
          '${unrepaired == 1 ? 'is' : 'are'} still stacked — deleting the '
          'surplus ${_points(unrepaired)} is the only fix',
  ];
  return 'Opened with a repair: ${parts.join('; ')}.';
}

/// Both reports land in the same place, so they read as the same kind of
/// news — something happened to your points that you did not do.
void showIntersectionReport(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), duration: const Duration(seconds: 6)),
  );
}

String _points(int n) => n == 1 ? 'point' : 'points';

String _objects(int n) => n == 1 ? 'object' : 'objects';
