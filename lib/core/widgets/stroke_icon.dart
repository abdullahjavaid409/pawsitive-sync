import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

enum StrokeIconKind {
  paw,
  check,
  calendar,
  people,
  file,
  plus,
  close,
  chevronLeft,
  chevronRight,
  settings,
  refresh,
  bell,
  phone,
  camera,
  alert,
  clock,
  sunrise,
  sun,
  moon,
  medicine,
  mail,
  download,
  eye,
  link,
  share,
  lock,
}

/// One icon family for the whole app: Phosphor, Regular weight (a light
/// 1.5 px stroke that sits well beside SF Pro). Screens name an icon by its
/// role, so changing the family or weight happens here only.
class StrokeIcon extends StatelessWidget {
  const StrokeIcon(this.kind, {super.key, this.size = 24, this.color});

  final StrokeIconKind kind;
  final double size;
  final Color? color;

  static IconData glyph(StrokeIconKind kind) => switch (kind) {
    StrokeIconKind.paw => PhosphorIconsRegular.pawPrint,
    StrokeIconKind.check => PhosphorIconsRegular.check,
    StrokeIconKind.calendar => PhosphorIconsRegular.calendarBlank,
    StrokeIconKind.people => PhosphorIconsRegular.users,
    StrokeIconKind.file => PhosphorIconsRegular.fileText,
    StrokeIconKind.plus => PhosphorIconsRegular.plus,
    StrokeIconKind.close => PhosphorIconsRegular.x,
    StrokeIconKind.chevronLeft => PhosphorIconsRegular.caretLeft,
    StrokeIconKind.chevronRight => PhosphorIconsRegular.caretRight,
    StrokeIconKind.settings => PhosphorIconsRegular.gearSix,
    StrokeIconKind.refresh => PhosphorIconsRegular.arrowClockwise,
    StrokeIconKind.bell => PhosphorIconsRegular.bell,
    StrokeIconKind.phone => PhosphorIconsRegular.phone,
    StrokeIconKind.camera => PhosphorIconsRegular.camera,
    StrokeIconKind.alert => PhosphorIconsRegular.warningCircle,
    StrokeIconKind.clock => PhosphorIconsRegular.clock,
    StrokeIconKind.sunrise => PhosphorIconsRegular.sunHorizon,
    StrokeIconKind.sun => PhosphorIconsRegular.sun,
    StrokeIconKind.moon => PhosphorIconsRegular.moon,
    StrokeIconKind.medicine => PhosphorIconsRegular.pill,
    StrokeIconKind.mail => PhosphorIconsRegular.envelopeSimple,
    StrokeIconKind.download => PhosphorIconsRegular.downloadSimple,
    StrokeIconKind.eye => PhosphorIconsRegular.eye,
    StrokeIconKind.link => PhosphorIconsRegular.link,
    StrokeIconKind.share => PhosphorIconsRegular.shareFat,
    StrokeIconKind.lock => PhosphorIconsRegular.lockSimple,
  };

  @override
  Widget build(BuildContext context) {
    final paintColor =
        color ??
        IconTheme.of(context).color ??
        Theme.of(context).colorScheme.onSurface;
    // Decorative by default: the control around it carries the label.
    return ExcludeSemantics(
      child: Icon(glyph(kind), size: size, color: paintColor),
    );
  }
}
