import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/domain/models.dart';

/// A simple drawn pet, so a screen has a face and not only words.
class PetMark extends StatelessWidget {
  const PetMark({
    super.key,
    required this.species,
    this.size = 72,
    this.artScale = 0.7,
  });

  final Species species;
  final double size;
  final double artScale;

  @override
  Widget build(BuildContext context) {
    final tokens = context.paws;
    final asset = switch (species) {
      Species.cat => 'assets/marks/cat.svg',
      Species.dog => 'assets/marks/dog.svg',
      Species.rabbit => 'assets/marks/rabbit.svg',
      Species.other => 'assets/marks/paw.svg',
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
        child: SvgPicture.asset(
          asset,
          width: size * artScale,
          height: size * artScale,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}
