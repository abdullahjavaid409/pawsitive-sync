import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pawsitive_sync/core/layout/adaptive.dart';
import 'package:pawsitive_sync/core/motion/app_motion.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/paws_widgets.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_view_model.dart';
import 'package:provider/provider.dart';

/// Photo, age, and weight. Kept apart from the name so the first form stays short.
class PetDetailsScreen extends StatelessWidget {
  const PetDetailsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final model = context.watch<OnboardingViewModel>();
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final name = model.petName.trim().isEmpty ? 'them' : model.petName.trim();

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              OnboardingHeader(
                step: 2,
                onBack: () => context.go(AppRoutes.pet),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(left: 12, top: 24),
                  children: [
                    Text('A little about $name', style: text.headlineMedium),
                    const SizedBox(height: 8),
                    Text(
                      'A photo helps people know which pet this is. Age and weight can wait.',
                      style: text.bodyLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 28),
                    InkWell(
                      onTap: () => _choosePhoto(context, model),
                      borderRadius: BorderRadius.circular(16),
                      child: Row(
                        children: [
                          _PhotoCircle(bytes: model.photoBytes),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
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
                    const SizedBox(height: 28),
                    _AgeStepper(years: model.ageYears),
                    const SizedBox(height: 24),
                    _WeightField(weight: model.weight),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: FilledButton(
                  onPressed: () {
                    final weight = model.weight.trim();
                    if (weight.isNotEmpty &&
                        !RegExp(r'^\d{1,2}(\.\d{1,2})?$').hasMatch(weight)) {
                      ScaffoldMessenger.of(context).showSnackBar(
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
                  child: const Text('Continue'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
          ? StrokeIcon(StrokeIconKind.camera, color: scheme.onSurfaceVariant)
          : Image.memory(bytes!, width: 80, height: 80, fit: BoxFit.cover),
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
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
          ),
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
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
          ),
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
              suffixStyle: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
