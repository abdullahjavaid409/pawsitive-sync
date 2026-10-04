import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/format/pet_names.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/paws_widgets.dart';
import 'package:pawsitive_sync/core/widgets/care_tab_builder.dart';
import 'package:pawsitive_sync/core/widgets/care_widgets.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:pawsitive_sync/domain/paywall_reason.dart';
import 'package:provider/provider.dart';

/// Lists household members and the doses logged today.
class HouseholdScreen extends StatelessWidget {
  const HouseholdScreen({super.key});

  // Tab screen: rebuilds on data changes only while visible.
  @override
  Widget build(BuildContext context) => CareTabBuilder(builder: _build);

  Widget _build(BuildContext context, CareRepository care) {
    // Built once per frame: each call formats up to 40 log rows.
    final activity = care.activity;
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.paws;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: carePagePadding,
          children: [
            CarePageHeader(
              title: 'Household',
              subtitle: householdPetSubtitle(care.pets),
              action: IconButton(
                tooltip: 'Settings',
                onPressed: () => context.push(AppRoutes.settings),
                style: IconButton.styleFrom(
                  backgroundColor: scheme.surfaceContainerLowest,
                  side: BorderSide(color: scheme.outlineVariant),
                  minimumSize: const Size(44, 44),
                ),
                icon: StrokeIcon(
                  StrokeIconKind.settings,
                  size: 21,
                  color: scheme.onSurface,
                ),
              ),
            ),
            if (care.pets.isNotEmpty) ...[
              const SizedBox(height: 16),
              // Whose care this household shares — photos when set.
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  for (final pet in care.pets)
                    Semantics(
                      label: pet.name,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          PetPortrait(pet, size: 44),
                          const SizedBox(height: 4),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 64),
                            child: ExcludeSemantics(
                              child: Text(
                                pet.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: text.labelMedium,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: tokens.brandSoft,
                borderRadius: BorderRadius.circular(28),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const CareIllustration('onboarding-care', height: 112),
                  const SizedBox(height: 16),
                  Text(
                    'One team. One shared routine.',
                    style: text.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Everyone sees who gave each dose, so handovers feel simple.',
                    style: text.bodyLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () {
                      if (care.canInviteHousehold) {
                        AppLog.event('invite.opened');
                        context.push(AppRoutes.invite);
                      } else {
                        AppLog.event('invite.blocked');
                        context.push(
                          AppRoutes.paywallWith(
                            reason: PaywallReason.invite.queryValue,
                          ),
                        );
                      }
                    },
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    icon: StrokeIcon(
                      StrokeIconKind.plus,
                      size: 18,
                      color: scheme.onPrimary,
                    ),
                    label: const Text('Invite someone'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            CareSectionHeader(
              'Your care circle',
              action:
                  '${care.members.length} ${care.members.length == 1 ? 'person' : 'people'}',
            ),
            const SizedBox(height: 12),
            if (care.members.isNotEmpty)
              SurfaceCard(
                radius: 20,
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
            if (!care.isConnected) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => context.push(AppRoutes.join),
                child: const Text('Have an invite code? Join a household'),
              ),
            ],
            const SizedBox(height: 24),
            const CareSectionHeader('Recent activity'),
            const SizedBox(height: 16),
            if (activity.isEmpty)
              SurfaceCard(
                radius: 20,
                padding: const EdgeInsets.all(20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    StrokeIcon(
                      StrokeIconKind.clock,
                      size: 24,
                      color: tokens.brandDark,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Your shared story starts here',
                            style: text.titleMedium,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Logged doses and care notes will appear here for everyone.',
                            style: text.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            else
              for (final item in activity) _ActivityRow(item: item),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        border: showDivider
            ? Border(bottom: BorderSide(color: tokens.divider))
            : null,
      ),
      child: Row(
        children: [
          InitialsAvatar(
            label: member.initials,
            size: 42,
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
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 12),
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
