import 'package:flutter/material.dart';
import 'package:pawsitive_sync/core/routing/app_route_observer.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:lottie/lottie.dart';
import 'package:pawsitive_sync/core/motion/app_motion.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';

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
    Widget picture = RepaintBoundary(child: child);
    if (Theme.of(context).brightness == Brightness.dark) {
      // The pack is inked for light paper, so on a dark surface the strokes
      // disappear. Give it its paper back: the inverse surface is the light
      // background colour, with a little margin so strokes don’t touch it.
      picture = DecoratedBox(
        decoration: BoxDecoration(
          color: context.paws.surfaces.inverse,
          borderRadius: BorderRadius.circular(size / 4),
        ),
        child: Padding(padding: EdgeInsets.all(size / 10), child: picture),
      );
    }
    if (!announce) return picture;
    final label = labels[name];
    if (label == null) return picture;
    return Semantics(label: label, child: picture);
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
    // A self-closing confirmation, not navigation: the route observer
    // leaves it out of the log (the action it confirms is logged already).
    routeSettings: const RouteSettings(name: AppRouteObserver.moment),
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
