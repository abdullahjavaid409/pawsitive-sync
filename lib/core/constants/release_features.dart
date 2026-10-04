import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';

/// Version shown in What's New and release notes. Keep in sync with pubspec.
abstract final class ReleaseFeatures {
  static const version = '1.0.0';

  static const items = <ReleaseFeature>[
    ReleaseFeature(
      icon: StrokeIconKind.people,
      title: 'Check before you give',
      description: 'When doses are due and others help care, Today reminds you to confirm before logging — so nothing is given twice.',
    ),
    ReleaseFeature(
      icon: StrokeIconKind.alert,
      title: 'Not sure if given',
      description: 'Mark a dose as uncertain when someone may have already given it. Your household sees it before the next person acts.',
    ),
    ReleaseFeature(
      icon: StrokeIconKind.link,
      title: 'Sitter browser link',
      description: 'Share a browser link from Invite — sitters log doses without installing the app. Partners can still join with the app invite.',
    ),
    ReleaseFeature(
      icon: StrokeIconKind.calendar,
      title: 'Course length & coming up',
      description: 'Set 7, 14, or 30 days for short-term meds. Vet visits, vaccines, and refills appear on Today under Coming up.',
    ),
    ReleaseFeature(
      icon: StrokeIconKind.paw,
      title: 'Free vs Pro — honest split',
      description: 'Free: one pet, dose logging, double-dose safety, reminders. Pro: up to 10 pets, household invites, low-supply alerts, vet export.',
    ),
  ];
}

class ReleaseFeature {
  const ReleaseFeature({
    required this.icon,
    required this.title,
    required this.description,
  });

  final StrokeIconKind icon;
  final String title;
  final String description;
}
