import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:regula/application/persistence/construction_codec.dart';
import 'package:regula/domain/construction/geo_object.dart';
import 'package:regula/domain/construction/incidence.dart';
import 'package:regula/domain/tools/intersection_tool.dart';
import 'package:regula/domain/tools/tool.dart';

/// Regression over the user document `inter2.json` (kept verbatim in
/// `test/fixtures/`): segments a = AB and b = AC hang off the shared
/// vertex A, c bisects their wedge. The bisector's only crossing with
/// either parent *is* A — a defining point the parents share, with no
/// `IntersectionPoint` anywhere — so intersecting c with a parent must
/// reuse A (tap refused), not stack a new point on it. The document
/// still carries the stacked D and E from before the fix.
void main() {
  test('bisector of segments off a shared vertex refuses new crossings', () {
    final doc = decodeDocument(
      jsonDecode(File('test/fixtures/inter2.json').readAsStringSync())
          as Map<String, dynamic>,
    );
    final objects = doc.construction.objects.toList();
    final byName = {for (final o in objects) o.attributes.name: o};
    final a = byName['A']! as GeoPoint;
    final segAB = byName['a']!;
    final segAC = byName['b']!;
    final bisector = byName['c']!;

    expect(structurallyIncident(bisector, a), isTrue);

    // Replay the taps that produced the stacked D and E, on the document
    // without them: both must now be refused.
    final clean = objects
        .where((o) => !{'D', 'E'}.contains(o.attributes.name))
        .toList();
    var n = 0;
    final t = IntersectionTool(newId: () => 'n${n++}')
      ..onInput(ToolInput(a.position!, hit: bisector, objects: clean));
    expect(
      t.onInput(ToolInput(a.position!, hit: segAC, objects: clean)),
      isA<ToolIgnored>(),
    );
    expect(
      t.onInput(ToolInput(a.position!, hit: segAB, objects: clean)),
      isA<ToolIgnored>(),
      reason: 'the refused tap keeps the bisector armed for the other parent',
    );
  });
}
