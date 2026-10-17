import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/core/widgets/paws_widgets.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_view_model.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_visuals.dart';
import 'package:pawsitive_sync/ui/pets/widgets/pet_photo_sheet.dart';
import 'package:provider/provider.dart';
import 'package:pawsitive_sync/core/widgets/system_menu.dart';

/// v14 PetStep: a photo, the name and the species on one screen.
class PetBasicsScreen extends StatelessWidget {
  const PetBasicsScreen({super.key});

  /// v14 offers three; rabbits and others are "Other" here and can be
  /// changed on Edit pet.
  // Same four as Edit profile, so a rabbit isn't saved as "Other".
  static const _species = Species.values;

  @override
  Widget build(BuildContext context) {
    final model = context.watch<OnboardingViewModel>();
    final text = Theme.of(context).textTheme;

    return OnboardingStep(
      onBack: () => context.go(AppRoutes.welcome),
      child: OnboardingShell(
        header: OnboardingHeader(
          step: 1,
          onBack: () => context.go(AppRoutes.welcome),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const OnboardingTitle(
              'Who are we caring for?',
              'Start with one pet. You can add more any time.',
            ),
            const SizedBox(height: 28),
            const Center(child: _PhotoPicker()),
            const SizedBox(height: 28),
            const FieldLabel('Name'),
            TextFormField(
              contextMenuBuilder: appContextMenuBuilder,
              initialValue: model.petName,
              onChanged: model.setName,
              maxLength: OnboardingViewModel.maxPetNameLength,
              buildCounter: (
                context, {
                required currentLength,
                required isFocused,
                maxLength,
              }) => null,
              decoration: const InputDecoration(hintText: 'Miso'),
              style: text.bodyLarge,
              textInputAction: TextInputAction.done,
              textCapitalization: TextCapitalization.words,
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
            ),
            const SizedBox(height: 20),
            const FieldLabel('Species'),
            ChoicePills<Species>(
              label: 'Species',
              options: _species,
              value: model.speciesPicked ? model.species : null,
              labelOf: (s) => switch (s) {
                Species.cat => 'Cat',
                Species.dog => 'Dog',
                Species.rabbit => 'Rabbit',
                Species.other => 'Other',
              },
              onChanged: model.setSpecies,
            ),
          ],
        ),
        footer: OnboardingCta(
          label: 'Continue',
          hint: !model.hasValidPetName
              ? 'Add your pet’s name to continue'
              : !model.speciesPicked
              ? 'Pick cat, dog, rabbit or other'
              : null,
          onPressed: model.petStepDone
              ? () {
                  AppLog.event('onboarding.step', {'step': 'pet'});
                  FocusScope.of(context).unfocus();
                  context.go(AppRoutes.firstMedicine);
                }
              : null,
        ),
      ),
    );
  }
}

/// v14: a 112 pt circle, dashed until a photo is chosen, with the action
/// named underneath. The pet doesn't exist yet, so the compressed photo
/// waits in the model and `CareRepository.applyOnboarding` saves it.
class _PhotoPicker extends StatelessWidget {
  const _PhotoPicker();

  Future<void> _choose(BuildContext context, OnboardingViewModel model) async {
    final choice = await showPetPhotoSheet(
      context,
      hasPhoto: model.photoBytes != null,
    );
    switch (choice) {
      case PetPhotoPicked(:final bytes):
        model.setPhoto(bytes);
      case PetPhotoRemoved():
        AppLog.event('pet.photo_removed', {'stage': 'onboarding'});
        model.setPhoto(null);
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final model = context.watch<OnboardingViewModel>();
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final photo = model.photoBytes;
    return Column(
      children: [
        Semantics(
          button: true,
          label: photo == null ? 'Add a photo' : 'Change photo',
          excludeSemantics: true,
          child: GestureDetector(
            onTap: () => _choose(context, model),
            child: SizedBox.square(
              dimension: 112,
              child: photo != null
                  ? ClipOval(
                      child: Image.memory(
                        photo,
                        fit: BoxFit.cover,
                        cacheWidth:
                            (112 * MediaQuery.devicePixelRatioOf(context))
                                .round(),
                      ),
                    )
                  : CustomPaint(
                      painter: DashedCirclePainter(
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                        strokeWidth: 1.5,
                      ),
                      child: Center(
                        child: StrokeIcon(
                          StrokeIconKind.camera,
                          size: 28,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
            ),
          ),
        ),
        TextButton(
          onPressed: () => _choose(context, model),
          style: TextButton.styleFrom(
            foregroundColor: scheme.primary,
            textStyle: text.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
          ),
          child: Text(photo == null ? 'Add a photo' : 'Change photo'),
        ),
      ],
    );
  }
}
