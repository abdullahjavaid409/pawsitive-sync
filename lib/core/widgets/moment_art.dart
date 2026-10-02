import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:lottie/lottie.dart';
import 'package:pawsitive_sync/core/motion/app_motion.dart';

/// Plays one drawing from the Lottie pack, then holds the last frame.
///
/// Reduce Motion shows the still drawing instead.
class MomentArt extends StatelessWidget {
  const MomentArt(
    this.name, {
    super.key,
    this.size = 120,
    this.announce = true,
  });

  final String name;
  final double size;

  /// When the words beside the drawing already say this, leave it silent.
  final bool announce;

  static const labels = <String, String>{
    'welcome': 'A shared dose',
    'morning': 'Morning',
    'afternoon': 'Afternoon',
    'evening': 'Evening',
    'dose.logged': 'Dose saved',
    'dose.already': 'Already given',
    'dose.skipped': 'Dose skipped',
    'dose.empty': 'Nothing scheduled',
    'medication.low': 'Running low',
    'medication.refilled': 'Refilled',
    'reminders.on': 'Reminders on',
    'reminders.off': 'Reminders off',
    'household.synced': 'Household up to date',
    'household.sync_failed': 'Could not refresh',
  };

  @override
  Widget build(BuildContext context) {
    final child = AppMotion.reduced(context)
        ? SvgPicture.asset(
            'assets/lottie/$name.svg',
            width: size,
            height: size,
            fit: BoxFit.contain,
          )
        : Lottie.asset(
            'assets/lottie/$name.json',
            width: size,
            height: size,
            fit: BoxFit.contain,
            repeat: false,
          );
    if (!announce) return child;
    final label = labels[name];
    if (label == null) return child;
    return Semantics(label: label, child: child);
  }
}

/// Shows one moment, then closes itself so the person can keep going.
Future<void> showMoment(
  BuildContext context, {
  required String name,
  required String message,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _MomentDialog(name: name, message: message),
  );
}

class _MomentDialog extends StatefulWidget {
  const _MomentDialog({required this.name, required this.message});

  final String name;
  final String message;

  @override
  State<_MomentDialog> createState() => _MomentDialogState();
}

class _MomentDialogState extends State<_MomentDialog> {
  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 1400), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MomentArt(widget.name, size: 140),
            const SizedBox(height: 12),
            Text(
              widget.message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }
}
