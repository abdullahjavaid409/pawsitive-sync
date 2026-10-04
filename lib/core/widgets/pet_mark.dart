import 'dart:io';

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

/// A pet's photo in a circle, or its drawn [PetMark] when there is none (or
/// the file can't be read). Decoded at display size, so a 512 px photo costs
/// only a few KB of memory per avatar.
class PetAvatar extends StatelessWidget {
  const PetAvatar({
    super.key,
    required this.species,
    required this.photoPath,
    this.photoVersion = 0,
    this.size = 72,
    this.artScale = 0.7,
  });

  final Species species;
  final String? photoPath;

  /// Changes whenever the file at [photoPath] is replaced.
  final int photoVersion;
  final double size;
  final double artScale;

  @override
  Widget build(BuildContext context) {
    final mark = PetMark(species: species, size: size, artScale: artScale);
    final path = photoPath;
    if (path == null) return mark;
    final pixels = (size * MediaQuery.devicePixelRatioOf(context)).round();
    return ClipOval(
      child: Image(
        image: ResizeImage(
          _VersionedFileImage(File(path), photoVersion),
          width: pixels,
          height: pixels,
        ),
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => mark,
      ),
    );
  }
}

/// [FileImage] whose cache identity includes a version, so replacing the
/// photo at the same path shows the new picture instead of the cached one.
class _VersionedFileImage extends FileImage {
  const _VersionedFileImage(super.file, this.version);

  final int version;

  @override
  bool operator ==(Object other) =>
      other is _VersionedFileImage &&
      other.file.path == file.path &&
      other.version == version &&
      other.scale == scale;

  @override
  int get hashCode => Object.hash(file.path, version, scale);
}
