import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

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
}

/// Paints a bundled stroke icon in one color.
///
/// Stroke weight lives in the SVG asset, so this widget only tints it.
class StrokeIcon extends StatelessWidget {
  const StrokeIcon(this.kind, {super.key, this.size = 24, this.color});

  final StrokeIconKind kind;
  final double size;
  final Color? color;

  String get _asset {
    final name = switch (kind) {
      StrokeIconKind.chevronLeft => 'chevron_left',
      StrokeIconKind.chevronRight => 'chevron_right',
      _ => kind.name,
    };
    return 'assets/icons/$name.svg';
  }

  @override
  Widget build(BuildContext context) {
    final paintColor =
        color ??
        IconTheme.of(context).color ??
        Theme.of(context).colorScheme.onSurface;
    return SvgPicture.asset(
      _asset,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(paintColor, BlendMode.srcIn),
      excludeFromSemantics: true,
    );
  }
}
