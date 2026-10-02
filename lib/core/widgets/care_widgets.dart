import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/pet_mark.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';
import 'package:pawsitive_sync/domain/models.dart';

const carePagePadding = EdgeInsets.fromLTRB(24, 20, 24, 28);

class CarePageHeader extends StatelessWidget {
  const CarePageHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.action,
  });
  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: text.displaySmall?.copyWith(
                  fontSize: 30,
                  letterSpacing: -0.9,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                subtitle,
                style: text.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
        if (action != null) ...[const SizedBox(width: 12), action!],
      ],
    );
  }
}

class CareSectionHeader extends StatelessWidget {
  const CareSectionHeader(this.title, {super.key, this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(title, style: Theme.of(context).textTheme.headlineSmall),
      ),
      if (action != null)
        if (onAction == null)
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Text(action!, style: Theme.of(context).textTheme.bodyMedium),
          )
        else
          TextButton(onPressed: onAction, child: Text(action!)),
    ],
  );
}

class PetPortrait extends StatelessWidget {
  const PetPortrait(this.pet, {super.key, this.size = 52});
  final Pet pet;
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: PetMark(species: pet.species, size: size, artScale: 1),
  );
}

/// The same selector filters a daily list, pet profile or report.
class CarePetPicker extends StatelessWidget {
  const CarePetPicker({
    super.key,
    required this.pets,
    required this.selectedId,
    required this.onSelected,
    this.includeAll = false,
    this.verticalWhenMany = false,
    this.verticalThreshold = 3,
  });
  final List<Pet> pets;
  final String? selectedId;
  final ValueChanged<String?> onSelected;
  final bool includeAll;

  /// When true and [pets.length] >= [verticalThreshold], show a vertical list.
  final bool verticalWhenMany;
  final int verticalThreshold;

  @override
  Widget build(BuildContext context) {
    final useVertical = verticalWhenMany && pets.length >= verticalThreshold;
    if (useVertical) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (includeAll)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _PetChoice(
                label: 'All pets',
                selected: selectedId == null,
                onTap: () => onSelected(null),
                expanded: true,
              ),
            ),
          for (final pet in pets)
            Padding(
              padding: EdgeInsets.only(bottom: pet == pets.last ? 0 : 8),
              child: _PetChoice(
                label: pet.name,
                pet: pet,
                selected: selectedId == pet.id,
                onTap: () => onSelected(pet.id),
                expanded: true,
              ),
            ),
        ],
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          if (includeAll) ...[
            _PetChoice(
              label: 'All pets',
              selected: selectedId == null,
              onTap: () => onSelected(null),
            ),
            const SizedBox(width: 8),
          ],
          for (final pet in pets) ...[
            _PetChoice(
              label: pet.name,
              pet: pet,
              selected: selectedId == pet.id,
              onTap: () => onSelected(pet.id),
            ),
            if (pet != pets.last) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _PetChoice extends StatelessWidget {
  const _PetChoice({
    required this.label,
    required this.selected,
    required this.onTap,
    this.pet,
    this.expanded = false,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Pet? pet;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected
            ? scheme.primaryContainer
            : scheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: selected ? scheme.primary : scheme.outlineVariant,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
              children: [
                if (pet != null) ...[
                  PetPortrait(pet!, size: 30),
                  const SizedBox(width: 8),
                ] else ...[
                  StrokeIcon(
                    StrokeIconKind.paw,
                    size: 20,
                    color: context.paws.brandDark,
                  ),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: selected ? context.paws.brandDark : scheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CareIllustration extends StatelessWidget {
  const CareIllustration(this.name, {super.key, this.height = 110});
  final String name;
  final double height;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SvgPicture.asset(
      'assets/art/$name.svg',
      height: height,
      fit: BoxFit.contain,
    ),
  );
}

class CareEmptyState extends StatelessWidget {
  const CareEmptyState({
    super.key,
    required this.title,
    required this.description,
    required this.action,
    required this.onAction,
    this.art = 'onboarding-welcome',
  });
  final String title;
  final String description;
  final String action;
  final VoidCallback onAction;
  final String art;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: context.paws.brandSoft,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CareIllustration(art, height: 140),
          const SizedBox(height: 20),
          Text(title, style: text.headlineSmall),
          const SizedBox(height: 8),
          Text(
            description,
            style: text.bodyLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: onAction,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            child: Text(action, textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }
}

class CareMetric extends StatelessWidget {
  const CareMetric({super.key, required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        value,
        style: Theme.of(context).textTheme.headlineSmall
            ?.copyWith(fontSize: 24),
      ),
      const SizedBox(height: 5),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}
