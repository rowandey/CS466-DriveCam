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

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyLarge),
          DropdownMenu<String>(
            initialSelection: value,
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
