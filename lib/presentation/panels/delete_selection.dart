import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../application/providers/command_stack_provider.dart';
import '../../application/providers/construction_provider.dart';
import '../../domain/commands/delete_objects_command.dart';
import '../../domain/construction/geo_object.dart';
import 'object_kind_label.dart';

/// Asks the user to confirm deleting [ids] when the cascade reaches
/// *beyond* them, listing exactly which unselected objects would go
/// too. Returns true when the deletion may proceed — immediately, with
/// no dialog, when the cascade stays inside [ids] (dependents all
/// included, or none): the user already sees everything that will
/// disappear. Shared by the selection path below and the canvas's
/// tap-delete pre-gate, so both give the same warning.
Future<bool> confirmCascadeDelete(
  BuildContext context,
  WidgetRef ref,
  List<String> ids,
) async {
  final construction = ref.read(constructionProvider).construction;
  final doomed = {
    for (final id in ids) ...construction.transitiveDependentsOf(id),
  }..removeAll(ids);
  if (doomed.isEmpty) {
    return true;
  }
  // Insertion order, like every other listing of objects.
  final casualties = [
    for (final object in construction.objects)
      if (doomed.contains(object.id)) object,
  ];
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      scrollable: true,
      title: const Text('Delete dependent objects too?'),
      content: Text(
        '${casualties.length == 1 ? 'This object depends' : 'These '
                  '${casualties.length} objects depend'} on the selection '
        'and will also be deleted:\n\n'
        '${casualties.map(_displayLabel).join(', ')}',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('confirm-delete'),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return confirmed == true && context.mounted;
}

/// Deletes [objects] as one [DeleteObjectsCommand] (one undo step).
/// Shared by the app-bar delete button, the Del/Backspace shortcut and
/// the Delete tool's activation-on-selection, all through the
/// [confirmCascadeDelete] warning above.
Future<void> deleteSelectionWithConfirmation(
  BuildContext context,
  WidgetRef ref,
  List<GeoObject> objects,
) async {
  final ids = [for (final object in objects) object.id];
  if (!await confirmCascadeDelete(context, ref, ids)) {
    return;
  }
  // The construction can have changed while the dialog was up; an
  // all-gone selection must not put an empty delete on the undo stack.
  final construction = ref.read(constructionProvider).construction;
  if (!ids.any(construction.contains)) {
    return;
  }
  ref.read(commandStackProvider.notifier).execute(DeleteObjectsCommand(ids));
}

String _displayLabel(GeoObject object) => object.attributes.name.isEmpty
    ? objectKindLabel(object)
    : object.attributes.name;
