import 'package:flutter/material.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/domain/models.dart';

/// What a medicine physically is (Magic Patterns v14 FormPicker). Only used
/// while adding one: it picks the unit, and the saved amount ("2 units",
/// "1 drop") carries it from then on, so no new field is stored or synced.
enum MedicineForm {
  tablet('Tablet', ['tablet', 'mg'], ['0.25', '0.5', '1', '2'], {'tablet': 4}),
  capsule('Capsule', ['capsule', 'mg'], ['1', '2'], {
    'capsule': 4,
  }, wholeOnly: true),
  liquid('Liquid', ['ml', 'mg'], ['0.5', '1', '2.5', '5'], {'ml': 20}),
  injection('Injection', ['units', 'ml'], [], {'units': 40, 'ml': 5}),
  drops('Drops', ['drop'], ['1', '2', '3'], {'drop': 6}, wholeOnly: true),
  topical('Topical', ['application'], ['1'], {}, wholeOnly: true),
  chew('Chew', ['chew', 'mg'], ['0.5', '1'], {'chew': 3}),
  other('Other', [], [], {});

  const MedicineForm(
    this.label,
    this.units,
    this.quick,
    this.highAt, {
    this.wholeOnly = false,
  });

  final String label;

  /// First is the default (the form's own count); "mg" is offered too where
  /// vets dose by strength. Empty for [other]: the person types one.
  final List<String> units;

  /// Common amounts of the first unit, offered as one-tap chips.
  final List<String> quick;

  /// Above this per unit, the amount step asks to double-check the label.
  final Map<String, double> highAt;

  /// Capsules, drops and applications can't be split (counted in the
  /// form's own unit; a strength in mg can be any number).
  final bool wholeOnly;

  /// Where it's given, for forms that need it (v14 DoseFields "Where").
  List<String> get sites => switch (this) {
    MedicineForm.drops => const ['Left eye', 'Right eye', 'Both eyes', 'Ears'],
    MedicineForm.topical => const ['Skin', 'Ears', 'Paws'],
    _ => const [],
  };

  /// Best guess from a saved amount ("2 units" → injection), for icons.
  static MedicineForm fromAmount(String amount) {
    final a = amount.toLowerCase();
    if (a.contains('unit')) return MedicineForm.injection;
    if (RegExp(r'\bmg\b').hasMatch(a)) return MedicineForm.tablet;
    if (a.contains('drop')) return MedicineForm.drops;
    if (RegExp(r'\bml\b').hasMatch(a)) return MedicineForm.liquid;
    if (a.contains('capsule')) return MedicineForm.capsule;
    if (a.contains('chew')) return MedicineForm.chew;
    if (a.contains('application')) return MedicineForm.topical;
    return MedicineForm.tablet;
  }
}

/// A well-known vet medicine offered on the name step. Convenience only:
/// the screen says to follow the vet's instructions.
class CommonMedicine {
  const CommonMedicine(this.name, this.form, this.use, this.species);

  final String name;
  final MedicineForm form;
  final String use;
  final Set<Species> species;

  static const all = [
    CommonMedicine('Insulin', MedicineForm.injection, 'Diabetes', {
      Species.cat,
      Species.dog,
    }),
    CommonMedicine('Methimazole', MedicineForm.tablet, 'Thyroid', {
      Species.cat,
    }),
    CommonMedicine('Apoquel', MedicineForm.tablet, 'Itching & allergies', {
      Species.dog,
    }),
    CommonMedicine('Carprofen', MedicineForm.chew, 'Pain & joints', {
      Species.dog,
    }),
    CommonMedicine('Gabapentin', MedicineForm.capsule, 'Pain & calming', {
      Species.cat,
      Species.dog,
    }),
    CommonMedicine('Prednisolone', MedicineForm.liquid, 'Inflammation', {
      Species.cat,
      Species.dog,
    }),
    CommonMedicine('Amoxicillin', MedicineForm.liquid, 'Infections', {
      Species.cat,
      Species.dog,
    }),
    CommonMedicine('Ofloxacin', MedicineForm.drops, 'Eye infections', {
      Species.cat,
      Species.dog,
    }),
    CommonMedicine('Revolution Plus', MedicineForm.topical, 'Flea & worm', {
      Species.cat,
    }),
    CommonMedicine('Simparica Trio', MedicineForm.chew, 'Flea, tick & worm', {
      Species.dog,
    }),
  ];

  /// With no query: the ones common for this species (all of them for
  /// rabbits and other pets). With a query: matches on name or use.
  static List<CommonMedicine> suggestionsFor(Species species, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      if (species == Species.cat || species == Species.dog) {
        return [
          for (final m in all)
            if (m.species.contains(species)) m,
        ];
      }
      return all;
    }
    return [
      for (final m in all)
        if (m.name.toLowerCase().contains(q) || m.use.toLowerCase().contains(q))
          m,
    ];
  }
}

const _fractions = {'0.25': '¼', '0.50': '½', '0.75': '¾'};

/// 0.5 → "½", 1.5 → "1½", 2.5 → "2½" (kept as decimals beyond quarters).
String formatAmount(double value) {
  final whole = value.floor();
  final frac = _fractions[(value - whole).toStringAsFixed(2)];
  if (frac != null) return whole == 0 ? frac : '$whole$frac';
  final fixed = value.toStringAsFixed(2);
  return fixed.replaceFirst(RegExp(r'\.?0+$'), '');
}

/// "tablet" → "tablets" above one; ml and plural units stay as they are.
String unitWord(double amount, String unit) {
  if (unit == 'units') return amount == 1 ? 'unit' : 'units';
  if (unit.isEmpty || unit == 'ml' || unit == 'mg' || unit.endsWith('s')) {
    return unit;
  }
  return amount > 1 ? '${unit}s' : unit;
}

/// "2 units", "½ tablet", "1 drop".
String formatDose(double amount, String unit) =>
    '${formatAmount(amount)} ${unitWord(amount, unit)}'.trim();

/// The form's photo on a cream tile (v14 `formImages`, bundled so the app
/// stays offline). The photos sit on cream, so light mode multiplies them
/// into the card for a seamless tile, as the prototype does.
class MedicineFormIcon extends StatelessWidget {
  const MedicineFormIcon({super.key, required this.form, this.size = 44});

  final MedicineForm form;
  final double size;

  /// `assets/medicine/<form>.jpg`, 192 px, about 7 KB each.
  static String assetFor(MedicineForm form) =>
      'assets/medicine/${form.name}.jpg';

  @override
  Widget build(BuildContext context) {
    final paws = context.paws;
    final light = Theme.of(context).brightness == Brightness.light;
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.27),
        child: Image.asset(
          assetFor(form),
          width: size,
          height: size,
          fit: BoxFit.cover,
          cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
          color: light ? paws.surfaces.card : null,
          colorBlendMode: light ? BlendMode.multiply : null,
          // A missing asset must never break a dose row.
          errorBuilder: (_, _, _) => SizedBox.square(
            dimension: size,
            child: ColoredBox(color: paws.surfaces.subtle),
          ),
        ),
      ),
    );
  }
}

/// One tap of − / + on an amount: halves for tablets and chews, whole
/// counts for what can't be split, and sensible steps for ml.
double amountStep(MedicineForm form, String unit) {
  if (unit == 'mg' || unit == 'units') return 1;
  if (unit == 'ml') return form == MedicineForm.injection ? 0.1 : 0.5;
  if (form == MedicineForm.tablet || form == MedicineForm.chew) return 0.5;
  return 1;
}
