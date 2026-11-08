import 'package:flutter/material.dart';

import '../data/models.dart';
import 'format.dart';

/// Male/Female, and a year of birth. Both can be left blank.
class GenderYearFields extends StatelessWidget {
  const GenderYearFields({
    super.key,
    required this.gender,
    required this.onGenderChanged,
    required this.birthYear,
    this.helperText,
  });

  final String? gender;
  final ValueChanged<String?> onGenderChanged;
  final TextEditingController birthYear;
  final String? helperText;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final e in Options.gender.entries)
                ChoiceChip(
                  label: Text(e.value),
                  selected: gender == e.key,
                  // Tapping the chosen one clears it.
                  onSelected: (on) => onGenderChanged(on ? e.key : null),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: birthYear,
            keyboardType: TextInputType.number,
            maxLength: 4,
            decoration: InputDecoration(
              labelText: 'Year of birth',
              prefixIcon: const Icon(Icons.cake),
              helperText: helperText,
              counterText: '',
            ),
            validator: birthYearError,
          ),
        ],
      );
}
