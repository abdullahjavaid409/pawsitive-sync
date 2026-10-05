import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/format/pet_names.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/paws_widgets.dart';
import 'package:pawsitive_sync/core/widgets/care_tab_builder.dart';
import 'package:pawsitive_sync/core/widgets/care_widgets.dart';
import 'package:pawsitive_sync/core/widgets/pro_lock.dart';
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
                    // Only the owner invites; others see why instead of a
                    // button that would fail.
                    onPressed: !care.canManageHousehold
                        ? null
                        : () {
                            if (care.canInviteHousehold) {
                              // Logged as nav.push to=/invite.
                              context.push(AppRoutes.invite);
                            } else {
                              context.push(
                                AppRoutes.paywallWith(
                                  reason: PaywallReason.invite.queryValue,
                                  from: 'invite',
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
                    label: WithProLock(
                      locked:
                          care.canManageHousehold && !care.canInviteHousehold,
                      onDark: true,
                      child: const Text('Invite someone'),
                    ),
                  ),
                  if (!care.canManageHousehold) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Ask the owner to invite people.',
                      textAlign: TextAlign.center,
                      style: text.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
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
                        onManage:
                            care.canManageHousehold &&
                                care.isConnected &&
                                !care.members[i].isYou &&
                                care.members[i].role != MemberRole.owner
                            ? () =>
                                  _manageMember(context, care, care.members[i])
                            : null,
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

/// Owner: change a member’s role or remove them. Each step confirms and
/// reports the result in plain words.
Future<void> _manageMember(
  BuildContext context,
  CareRepository care,
  Member member,
) async {
  // A browser sitter link has no app: it can be removed, not re-roled.
  final browserSitter = member.role == MemberRole.sitter && !member.joined;
  final target = member.role == MemberRole.sitter
      ? MemberRole.caregiver
      : MemberRole.sitter;
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    routeSettings: const RouteSettings(name: 'member_actions'),
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              '${member.name} · ${member.roleLabel}',
              style: Theme.of(sheet).textTheme.titleMedium,
            ),
          ),
          if (!browserSitter)
            ListTile(
              title: Text(
                target == MemberRole.caregiver
                    ? 'Make caregiver'
                    : 'Make sitter',
              ),
              subtitle: Text(
                target == MemberRole.caregiver
                    ? 'Can log doses, refill, and edit pets and medicines.'
                    : 'Can only see and log doses.',
              ),
              onTap: () => Navigator.of(sheet).pop('role'),
            ),
          ListTile(
            title: Text(
              'Remove from household',
              style: TextStyle(color: Theme.of(sheet).colorScheme.error),
            ),
            subtitle: const Text('Their past doses stay in the history.'),
            onTap: () => Navigator.of(sheet).pop('remove'),
          ),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return;
  String? error;
  String done;
  if (choice == 'role') {
    error = await care.changeMemberRole(member.id, target);
    done =
        '${member.name} is now a ${target == MemberRole.caregiver ? 'caregiver' : 'sitter'}.';
  } else {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('Remove ${member.name}?'),
        content: Text(
          member.paysForPro
              ? '${member.name} pays for Pro. If no one else does, the household goes back to Free. They lose access right away; their past doses stay.'
              : 'They lose access right away. Their past doses stay in the history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    error = await care.removeMember(member.id);
    done = '${member.name} was removed.';
  }
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(error ?? done)));
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.member,
    required this.showDivider,
    this.onManage,
  });

  final Member member;
  final bool showDivider;

  /// Owner-only "Change role / Remove"; null hides the control.
  final VoidCallback? onManage;

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
          if (onManage != null)
            IconButton(
              tooltip: 'Manage ${member.name}',
              onPressed: onManage,
              icon: Icon(Icons.more_horiz, color: scheme.onSurfaceVariant),
            ),
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
