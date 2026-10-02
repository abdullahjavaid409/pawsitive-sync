import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/motion/app_motion.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/paws_widgets.dart';
import 'package:pawsitive_sync/core/widgets/pet_mark.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_view_model.dart';
import 'package:provider/provider.dart';

/// Collects the pet's name and species. Photo, age, and weight come next.
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
                          onBack: () => context.go(AppRoutes.day),
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
                                  child: Column(
                                    children: [
                                      PetMark(
                                        species: model.species,
                                        size: 88,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        _label(model.species),
                                        style: text.titleSmall,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 28),
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
                              for (var row = 0; row < 2; row++) ...[
                                Row(
                                  children: [
                                    for (var column = 0; column < 2; column++) ...[
                                      Expanded(
                                        child: _SpeciesChip(
                                          label: _label(
                                            Species.values[row * 2 + column],
                                          ),
                                          selected:
                                              model.species ==
                                              Species.values[row * 2 + column],
                                          onPressed: () => model.setSpecies(
                                            Species.values[row * 2 + column],
                                          ),
                                        ),
                                      ),
                                      if (column == 0) const SizedBox(width: 12),
                                    ],
                                  ],
                                ),
                                if (row == 0) const SizedBox(height: 12),
                              ],
                            ],
                          ),
                        ),
                        const Spacer(),
                        Padding(
                          padding: const EdgeInsets.only(left: 12),
                          child: FilledButton(
                            onPressed: model.petName.trim().isEmpty
                                ? null
                                : () => context.go(AppRoutes.petDetails),
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
