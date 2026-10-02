import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';
import 'package:pawsitive_sync/domain/models.dart';

/// A simple drawn pet, so a screen has a face and not only words.
class PetMark extends StatelessWidget {
  const PetMark({super.key, required this.species, this.size = 72});

  final Species species;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tokens = context.paws;
    final asset = switch (species) {
      Species.cat => 'assets/marks/cat.svg',
      Species.dog => 'assets/marks/dog.svg',
      Species.rabbit || Species.other => null,
    };
    final label = switch (species) {
      Species.cat => 'Cat',
      Species.dog => 'Dog',
      Species.rabbit => 'Rabbit',
      Species.other => 'Pet',
    };

    return Semantics(
      label: label,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: tokens.brandSoft,
          shape: BoxShape.circle,
        ),
        child: asset == null
            ? StrokeIcon(
                StrokeIconKind.paw,
                size: size * 0.42,
                color: tokens.brandDark,
              )
            : SvgPicture.asset(
                asset,
                width: size * 0.7,
                height: size * 0.7,
                colorFilter: ColorFilter.mode(tokens.brandDark, BlendMode.srcIn),
              ),
      ),
    );
  }
}
