import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// A colored drawing from assets/art. It keeps its own colors.
class StoryArt extends StatelessWidget {
  const StoryArt(this.name, {super.key, this.size = 160});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/art/$name.svg',
      width: size,
      height: size,
      fit: BoxFit.contain,
      semanticsLabel: name,
    );
  }
}
