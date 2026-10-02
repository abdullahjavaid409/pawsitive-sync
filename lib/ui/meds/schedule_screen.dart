import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/core/theme/app_colors.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';

/// Lets a caregiver choose when a repeating dose is due.
class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  bool _fromLastDose = true;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.paws;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Back',
                      onPressed: () => context.pop(),
                      icon: StrokeIcon(
                        StrokeIconKind.chevronLeft,
                        color: scheme.onSurface,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'New medication',
                        textAlign: TextAlign.center,
                        style: text.titleMedium,
                      ),
                    ),
                    SizedBox(
                      width: 48,
                      child: Text(
                        '2/3',
                        textAlign: TextAlign.center,
                        style: text.bodyMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: tokens.neutral,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    child: Text(
                      'Heartworm chew · Juniper',
                      style: text.bodyMedium?.copyWith(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'When should the next dose be due?',
                  style: text.headlineMedium,
                ),
                const SizedBox(height: 16),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: SizedBox(
                    height: 52,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Text(
                            'Repeats',
                            style: text.bodyLarge?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            'Every month',
                            style: text.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _Rule(
                  title: 'From the last dose',
                  badge: 'Recommended',
                  body: 'Gave it late? The next one counts from when it was actually given.',
                  selected: _fromLastDose,
                  onPressed: () => setState(() => _fromLastDose = true),
                ),
                const SizedBox(height: 8),
                _Rule(
                  title: 'Same date every month',
                  body: 'Stays on the 1st, even after a late dose.',
                  selected: !_fromLastDose,
                  onPressed: () => setState(() => _fromLastDose = false),
                ),
                const SizedBox(height: 16),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: tokens.neutral,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'HOW THIS PLAYS OUT',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                        const SizedBox(height: 16),
                        const _Timeline(),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Row(
                  children: [
                    Expanded(
                      child: _Mini(label: 'Remind at', value: '9:00 AM'),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: _Mini(label: 'In the box', value: '6 chews'),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () {
                    AppLog.event('schedule.not_saved');
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Saved on Juniper’s schedule.'),
                      ),
                    );
                    context.go(AppRoutes.today);
                  },
                  child: const Text('Save medication'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Rule extends StatelessWidget {
  const _Rule({
    required this.title,
    required this.body,
    required this.selected,
    required this.onPressed,
    this.badge,
  });

  final String title;
  final String body;
  final bool selected;
  final VoidCallback onPressed;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.paws;
    return Material(
      color: scheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 22,
                height: 22,
                margin: const EdgeInsets.only(top: 1),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? scheme.primary : scheme.outline,
                    width: selected ? 6 : 1.5,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (badge != null)
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer,
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              child: Text(
                                badge!,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: tokens.brandDark,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      body,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w400,
                        height: 1.4,
                        color: selected
                            ? scheme.onSurface
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: 7,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 0),
            child: Align(
              alignment: Alignment.center,
              child: FractionallySizedBox(
                widthFactor: 0.75,
                child: Container(height: 2, color: scheme.outline),
              ),
            ),
          ),
        ),
        const Row(
          children: [
            Expanded(
              child: _Stop(
                date: 'Sep 1',
                caption: 'was due',
                struck: true,
                fill: _StopFill.outlineMuted,
              ),
            ),
            Expanded(
              child: _Stop(
                date: 'Sep 4',
                caption: 'given late',
                fill: _StopFill.amber,
              ),
            ),
            Expanded(
              child: _Stop(
                date: 'Oct 4',
                caption: 'next due',
                fill: _StopFill.brand,
              ),
            ),
            Expanded(
              child: _Stop(
                date: 'Nov 4',
                caption: 'then',
                fill: _StopFill.outlineBrand,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

enum _StopFill { outlineMuted, amber, brand, outlineBrand }

class _Stop extends StatelessWidget {
  const _Stop({
    required this.date,
    required this.caption,
    required this.fill,
    this.struck = false,
  });

  final String date;
  final String caption;
  final _StopFill fill;
  final bool struck;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.paws;
    final dateColor = switch (fill) {
      _StopFill.outlineMuted => scheme.onSurfaceVariant,
      _StopFill.amber => scheme.onSurface,
      _StopFill.brand => tokens.brandDark,
      _StopFill.outlineBrand => scheme.onSurface,
    };
    final captionColor = switch (fill) {
      _StopFill.amber => tokens.warning,
      _StopFill.brand => tokens.brandDark,
      _ => scheme.onSurfaceVariant,
    };
    return Column(
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: switch (fill) {
              _StopFill.amber => tokens.amber,
              _StopFill.brand => scheme.primary,
              _StopFill.outlineMuted => scheme.surface,
              _ => scheme.surfaceContainerLowest,
            },
            border: switch (fill) {
              _StopFill.outlineMuted => Border.all(
                color: AppColors.timelineMuted,
                width: 2,
              ),
              _StopFill.outlineBrand => Border.all(
                color: scheme.primary,
                width: 2,
              ),
              _ => null,
            },
          ),
        ),
        const SizedBox(height: 8),
        Text(
          date,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: dateColor,
            fontWeight: FontWeight.w600,
            decoration: struck ? TextDecoration.lineThrough : null,
          ),
        ),
        Text(
          caption,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: captionColor),
        ),
      ],
    );
  }
}

class _Mini extends StatelessWidget {
  const _Mini({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyLarge
                  ?.copyWith(fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}
