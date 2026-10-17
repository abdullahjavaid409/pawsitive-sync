import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pawsitive_sync/core/constants/pet_limits.dart';
import 'package:pawsitive_sync/core/widgets/paws_widgets.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:pawsitive_sync/domain/pet_conditions.dart';
import 'package:pawsitive_sync/core/widgets/system_menu.dart';

/// Species chips used on add- and edit-pet screens.
class PetSpeciesPicker extends StatelessWidget {
  const PetSpeciesPicker({
    super.key,
    required this.species,
    required this.onChanged,
  });

  /// Null until picked (Add pet); Edit profile passes the saved one.
  final Species? species;
  final ValueChanged<Species> onChanged;

  // v14 ChoiceChips: one row of equal pills, ink when selected.
  @override
  Widget build(BuildContext context) => ChoicePills<Species>(
    label: 'Species',
    options: Species.values,
    value: species,
    labelOf: (value) => switch (value) {
      Species.cat => 'Cat',
      Species.dog => 'Dog',
      Species.rabbit => 'Rabbit',
      Species.other => 'Other',
    },
    onChanged: onChanged,
  );
}

/// Optional age and weight row for pet forms.
class PetAgeWeightFields extends StatelessWidget {
  const PetAgeWeightFields({
    super.key,
    required this.age,
    required this.weight,
  });

  final TextEditingController age;
  final TextEditingController weight;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            contextMenuBuilder: appContextMenuBuilder,
            controller: age,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(2),
            ],
            decoration: const InputDecoration(
              labelText: 'Age (optional)',
              suffixText: 'yrs',
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            contextMenuBuilder: appContextMenuBuilder,
            controller: weight,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              LengthLimitingTextInputFormatter(5),
            ],
            decoration: const InputDecoration(
              labelText: 'Weight (optional)',
              suffixText: 'kg',
            ),
          ),
        ),
      ],
    );
  }
}

/// Condition checklist reused from onboarding.
class PetConditionsPicker extends StatelessWidget {
  const PetConditionsPicker({
    super.key,
    required this.petName,
    required this.selected,
    required this.onToggle,
  });

  final String petName;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final name = petName.trim().isEmpty ? 'your pet' : petName.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Same label style as the fields above (v14 FieldLabel).
        FieldLabel('What is $name being treated for? Pick any'),
        const SizedBox(height: 4),
        for (final option in PetConditions.options) ...[
          SelectableOption(
            title: option.$1,
            subtitle: option.$2,
            selected: selected.contains(option.$1),
            minHeight: 64,
            onPressed: () => onToggle(option.$1),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

/// Validates pet form input before save.
abstract final class PetFormValidation {
  static String? nameError(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return "Add your pet’s name.";
    if (trimmed.length > PetLimits.maxNameLength) {
      return 'Name is too long.';
    }
    return null;
  }

  static String? weightError(String raw) {
    if (PetLimits.isValidWeight(raw)) return null;
    return 'Use a weight like 4.5';
  }

  /// Blank is fine (age is optional). The repository clamps to
  /// [PetLimits.maxAgeYears]; telling the person first beats a silent change.
  static String? ageError(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final age = int.tryParse(trimmed);
    if (age == null || age < 0) return 'Use a whole number of years.';
    if (age > PetLimits.maxAgeYears) {
      return 'Age must be ${PetLimits.maxAgeYears} years or less.';
    }
    return null;
  }
}
