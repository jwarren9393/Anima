import 'package:flutter/material.dart';

import '../models/character_category.dart';
import '../services/character_category_service.dart';

/// Dropdown to filter characters by category (All + custom lists).
class CharacterCategoryFilterBar extends StatelessWidget {
  const CharacterCategoryFilterBar({
    super.key,
    required this.state,
    required this.selectedCategoryId,
    required this.onChanged,
    this.onManage,
  });

  final CharacterCategoryState state;
  final String selectedCategoryId;
  final ValueChanged<String> onChanged;
  final VoidCallback? onManage;

  @override
  Widget build(BuildContext context) {
    final selected = selectedCategoryId.trim();
    final known = {
      CharacterCategoryService.allFilterId,
      ...state.categories.map((c) => c.id),
    };
    final value = known.contains(selected)
        ? selected
        : CharacterCategoryService.allFilterId;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: value,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Category',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                const DropdownMenuItem(
                  value: CharacterCategoryService.allFilterId,
                  child: Text('All characters'),
                ),
                for (final category in state.categories)
                  DropdownMenuItem(
                    value: category.id,
                    child: Text(category.name),
                  ),
              ],
              onChanged: (next) {
                if (next == null) return;
                onChanged(next);
              },
            ),
          ),
          if (onManage != null) ...[
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Manage categories',
              onPressed: onManage,
              icon: const Icon(Icons.folder_outlined),
            ),
          ],
        ],
      ),
    );
  }
}

/// Checkbox sheet to assign a character to zero or more categories.
Future<Set<String>?> showCharacterCategoryPicker({
  required BuildContext context,
  required CharacterCategoryState state,
  required Set<String> initiallySelected,
  required String characterName,
}) {
  return showModalBottomSheet<Set<String>>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      final selected = Set<String>.from(initiallySelected);
      return StatefulBuilder(
        builder: (context, setModalState) {
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      'Categories for $characterName',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      'A character can belong to several lists. '
                      'All characters always shows everyone.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  if (state.categories.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No categories yet. Use Manage categories to create one.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.sizeOf(context).height * 0.45,
                      ),
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final category in state.categories)
                            CheckboxListTile(
                              value: selected.contains(category.id),
                              title: Text(category.name),
                              onChanged: (on) {
                                setModalState(() {
                                  if (on == true) {
                                    selected.add(category.id);
                                  } else {
                                    selected.remove(category.id);
                                  }
                                });
                              },
                            ),
                        ],
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: FilledButton(
                      onPressed: () => Navigator.pop(
                        context,
                        Set<String>.from(selected),
                      ),
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

/// Create / rename / delete custom category lists.
Future<void> showManageCharacterCategoriesSheet({
  required BuildContext context,
  required CharacterCategoryService categoryService,
  required CharacterCategoryState state,
  required ValueChanged<CharacterCategoryState> onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      var local = state;
      return StatefulBuilder(
        builder: (context, setModalState) {
          Future<void> createCategory() async {
            final name = await _promptCategoryName(
              context,
              title: 'New category',
            );
            if (name == null || name.isEmpty) return;
            local = await categoryService.upsertCategory(
              CharacterCategory(id: CharacterCategory.newId(), name: name),
            );
            onChanged(local);
            setModalState(() {});
          }

          Future<void> renameCategory(CharacterCategory category) async {
            final name = await _promptCategoryName(
              context,
              title: 'Rename category',
              initial: category.name,
            );
            if (name == null || name.isEmpty) return;
            local = await categoryService.upsertCategory(
              category.copyWith(name: name),
            );
            onChanged(local);
            setModalState(() {});
          }

          Future<void> deleteCategory(CharacterCategory category) async {
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Delete category?'),
                content: Text(
                  'Remove “${category.name}”? Characters stay on the device; '
                  'they just leave this list.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Delete'),
                  ),
                ],
              ),
            );
            if (confirmed != true) return;
            local = await categoryService.deleteCategory(category.id);
            onChanged(local);
            setModalState(() {});
          }

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Manage categories',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        IconButton(
                          tooltip: 'New category',
                          onPressed: createCategory,
                          icon: const Icon(Icons.add),
                        ),
                      ],
                    ),
                  ),
                  if (local.categories.isEmpty)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(24, 8, 24, 24),
                      child: Text(
                        'Create lists like “Fantasy world”, “Slice of life”, '
                        'or “Group cast”. The same character can be in several.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.sizeOf(context).height * 0.5,
                      ),
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final category in local.categories)
                            ListTile(
                              title: Text(category.name),
                              trailing: PopupMenuButton<String>(
                                onSelected: (value) {
                                  if (value == 'rename') {
                                    renameCategory(category);
                                  }
                                  if (value == 'delete') {
                                    deleteCategory(category);
                                  }
                                },
                                itemBuilder: (context) => const [
                                  PopupMenuItem(
                                    value: 'rename',
                                    child: Text('Rename'),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Delete'),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

Future<String?> _promptCategoryName(
  BuildContext context, {
  required String title,
  String initial = '',
}) async {
  final controller = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          labelText: 'Name',
          hintText: 'e.g. Fantasy world',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (value) => Navigator.pop(context, value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
  final trimmed = result?.trim() ?? '';
  if (trimmed.isEmpty) return null;
  return trimmed;
}
