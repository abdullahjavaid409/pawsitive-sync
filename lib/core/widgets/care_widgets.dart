import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/pet_mark.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';
import 'package:pawsitive_sync/domain/models.dart';

const carePagePadding = EdgeInsets.fromLTRB(24, 20, 24, 28);

/// Page insets that stay comfortable on a narrow window while using the
/// shared spacing roles everywhere else.
EdgeInsets carePagePaddingOf(BuildContext context) {
  final spacing = context.paws.spacing;
  final width = MediaQuery.sizeOf(context).width;
  final horizontal = width < 340 ? spacing.lg : spacing.pageHorizontal;
  return EdgeInsets.fromLTRB(
    horizontal,
    spacing.pageTop,
    horizontal,
    spacing.pageBottom,
  );
}

/// The shared back affordance for pushed care pages.
class CareBackButton extends StatelessWidget {
  const CareBackButton({
    super.key,
    required this.fallbackRoute,
    this.onPressed,
    this.enabled = true,
  });

  final String fallbackRoute;
  final VoidCallback? onPressed;
  final bool enabled;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Back',
    onPressed: enabled
        ? onPressed ??
              () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go(fallbackRoute);
                }
              }
        : null,
    style: IconButton.styleFrom(
      minimumSize: Size.square(context.paws.controlHeights.icon),
    ),
    icon: const StrokeIcon(StrokeIconKind.chevronLeft),
  );
}

class CarePageHeader extends StatelessWidget {
  const CarePageHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.action,
    this.leading,
  });
  final String title;
  final String subtitle;
  final Widget? action;
  final Widget? leading;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final spacing = context.paws.spacing;
      final text = Theme.of(context).textTheme;
      final textScale = MediaQuery.textScalerOf(context).scale(1);
      final hasControls = leading != null || action != null;
      final stackControls =
          hasControls && (constraints.maxWidth < 360 || textScale > 1.2);
      final titleBlock = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: text.displaySmall),
          if (subtitle.isNotEmpty) ...[
            SizedBox(height: spacing.xs + 3),
            Text(
              subtitle,
              style: text.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      );

      if (stackControls) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [?leading, const Spacer(), ?action]),
            SizedBox(height: spacing.sm),
            titleBlock,
          ],
        );
      }

      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (leading != null) ...[leading!, SizedBox(width: spacing.xs)],
          Expanded(child: titleBlock),
          if (action != null) ...[SizedBox(width: spacing.md), action!],
        ],
      );
    },
  );
}

class CareSectionHeader extends StatelessWidget {
  const CareSectionHeader(this.title, {super.key, this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final text = Theme.of(context).textTheme;
      final spacing = context.paws.spacing;
      final stack =
          action != null &&
          (constraints.maxWidth < 360 ||
              MediaQuery.textScalerOf(context).scale(1) > 1.2);
      final titleWidget = Text(title, style: text.headlineSmall);
      if (stack) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            titleWidget,
            SizedBox(height: spacing.xs),
            if (onAction == null)
              Text(action!, style: text.bodyMedium)
            else
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                child: Text(action!),
              ),
          ],
        );
      }
      return Row(
        children: [
          Expanded(child: titleWidget),
          if (action != null) ...[
            SizedBox(width: spacing.md),
            if (onAction == null)
              Text(action!, style: text.bodyMedium)
            else
              TextButton(onPressed: onAction, child: Text(action!)),
          ],
        ],
      );
    },
  );
}

/// Small, explicit plan affordance used in the Today header.
///
/// Dose logging stays available in both states; the Free action only explains
/// what Pro adds for households that want shared care.
class CarePlanBadge extends StatelessWidget {
  const CarePlanBadge({super.key, required this.isPro, this.onUpgrade});

  final bool isPro;
  final VoidCallback? onUpgrade;

  @override
  Widget build(BuildContext context) {
    final tokens = context.paws;
    final scheme = Theme.of(context).colorScheme;
    final label = isPro ? 'Pro' : 'Free';
    final semanticsLabel = isPro ? 'Pro plan' : 'Free plan. See Pro features';
    final content = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: tokens.spacing.sm + 2,
        vertical: tokens.spacing.xs + 2,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StrokeIcon(
            isPro ? StrokeIconKind.check : StrokeIconKind.paw,
            size: 15,
            color: tokens.brandDark,
          ),
          SizedBox(width: tokens.spacing.xs + 1),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: tokens.brandDark),
          ),
          if (!isPro && onUpgrade != null) ...[
            SizedBox(width: tokens.spacing.xs),
            Text(
              'See Pro',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: tokens.brandDark,
                decoration: TextDecoration.underline,
              ),
            ),
          ],
        ],
      ),
    );

    return Semantics(
      container: true,
      label: semanticsLabel,
      button: !isPro && onUpgrade != null,
      child: Material(
        color: isPro ? scheme.primaryContainer : tokens.surfaces.subtle,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radii.pill),
          side: BorderSide(color: tokens.borders.subtle),
        ),
        child: onUpgrade == null || isPro
            ? content
            : InkWell(
                onTap: onUpgrade,
                borderRadius: BorderRadius.circular(tokens.radii.pill),
                child: content,
              ),
      ),
    );
  }
}

class PetPortrait extends StatelessWidget {
  const PetPortrait(this.pet, {super.key, this.size = 52});
  final Pet pet;
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: PetAvatar(
      species: pet.species,
      photoPath: pet.photoPath,
      photoVersion: pet.photoVersion,
      size: size,
      artScale: 1,
    ),
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
    final tokens = context.paws;
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? scheme.primaryContainer : tokens.surfaces.card,
        shape: RoundedRectangleBorder(
          borderRadius: tokens.radii.chipShape,
          side: BorderSide(
            color: selected ? tokens.borders.focus : tokens.borders.subtle,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: tokens.radii.chipShape,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: tokens.spacing.md,
              vertical: tokens.spacing.xs + 5,
            ),
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
                    color: selected
                        ? tokens.states.selectedContent
                        : scheme.onSurface,
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
