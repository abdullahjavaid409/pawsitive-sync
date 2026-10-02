import 'package:flutter/material.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';

/// One large picture with a one-word caption, so a step is clear before the text.
class StepPicture extends StatelessWidget {
  const StepPicture({
    super.key,
    required this.icon,
    required this.caption,
    this.size = 72,
  });

  final StrokeIconKind icon;
  final String caption;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tokens = context.paws;
    final text = Theme.of(context).textTheme;
    return Column(
      children: [
        Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: tokens.brandSoft,
            shape: BoxShape.circle,
          ),
          child: StrokeIcon(icon, size: size * 0.42, color: tokens.brandDark),
        ),
        const SizedBox(height: 8),
        Text(
          caption,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
