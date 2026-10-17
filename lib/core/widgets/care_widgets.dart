import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/paws_widgets.dart';
import 'package:pawsitive_sync/core/widgets/pet_mark.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';
import 'package:pawsitive_sync/domain/models.dart';

/// v14 gutters (16) for tab pages that don't need the safe-area bottom.
const carePagePadding = EdgeInsets.fromLTRB(16, 8, 16, 28);

/// Page insets that stay comfortable on a narrow window while using the
/// shared spacing roles everywhere else.
EdgeInsets carePagePaddingOf(BuildContext context) {
  final spacing = context.paws.spacing;
  final width = MediaQuery.sizeOf(context).width;
  // v14 tab pages: 16 px gutters so cards run nearly edge to edge, and a
  // short top inset under the status bar.
  final horizontal = width < 340 ? spacing.md : spacing.lg;
  return EdgeInsets.fromLTRB(
    horizontal,
    spacing.sm,
    horizontal,
    // The floating tab bar (or the home indicator) sits over the page's
    // bottom inset, so the last item can always scroll clear of it.
    spacing.pageBottom + MediaQuery.paddingOf(context).bottom,
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

  /// Moves the caret onto the page title's edge; the 48pt target is kept.
  static const _opticalShift = 14.0;

  @override
  Widget build(BuildContext context) => Transform.translate(
    offset: Offset(
      Directionality.of(context) == TextDirection.rtl
          ? _opticalShift
          : -_opticalShift,
      0,
    ),
    child: _button(context),
  );

  Widget _button(BuildContext context) => IconButton(
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

/// The round gear in a tab's header (Today, Household): one look everywhere.
class CareSettingsButton extends StatelessWidget {
  const CareSettingsButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = context.paws;
    return IconButton(
      tooltip: 'Settings',
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: tokens.surfaces.card,
        side: BorderSide(color: tokens.borders.subtle),
        minimumSize: Size.square(tokens.controlHeights.icon),
      ),
      icon: StrokeIcon(
        StrokeIconKind.settings,
        size: 21,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    );
  }
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
  Widget build(BuildContext context) => Padding(
    // Same 4 px inset as [CareSectionHeader] (v14 `px-1` on headers).
    padding: CareSectionHeader.inset,
    child: _build(context),
  );

  Widget _build(BuildContext context) => LayoutBuilder(
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
          // One line that shrinks to fit: "Household" at 2x text on a small
          // phone scales down instead of breaking mid-word.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(title, maxLines: 1, style: text.displaySmall),
          ),
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

  /// v14 insets section titles 4 px (`px-1`) so they line up with the
  /// text inside the cards below, not the cards' edge.
  static const inset = EdgeInsets.symmetric(horizontal: 4);

  @override
  Widget build(BuildContext context) =>
      Padding(padding: inset, child: _build(context));

  Widget _build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final text = Theme.of(context).textTheme;
      final spacing = context.paws.spacing;
      final stack =
          action != null &&
          // 16 px gutters leave 358 on a 390 phone: only stack below 300.
          (constraints.maxWidth < 300 ||
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
              _HeaderAction(
                label: action!,
                onPressed: onAction!,
                // Flush with the title so the stacked pair reads as one block.
                padding: EdgeInsets.zero,
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
              _HeaderAction(label: action!, onPressed: onAction!),
          ],
        ],
      );
    },
  );
}

/// The tappable half of a section header: brand-coloured with a leading +, so
/// it never reads as a second heading when large text stacks it under the
/// title.
class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    required this.label,
    required this.onPressed,
    this.padding,
  });

  final String label;
  final VoidCallback onPressed;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final color = context.paws.brandDark;
    return TextButton.icon(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: color,
        // No end padding: the label ends on the header's edge; still 44pt.
        padding: padding ?? const EdgeInsetsDirectional.only(start: 8),
        minimumSize: const Size(44, 44),
        textStyle: Theme.of(context).textTheme.labelLarge,
      ),
      icon: StrokeIcon(StrokeIconKind.plus, size: 18, color: color),
      label: Text(label),
    );
  }
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
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: isPro ? tokens.brandDark : scheme.onSurfaceVariant,
            ),
          ),
          if (!isPro && onUpgrade != null) ...[
            // A hairline splits plan from action so they never read as one
            // phrase ("Free See Pro").
            Container(
              width: 1,
              height: 12,
              margin: EdgeInsets.symmetric(horizontal: tokens.spacing.sm),
              color: tokens.borders.standard,
            ),
            Text(
              'See Pro',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: tokens.brandDark,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(width: tokens.spacing.xs / 2),
            StrokeIcon(
              StrokeIconKind.chevronRight,
              size: 12,
              color: tokens.brandDark,
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

/// A pet's photo as a rounded square (v14 sheet and profile tiles), or its
/// drawn mark on a chip-coloured tile when there is no readable photo.
/// Decoded at display size; the caller clips the corners.
class PetPortraitSquare extends StatelessWidget {
  const PetPortraitSquare({super.key, required this.pet, this.size = 56});

  final Pet pet;
  final double size;

  @override
  Widget build(BuildContext context) {
    final mark = ColoredBox(
      color: context.paws.surfaces.subtle,
      child: Center(
        child: PetMark(species: pet.species, size: size * 0.8),
      ),
    );
    final path = pet.photoPath;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: path == null
            ? mark
            : Image.file(
                File(path),
                // A replaced photo keeps its path: the version busts the cache.
                key: ValueKey('$path#${pet.photoVersion}'),
                fit: BoxFit.cover,
                cacheWidth: (size * MediaQuery.devicePixelRatioOf(context))
                    .round(),
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => mark,
              ),
      ),
    );
  }
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
      // v14 pills: ink when selected, a lifted cream pill otherwise.
      child: Material(
        color: selected ? scheme.onSurface : tokens.surfaces.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: tokens.radii.chipShape,
          side: selected
              ? BorderSide.none
              : BorderSide(color: tokens.borders.subtle.withValues(alpha: 0.6)),
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
                    color: selected ? scheme.surface : scheme.onSurface,
                  ),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: selected ? scheme.surface : scheme.onSurface,
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

/// A list row with one text action ("Upgrade") on the right. On a narrow
/// window or at large text the action moves under the text, so neither is
/// squeezed into a sliver.
class CareActionTile extends StatelessWidget {
  const CareActionTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.action,
    required this.onAction,
  });

  final String title;
  final String subtitle;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final text = Theme.of(context).textTheme;
      final stack =
          constraints.maxWidth < 360 ||
          MediaQuery.textScalerOf(context).scale(1) > 1.3;
      final button = TextButton(
        onPressed: onAction,
        style: TextButton.styleFrom(foregroundColor: context.paws.brandDark),
        child: Text(action),
      );
      if (!stack) {
        return ListTile(
          title: Text(title, style: text.titleSmall),
          subtitle: Text(subtitle),
          trailing: button,
        );
      }
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: text.titleSmall),
            const SizedBox(height: 4),
            Text(subtitle, style: text.bodyMedium),
            button,
          ],
        ),
      );
    },
  );
}

/// An empty screen that still feels lived-in: a real photo, one line of
/// what goes here, and the one action that fills it.
class CareEmptyState extends StatelessWidget {
  const CareEmptyState({
    super.key,
    required this.title,
    required this.description,
    required this.action,
    required this.onAction,
    this.photo = 'assets/photos/empty-no-medicine.jpg',
  });
  final String title;
  final String description;
  final String action;
  final VoidCallback onAction;

  /// A 3:2 photo from `assets/photos/` (see its README).
  final String photo;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final width =
        (MediaQuery.sizeOf(context).width *
                MediaQuery.devicePixelRatioOf(context))
            .round();
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 3 / 2,
            child: Image.asset(
              photo,
              fit: BoxFit.cover,
              cacheWidth: width,
              excludeFromSemantics: true,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: text.headlineSmall),
                const SizedBox(height: 8),
                Text(
                  description,
                  style: text.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: onAction,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  child: Text(action, textAlign: TextAlign.center),
                ),
              ],
            ),
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
