import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/core/widgets/paws_widgets.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';

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
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
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
                  Text('2/3', style: text.bodyMedium),
                ],
              ),
              const SizedBox(height: 8),
              Text('Heartworm chew · Juniper', style: text.bodyMedium),
              const SizedBox(height: 8),
              Text(
                'When should the next dose be due?',
                style: text.headlineMedium,
              ),
              const SizedBox(height: 16),
              SurfaceCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Text('Repeats', style: text.bodyLarge),
                    const Spacer(),
                    Text('Every month', style: text.titleSmall),
                  ],
                ),
              ),
              const SizedBox(height: 12),
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
              Text('HOW THIS PLAYS OUT', style: text.labelSmall),
              const SizedBox(height: 8),
              const Row(
                children: [
                  Expanded(
                    child: _Play(date: 'Sep 1', caption: 'was due'),
                  ),
                  Expanded(
                    child: _Play(date: 'Sep 4', caption: 'given late'),
                  ),
                  Expanded(
                    child: _Play(date: 'Oct 4', caption: 'next due'),
                  ),
                  Expanded(
                    child: _Play(date: 'Nov 4', caption: 'then'),
                  ),
                ],
              ),
              const Spacer(),
              SurfaceCard(
                child: const Column(
                  children: [
                    _Line(label: 'Remind at', value: '9:00 AM'),
                    _Line(
                      label: 'In the box',
                      value: '6 chews',
                      divider: false,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Medication saved to Juniper’s schedule.'),
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
    return Material(
      color: scheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: selected ? 1.5 : 1,
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
                margin: const EdgeInsets.only(top: 2),
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
                    Text.rich(
                      TextSpan(
                        text: title,
                        style: Theme.of(context).textTheme.titleMedium,
                        children: [
                          if (badge != null)
                            TextSpan(
                              text: '  $badge',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: scheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                        ],
                      ),
                    ),
                    Text(body, style: Theme.of(context).textTheme.bodyMedium),
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

class _Play extends StatelessWidget {
  const _Play({required this.date, required this.caption});

  final String date;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(height: 8),
        Text(date, style: Theme.of(context).textTheme.titleSmall),
        Text(caption, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value, this.divider = true});

  final String label;
  final String value;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: divider
            ? Border(
                bottom: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              )
            : null,
      ),
      child: Row(
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyLarge),
          const Spacer(),
          Text(value, style: Theme.of(context).textTheme.titleSmall),
        ],
      ),
    );
  }
}
