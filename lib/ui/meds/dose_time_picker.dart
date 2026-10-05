import 'package:flutter/material.dart';
import 'package:pawsitive_sync/core/format/clock_format.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';
import 'package:pawsitive_sync/domain/models.dart';

/// Opens the system time picker for [part]'s reminder, starting at
/// [currentMinute]. Returns the picked minute of day, or null when
/// dismissed. The picker follows the phone’s 12/24-hour setting.
Future<int?> pickDoseTime(
  BuildContext context,
  DayPart part,
  int currentMinute,
) async {
  final picked = await showTimePicker(
    context: context,
    initialTime: TimeOfDay(
      hour: currentMinute ~/ 60,
      minute: currentMinute % 60,
    ),
    helpText: '${part.label} reminder',
    routeSettings: RouteSettings(name: 'dose_time_${part.name}'),
  );
  if (picked == null) {
    AppLog.event('medication.time_pick_cancelled', {'part': part.name});
    return null;
  }
  return picked.hour * 60 + picked.minute;
}

/// One "Morning reminder · 7:00 AM ›" row. Read-only when [onTap] is null
/// (sitters, or nothing to change).
class DoseTimeRow extends StatelessWidget {
  const DoseTimeRow({
    super.key,
    required this.part,
    required this.minute,
    this.onTap,
    this.divider = true,
  });

  final DayPart part;
  final int minute;
  final VoidCallback? onTap;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final label = ClockFormat.label(minute);
    final custom = minute != part.defaultMinute;
    return Semantics(
      button: onTap != null,
      label:
          '${part.label} reminder, $label${custom ? '' : ', default'}'
          '${onTap == null ? '' : '. Double tap to change'}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            border: divider
                ? Border(bottom: BorderSide(color: context.paws.divider))
                : null,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${part.label} reminder',
                  style: text.bodyLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              Text(
                label,
                style: text.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: onTap == null ? null : scheme.primary,
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 4),
                StrokeIcon(
                  StrokeIconKind.chevronRight,
                  size: 18,
                  color: scheme.primary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
