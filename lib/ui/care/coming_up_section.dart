import 'package:flutter/material.dart';
import 'package:pawsitive_sync/core/format/day_label.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/care_widgets.dart';
import 'package:pawsitive_sync/core/widgets/paws_widgets.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:pawsitive_sync/ui/care/add_care_event_sheet.dart';
import 'package:provider/provider.dart';

/// "Coming up": a pet's vet visits, vaccines and refills with "Add event".
/// Lives on the pet's page (v14 keeps Today to doses only).
class ComingUpSection extends StatelessWidget {
  const ComingUpSection({super.key, required this.care, required this.petId});

  final CareRepository care;
  final String petId;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final events = care
        .upcomingCareEvents(withinDays: 60)
        .where((e) => e.petId == petId)
        .take(5)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CareSectionHeader(
          'Coming up',
          action: 'Add event',
          onAction: () => showAddCareEventSheet(context, petId: petId),
        ),
        const SizedBox(height: 8),
        if (events.isEmpty)
          // Nothing to draw a box around: one quiet line instead.
          Padding(
            padding: CareSectionHeader.inset,
            child: Text(
              'Vet visits, vaccines and refills show here.',
              style: text.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          SurfaceCard(
            child: Column(
              children: [
                for (final (index, event) in events.indexed)
                  _CareEventTile(
                    event: event,
                    pet: care.tryPetById(event.petId),
                    showDivider: index < events.length - 1,
                    // care_event.removed is logged by the repository.
                    onRemove: () {
                      AppLog.unawaitedLogged(
                        care.removeCareEvent(event.id),
                        'care_event.remove_failed',
                        {'eventId': event.id},
                      );
                    },
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

String _careDueLabel(String dueDay, DateTime now) {
  final parsed = DateTime.tryParse(dueDay);
  if (parsed == null) return dueDay;
  final today = DateTime(now.year, now.month, now.day);
  final due = DateTime(parsed.year, parsed.month, parsed.day);
  final diff = due.difference(today).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  if (diff < 7) return 'In $diff days';
  return dayLabel(parsed);
}

class _CareEventTile extends StatelessWidget {
  const _CareEventTile({
    required this.event,
    required this.pet,
    required this.showDivider,
    required this.onRemove,
  });

  final CareEvent event;
  final Pet? pet;
  final bool showDivider;
  final VoidCallback onRemove;

  Future<bool> _confirmRemove(BuildContext context) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Remove care event?'),
          content: Text('“${event.title}” will be removed from Coming up.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Remove'),
            ),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    // The parent list rebuilds on data changes; the tile only needs the clock.
    final now = context.read<CareRepository>().now;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final due = _careDueLabel(event.dueDay, now);
    final petName = pet?.name ?? 'Pet removed';

    return Column(
      children: [
        Dismissible(
          key: ValueKey(event.id),
          direction: DismissDirection.endToStart,
          confirmDismiss: (_) => _confirmRemove(context),
          onDismissed: (_) => onRemove(),
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            color: scheme.errorContainer,
            child: Icon(Icons.delete_outline, color: scheme.onErrorContainer),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: StrokeIcon(
                    StrokeIconKind.calendar,
                    size: 20,
                    color: context.paws.brandDark,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(event.title, style: text.titleSmall),
                      const SizedBox(height: 4),
                      Text(
                        '${event.kindLabel} · $due · $petName',
                        style: text.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      if (event.note.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Text(event.note, style: text.bodySmall),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Remove ${event.title}',
                  onPressed: () async {
                    if (await _confirmRemove(context)) onRemove();
                  },
                  icon: const StrokeIcon(StrokeIconKind.close, size: 18),
                ),
              ],
            ),
          ),
        ),
        if (showDivider) Divider(height: 1, color: scheme.outlineVariant),
      ],
    );
  }
}
