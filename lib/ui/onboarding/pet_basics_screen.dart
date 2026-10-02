import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pawsitive_sync/core/layout/adaptive.dart';
import 'package:pawsitive_sync/core/motion/app_motion.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/paws_widgets.dart';
import 'package:pawsitive_sync/core/widgets/pet_mark.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_view_model.dart';
import 'package:provider/provider.dart';

/// Collects the first pet's name, species, age, and weight.
class PetBasicsScreen extends StatelessWidget {
  const PetBasicsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final model = context.watch<OnboardingViewModel>();
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 24, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        OnboardingHeader(
                          step: 1,
                          onBack: () => context.go(AppRoutes.welcome),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(left: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 24),
                              Text(
                                'Who are we caring for?',
                                style: text.headlineMedium,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Start with one pet. You can add the rest later.',
                                style: text.bodyLarge?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 20),
                              Center(
                                child: SoftEnter(
                                  child: PetMark(
                                    species: model.species,
                                    size: 88,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 20),
                              InkWell(
                                onTap: () => _choosePhoto(context, model),
                                borderRadius: BorderRadius.circular(16),
                                child: Row(
                                  children: [
                                    _PhotoCircle(bytes: model.photoBytes),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            model.photoBytes == null
                                                ? 'Add a photo'
                                                : 'Photo added',
                                            style: text.bodyLarge?.copyWith(
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          Text(
                                            model.photoBytes == null
                                                ? 'Tap here. Take one or choose one.'
                                                : 'Tap here to change it.',
                                            style: text.bodyMedium,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),
                              Text(
                                'Name',
                                style: text.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                initialValue: model.petName,
                                onChanged: model.setName,
                                style: text.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w500,
                                ),
                                textInputAction: TextInputAction.next,
                              ),
                              const SizedBox(height: 24),
                              Text(
                                'Species',
                                style: text.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  for (final species in Species.values) ...[
                                    Expanded(
                                      child: _SpeciesChip(
                                        label: _label(species),
                                        selected: model.species == species,
                                        onPressed: () =>
                                            model.setSpecies(species),
                                      ),
                                    ),
                                    if (species != Species.other)
                                      const SizedBox(width: 8),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 24),
                              Row(
                                children: [
                                  Expanded(
                                    child: _AgeStepper(years: model.ageYears),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: _WeightField(weight: model.weight),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        Padding(
                          padding: const EdgeInsets.only(left: 12),
                          child: FilledButton(
                            onPressed: model.petName.trim().isEmpty
                                ? null
                                : () {
                                    final weight = model.weight.trim();
                                    if (weight.isNotEmpty &&
                                        !RegExp(
                                          r'^\d{1,2}(\.\d{1,2})?$',
                                        ).hasMatch(weight)) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Use a weight like 4.6 kg, or leave it blank.',
                                          ),
                                        ),
                                      );
                                      return;
                                    }
                                    context.go(AppRoutes.conditions);
                                  },
                            child: Text(
                              model.petName.trim().isEmpty
                                  ? 'Add a name to continue'
                                  : 'Continue',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  String _label(Species species) => switch (species) {
    Species.cat => 'Cat',
    Species.dog => 'Dog',
    Species.rabbit => 'Rabbit',
    Species.other => 'Other',
  };
}

class _PhotoCircle extends StatelessWidget {
  const _PhotoCircle({required this.bytes});

  final Uint8List? bytes;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 80,
      height: 80,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: context.paws.neutral,
        shape: BoxShape.circle,
        border: Border.all(color: scheme.outline, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: bytes == null
          ? StrokeIcon(
              StrokeIconKind.camera,
              color: scheme.onSurfaceVariant,
            )
          : Image.memory(
              bytes!,
              width: 80,
              height: 80,
              fit: BoxFit.cover,
            ),
    );
  }
}

Future<void> _choosePhoto(BuildContext context, OnboardingViewModel model) {
  final scheme = Theme.of(context).colorScheme;
  return showModalBottomSheet<void>(
    context: context,
    sheetAnimationStyle: AppMotion.sheet(context),
    constraints: AdaptiveLayout.sheetConstraints,
    backgroundColor: scheme.surfaceContainerLowest,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (sheetContext) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Pet photo',
                style: Theme.of(sheetContext).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'People use this to know which pet they are looking at.',
                style: Theme.of(sheetContext).textTheme.bodyLarge,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => _pick(context, sheetContext, ImageSource.camera),
                child: const Text('Take a photo'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () =>
                    _pick(context, sheetContext, ImageSource.gallery),
                child: const Text('Choose from photos'),
              ),
              if (model.photoBytes != null) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {
                    model.setPhoto(null);
                    Navigator.of(sheetContext).pop();
                  },
                  child: const Text('Remove photo'),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

Future<void> _pick(
  BuildContext context,
  BuildContext sheetContext,
  ImageSource source,
) async {
  Navigator.of(sheetContext).pop();
  try {
    final file = await ImagePicker().pickImage(
      source: source,
      maxWidth: 800,
      imageQuality: 80,
    );
    if (file == null || !context.mounted) return;
    final bytes = await file.readAsBytes();
    if (!context.mounted) return;
    context.read<OnboardingViewModel>().setPhoto(bytes);
  } on PlatformException {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Could not open the camera or photos. Try the other one.'),
      ),
    );
  }
}

class _SpeciesChip extends StatelessWidget {
  const _SpeciesChip({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 48,
      child: Material(
        color: selected
            ? scheme.primaryContainer
            : scheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Center(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? context.paws.brandDark : scheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AgeStepper extends StatelessWidget {
  const _AgeStepper({required this.years});

  final int years;

  @override
  Widget build(BuildContext context) {
    final model = context.read<OnboardingViewModel>();
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Age',
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: SizedBox(
            height: 52,
            child: Row(
              children: [
                IconButton(
                  tooltip: years <= 0 ? 'Youngest age is 0' : 'Decrease age',
                  onPressed: years <= 0 ? null : () => model.changeAge(-1),
                  icon: const Text('−', style: TextStyle(fontSize: 20)),
                ),
                Expanded(
                  child: Text(
                    '$years yrs',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: years >= 30 ? 'Oldest age is 30' : 'Increase age',
                  onPressed: years >= 30 ? null : () => model.changeAge(1),
                  icon: const Text('+', style: TextStyle(fontSize: 20)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _WeightField extends StatelessWidget {
  const _WeightField({required this.weight});

  final String weight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Weight (optional)',
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 52,
          child: TextFormField(
            initialValue: weight,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            onChanged: context.read<OnboardingViewModel>().setWeight,
            decoration: InputDecoration(
              suffixText: 'kg',
              suffixStyle: Theme.of(context).textTheme.bodyLarge
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ),
      ],
    );
  }
}
