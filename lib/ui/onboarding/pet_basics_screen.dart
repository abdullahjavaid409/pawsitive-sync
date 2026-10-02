import 'package:flutter/material.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/paws_widgets.dart';
import 'package:pawsitive_sync/core/widgets/pet_mark.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_view_model.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_visuals.dart';
import 'package:provider/provider.dart';

class PetBasicsScreen extends StatelessWidget {
  const PetBasicsScreen({super.key});

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
              'Start with one pet. There’s room for the whole family later.',
            ),
            const SizedBox(height: 32),
            Text('Pet’s name', style: text.titleSmall),
            const SizedBox(height: 10),
            TextFormField(
              initialValue: model.petName,
              onChanged: model.setName,
              maxLength: OnboardingViewModel.maxPetNameLength,
              buildCounter: (
                context, {
                required currentLength,
                required isFocused,
                maxLength,
              }) => null,
              decoration: const InputDecoration(
                hintText: 'e.g. Miso',
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 18,
                ),
              ),
              style: text.titleLarge?.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
              textInputAction: TextInputAction.done,
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 28),
            Text('What kind of pet?', style: text.titleSmall),
            const SizedBox(height: 12),
            for (var row = 0; row < 2; row++) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var column = 0; column < 2; column++) ...[
                    if (column > 0) const SizedBox(width: 12),
                    Expanded(
                      child: _SpeciesTile(
                        species: Species.values[row * 2 + column],
                        selected:
                            model.species == Species.values[row * 2 + column],
                        onPressed: () =>
                            model.setSpecies(Species.values[row * 2 + column]),
                      ),
                    ),
                  ],
                ],
              ),
              if (row == 0) const SizedBox(height: 12),
            ],
            const SizedBox(height: 24),
            const OnboardingNote('A care routine made just for them.'),
          ],
        ),
        footer: FilledButton(
          onPressed: model.hasValidPetName
              ? () {
                  AppLog.event('onboarding.step', {'step': 'pet_basics'});
                  FocusScope.of(context).unfocus();
                  context.go(AppRoutes.petDetails);
                }
              : null,
          child: Text(
            model.hasValidPetName ? 'Continue' : 'Add a name to continue',
          ),
        ),
      ),
    );
  }
}

class _SpeciesTile extends StatelessWidget {
  const _SpeciesTile({
    required this.species,
    required this.selected,
    required this.onPressed,
  });

  final Species species;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = switch (species) {
      Species.cat => 'Cat',
      Species.dog => 'Dog',
      Species.rabbit => 'Rabbit',
      Species.other => 'Other',
    };
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      child: Material(
        color: selected
            ? scheme.primaryContainer
            : scheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(20),
          child: ExcludeSemantics(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      PetMark(species: species, size: 56, artScale: 1),
                      CheckMark(selected: selected, size: 20),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      label,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: selected
                            ? context.paws.brandDark
                            : scheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
