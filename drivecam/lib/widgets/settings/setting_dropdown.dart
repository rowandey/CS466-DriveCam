// setting_dropdown.dart
// Reusable labeled dropdown widget for settings values.
import 'package:flutter/material.dart';

class SettingDropdown extends StatelessWidget {
  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  const SettingDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  // Builds a labeled dropdown row for a single settings field.
  // [label] is the visible field name, [value] is the selected option,
  // [options] are selectable values, and [onChanged] handles updates.
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyLarge),
          DropdownMenu<String>(
            initialSelection: value,
            // Force a solid menu surface for better dark-mode readability.
            menuStyle: MenuStyle(
              backgroundColor: MaterialStatePropertyAll<Color>(
                colorScheme.surface,
              ),
              surfaceTintColor: MaterialStatePropertyAll<Color>(
                colorScheme.surface,
              ),
            ),
            onSelected: (v) {
              if (v != null) onChanged(v);
            },
            dropdownMenuEntries: options
                .map((o) => DropdownMenuEntry(value: o, label: o))
                .toList(),
          ),
        ],
      ),
    );
  }
}
