import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/command_stack_provider.dart';
import '../../application/providers/construction_provider.dart';
import '../../domain/commands/set_geometry_command.dart';
import '../../domain/construction/document_kernel.dart';
import '../../domain/construction/geometry_change.dart';

/// The document's geometry, as a menu (Phase 126).
///
/// Three phases of M-CK are reachable only from tests; this is the door.
/// The switch goes through `SetGeometryCommand` rather than a provider
/// toggle, and that is not a stylistic choice: changing the absolute
/// recomputes every derived object *and* re-addresses every intersection
/// point, so it is an edit to the construction and belongs in the undo
/// history with the rest of them.
class GeometryMenu extends ConsumerWidget {
  const GeometryMenu({super.key});

  /// What each geometry is, in one line each — the menu is where a user
  /// who has never met a Cayley-Klein absolute first meets one.
  static const Map<FundamentalConic, (String, String)> _labels = {
    FundamentalConic.euclidean: (
      'Euclidean',
      'The ordinary plane. Parallels never meet; a triangle sums to 180°.',
    ),
    FundamentalConic.hyperbolic: (
      'Hyperbolic',
      'Inside the unit disc. Many parallels through a point; triangles sum '
          'to less than 180°.',
    ),
    FundamentalConic.elliptic: (
      'Elliptic',
      'No parallels at all; triangles sum to more than 180°. No boundary — '
          'the whole plane is the space.',
    ),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final construction = ref.watch(constructionProvider).construction;
    final current = construction.kernel.metric;
    return PopupMenuButton<VoidCallback>(
      tooltip: 'Geometry: Euclidean, hyperbolic or elliptic',
      popUpAnimationStyle: AnimationStyle.noAnimation,
      icon: const Icon(Icons.public),
      onSelected: (action) => action(),
      itemBuilder: (context) => [
        for (final metric in FundamentalConic.values)
          CheckedPopupMenuItem(
            checked: metric == current,
            value: () => _switchTo(context, ref, metric),
            child: _GeometryRow(
              title: _labels[metric]!.$1,
              subtitle: _labels[metric]!.$2,
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: () => showGeometryGuide(context),
          child: const _GeometryRow(
            title: 'What can I do with this?…',
            subtitle: 'Four things to build that look different in each.',
          ),
        ),
      ],
    );
  }

  void _switchTo(BuildContext context, WidgetRef ref, FundamentalConic metric) {
    final construction = ref.read(constructionProvider).construction;
    if (construction.kernel.metric == metric) {
      return;
    }
    final command = SetGeometryCommand(DocumentKernel(metric: metric));
    ref.read(commandStackProvider.notifier).execute(command);
    final change = command.change;
    if (change != null && change.hasReport && context.mounted) {
      _report(context, change);
    }
  }

  /// Tells the user what the switch had to do to their intersection
  /// points, because it is not visible and it is not nothing: a crossing
  /// that keeps its position has quietly changed address, and one that
  /// could not be matched may now name a different crossing entirely.
  ///
  /// The same obligation the decoder's `repairedIntersections` carries and
  /// still has not discharged — a silent repair is how the Phase 120c
  /// document accumulated points nobody could account for.
  void _report(BuildContext context, GeometryChange change) {
    final parts = <String>[
      if (change.readdressed.isNotEmpty)
        '${change.readdressed.length} intersection '
            '${_plural(change.readdressed.length)} kept '
            '${change.readdressed.length == 1 ? 'its' : 'their'} crossing '
            'under a new branch number',
      if (change.unmatched.isNotEmpty)
        '${change.unmatched.length} had no crossing to match on and may now '
            'sit on a different branch',
    ];
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${_labels[change.to.metric]!.$1} geometry: ${parts.join('; ')}.',
        ),
        duration: const Duration(seconds: 6),
      ),
    );
  }

  static String _plural(int n) => n == 1 ? 'point' : 'points';
}

/// The mini-tutorial: what to *build* to see that the geometry changed.
///
/// Asked for directly — "I don't know how to use these alternative
/// geometries in Cinderella either". The answer that generalizes is that
/// nothing in the toolbar changes; what changes is which theorems hold, so
/// the way to see it is to build a figure whose Euclidean behaviour you
/// already expect and watch it stop.
Future<void> showGeometryGuide(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('Trying the other geometries'),
    content: const SizedBox(
      width: 460,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Switch with the globe button. Nothing in the toolbar changes '
              '— the same tools build the same kinds of object. What changes '
              'is which theorems are true.\n\n'
              'In hyperbolic geometry the plane is the inside of the drawn '
              'circle (the absolute). Build near the centre and drag '
              'outwards: the figure is ordinary in the middle and gets '
              'strange near the edge, which is where hyperbolic space '
              'differs most from flat space. Points outside the circle are '
              'not in the plane at all.',
            ),
            SizedBox(height: 16),
            _Experiment(
              'Triangle angle sum',
              'Three free points, the three segments, then the angle tool on '
                  'each corner. Euclidean: 180°, always. Hyperbolic: less '
                  'than 180°, and it shrinks as you drag the corners apart. '
                  'Elliptic: more than 180°. The defect is the triangle’s '
                  'area — that is a theorem, not a coincidence.',
            ),
            _Experiment(
              'The parallel postulate',
              'A line through two points, a third point off it, and the '
                  'perpendicular tools to drop and raise a perpendicular. In '
                  'Euclidean geometry that gives you the one parallel. In '
                  'hyperbolic geometry it gives you one of infinitely many '
                  'lines through the point that never meet the first.',
            ),
            _Experiment(
              'Incidence does not move',
              'Build any figure out of points, lines through them and their '
                  'intersections, then switch. Nothing moves at all. '
                  'Incidence is projective, so it is the same in every '
                  'geometry — Pappus and Desargues hold everywhere.',
            ),
            _Experiment(
              'A circle with a centre that looks wrong',
              'Compass circle from a centre and a rim point, near the edge '
                  'of the disc. It is still a perfect set of points at equal '
                  'distance from the centre — but drawn on this page the '
                  'centre sits off to one side, because distance near the '
                  'boundary is much larger than it looks.',
            ),
            SizedBox(height: 12),
            Text(
              'Some tools have no meaning in a non-Euclidean plane and go '
              'quiet: parallels through a point, translations, scaling, and '
              'anything measuring area or slope. A similarity that is not a '
              'congruence does not exist here — that is Wallis’ theorem, '
              'and it is equivalent to the parallel postulate.',
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Close'),
      ),
    ],
  ),
);

class _Experiment extends StatelessWidget {
  const _Experiment(this.title, this.body);

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleSmall),
          const SizedBox(height: 2),
          Text(body, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _GeometryRow extends StatelessWidget {
  const _GeometryRow({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 300,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
