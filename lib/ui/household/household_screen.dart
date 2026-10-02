import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/paws_widgets.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:provider/provider.dart';

/// Lists household members and the doses logged today.
class HouseholdScreen extends StatelessWidget {
  const HouseholdScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final care = context.watch<CareRepository>();
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.paws;
    final text = Theme.of(context).textTheme;
    final names = care.pets.map((pet) => pet.name).join(' and ');

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Household', style: text.displaySmall),
                  Text(
                    'Everyone caring for $names',
                    style: text.bodyLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SurfaceCard(
              child: Column(
                children: [
                  for (var i = 0; i < care.members.length; i++)
                    _MemberRow(
                      member: care.members[i],
                      showDivider: i != care.members.length - 1,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () {
                if (care.isPro) {
                  context.push(AppRoutes.invite);
                } else {
                  context.push(AppRoutes.paywall);
                }
              },
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                foregroundColor: tokens.brandDark,
              ),
              icon: StrokeIcon(
                StrokeIconKind.plus,
                size: 18,
                color: tokens.brandDark,
              ),
              label: const Text('Invite someone'),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 24, 8, 8),
              child: Row(
                children: [
                  Text('ACTIVITY · TODAY', style: text.labelSmall),
                  const Spacer(),
                  Text(
                    'Filter',
                    style: text.bodyMedium?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            if (care.activity.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Doses logged today will show up here.',
                  style: text.bodyLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              for (final item in care.activity) _ActivityRow(item: item),
          ],
        ),
      ),
    );
  }

}

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.member, required this.showDivider});

  final Member member;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.paws;
    final text = Theme.of(context).textTheme;
    final (background, foreground) = switch (member.avatarTone) {
      AvatarTone.brand => (scheme.primary, scheme.onPrimary),
      AvatarTone.soft => (tokens.brandSoft, tokens.brandDark),
      AvatarTone.neutral => (tokens.neutral, scheme.onSurface),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: showDivider
            ? Border(bottom: BorderSide(color: tokens.divider))
            : null,
      ),
      child: Row(
        children: [
          InitialsAvatar(
            label: member.initials,
            size: 36,
            fontSize: member.isYou ? 12 : 15,
            background: background,
            foreground: foreground,
            showPresence: member.active,
            dashed: member.role == MemberRole.sitter,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.name,
                  style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
                ),
                if (member.status != null)
                  Text(
                    member.status!,
                    style: text.bodySmall?.copyWith(
                      color: member.active
                          ? tokens.brandDark
                          : scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (member.role == MemberRole.sitter)
            DecoratedBox(
              decoration: BoxDecoration(
                color: tokens.neutral,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  member.roleLabel,
                  style: text.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
              ),
            )
          else
            Text(member.roleLabel, style: text.bodyMedium),
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.item});

  final ActivityItem item;

  @override
  Widget build(BuildContext context) {
    final care = context.read<CareRepository>();
    final member = care.memberById(item.memberId);
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.paws;
    final text = Theme.of(context).textTheme;
    final (background, foreground) = switch (member.avatarTone) {
      AvatarTone.brand => (scheme.primary, scheme.onPrimary),
      AvatarTone.soft => (tokens.brandSoft, tokens.brandDark),
      AvatarTone.neutral => (tokens.neutral, scheme.onSurface),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InitialsAvatar(
            label: member.initials,
            size: 32,
            background: background,
            foreground: foreground,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    style: text.titleSmall?.copyWith(
                      fontWeight: FontWeight.w400,
                    ),
                    children: [
                      TextSpan(
                        text: item.actor,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      TextSpan(text: ' ${item.action}'),
                      if (item.emphasis.isNotEmpty)
                        TextSpan(
                          text: ' ${item.emphasis}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                    ],
                  ),
                ),
                if (item.note != null) ...[
                  const SizedBox(height: 4),
                  SurfaceCard(
                    radius: 10,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Text(
                      item.note!,
                      style: text.titleSmall?.copyWith(
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Text(item.timeLabel, style: text.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
