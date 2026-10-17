import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/format/pet_names.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/paws_widgets.dart';
import 'package:pawsitive_sync/core/widgets/care_tab_builder.dart';
import 'package:pawsitive_sync/core/widgets/care_widgets.dart';
import 'package:pawsitive_sync/core/widgets/pro_lock.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/data/firebase_setup.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:pawsitive_sync/domain/paywall_reason.dart';
import 'package:pawsitive_sync/ui/account/account_sheet.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_view_model.dart';
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
    final text = Theme.of(context).textTheme;
    final spacing = context.paws.spacing;
    final people = care.members.length;
    // v14 shows the latest handful; the full history lives in Reports.
    final recent = activity.take(12).toList();
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: carePagePaddingOf(context),
          children: [
            CarePageHeader(
              title: 'Household',
              subtitle: care.isConnected
                  ? '${petNameList(care.pets)} · $people '
                        '${people == 1 ? 'person' : 'people'}'
                  : householdPetSubtitle(care.pets),
              action: CareSettingsButton(
                onPressed: () => context.push(AppRoutes.settings),
              ),
            ),
            SizedBox(height: spacing.xxl),
            // People first, invite as the last row of the same list: who is
            // here and how to add someone read as one thing.
            const CareSectionHeader('People'),
            const SizedBox(height: 10),
            SurfaceCard(
              child: Column(
                children: [
                  for (final member in care.members)
                    _MemberRow(
                      member: member,
                      onManage:
                          care.canManageHousehold &&
                              care.isConnected &&
                              !member.isYou &&
                              member.role != MemberRole.owner
                          ? () => _manageMember(context, care, member)
                          : null,
                    ),
                  _InviteRow(
                    enabled: care.canManageHousehold,
                    locked: care.canManageHousehold && !care.canInviteHousehold,
                    // The first address typed in setup, until it's sent.
                    pendingEmail: _pendingInvite(context),
                    onPressed: () {
                      final pending = _pendingInvite(context, listen: false);
                      if (care.canInviteHousehold) {
                        // Logged as nav.push to=/invite.
                        context.push(
                          pending == null
                              ? AppRoutes.invite
                              : Uri(
                                  path: AppRoutes.invite,
                                  queryParameters: {'email': pending},
                                ).toString(),
                        );
                      } else {
                        context.push(
                          AppRoutes.paywallWith(
                            reason: PaywallReason.invite.queryValue,
                            from: 'invite',
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // The trust promise sits next to the people it is about.
            Padding(
              padding: EdgeInsets.symmetric(horizontal: spacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: StrokeIcon(
                      StrokeIconKind.lock,
                      size: 14,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      !care.canManageHousehold
                          ? 'Private to your household. Ask the owner to '
                                'invite people.'
                          : people <= 1
                          ? 'Private to you. Every dose is logged with who '
                                'gave it and when.'
                          : 'Private to your household. Only these $people '
                                'people can see your pets’ records, and every '
                                'change is logged with who made it.',
                      style: text.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (!care.isConnected)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: () => context.push(AppRoutes.join),
                  style: TextButton.styleFrom(
                    foregroundColor: scheme.primary,
                    padding: EdgeInsets.symmetric(horizontal: spacing.xs),
                  ),
                  child: const Text('Have an invite code? Join a household'),
                ),
              ),
            SizedBox(height: spacing.xxl),
            const CareSectionHeader('Recent activity'),
            const SizedBox(height: 4),
            if (recent.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: spacing.xs,
                  vertical: 8,
                ),
                child: Text(
                  'When anyone here logs a dose, it shows up with their name '
                  'and the time.',
                  style: text.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              for (var i = 0; i < recent.length; i++)
                _ActivityRow(
                  item: recent[i],
                  showDivider: i != recent.length - 1,
                ),
            if (people <= 1) ...[
              const SizedBox(height: 20),
              _SharingSteps(petName: care.primaryPet?.name ?? 'your pet'),
            ],
            const SizedBox(height: 12),
            _PlanCard(
              isPro: care.isPro,
              // billing.paywall.opened reason=settings from=household_plan.
              onSeePro: () => context.push(
                AppRoutes.paywallWith(
                  reason: 'settings',
                  from: 'household_plan',
                ),
              ),
            ),
            const SizedBox(height: 12),
            const _BackupRow(),
          ],
        ),
      ),
    );
  }
}

/// Shown while nobody else has joined: what sharing does, in three steps,
/// so the invite row above isn't a mystery button.
class _SharingSteps extends StatelessWidget {
  const _SharingSteps({required this.petName});

  final String petName;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final paws = context.paws;
    final steps = [
      (StrokeIconKind.mail, 'Invite by email, or share a link'),
      (StrokeIconKind.phone, 'They join on their own phone'),
      (
        StrokeIconKind.userCheck,
        'Every dose shows who gave it and when, so nobody doubles up',
      ),
    ];
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text('How sharing works', style: text.headlineSmall),
          ),
          const SizedBox(height: 4),
          Text(
            'One log for everyone who looks after $petName.',
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          for (final (icon, line) in steps)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: paws.surfaces.selected,
                      shape: BoxShape.circle,
                    ),
                    child: StrokeIcon(icon, size: 15, color: paws.brandDark),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Text(line, style: text.bodyMedium),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// "Free plan" with "See Pro", or "Gave It Pro" for the whole household.
class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.isPro, required this.onSeePro});

  final bool isPro;
  final VoidCallback onSeePro;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      child: Row(
        children: [
          Icon(Icons.auto_awesome_outlined, size: 20, color: scheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isPro ? 'Gave It Pro' : 'Free plan',
                  style: text.labelLarge,
                ),
                Text(
                  isPro
                      ? 'Covers your whole household'
                      : 'Just you, on this phone. Pro lets partners and '
                            'sitters log doses on their own phones.',
                  style: text.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (!isPro) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: onSeePro,
              style: TextButton.styleFrom(
                backgroundColor: context.paws.surfaces.subtle,
                foregroundColor: scheme.onSurface,
                minimumSize: const Size(44, 44),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: const StadiumBorder(),
                textStyle: text.labelLarge?.copyWith(fontSize: 14),
              ),
              child: const Text('See Pro'),
            ),
          ],
        ],
      ),
    );
  }
}

/// "Back up your household" / "Backed up · Saved to sam@…" (v14). Hidden
/// when sign-in isn't configured on this build.
class _BackupRow extends StatelessWidget {
  const _BackupRow();

  @override
  Widget build(BuildContext context) {
    if (!FirebaseSetup.isReady) return const SizedBox.shrink();
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.userChanges(),
      initialData: FirebaseAuth.instance.currentUser,
      builder: (context, snapshot) {
        final user = snapshot.data;
        final text = Theme.of(context).textTheme;
        final scheme = Theme.of(context).colorScheme;
        final care = context.read<CareRepository>();
        return SurfaceCard(
          child: InkWell(
            onTap: () {
              if (user != null) {
                // Sign-out and details live in Settings.
                context.push(AppRoutes.settings);
                return;
              }
              // Saving needs the household on the server: shared households
              // already are; a solo phone only with Pro.
              if (!care.isConnected && !care.isPro) {
                AppLog.event('account.save_needs_pro');
                context.push(
                  AppRoutes.paywallWith(
                    reason: 'settings',
                    from: 'household_backup',
                  ),
                );
                return;
              }
              showAccountSheet(context, mode: AccountSheetMode.save);
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              child: Row(
                children: [
                  Icon(Icons.cloud_outlined, size: 20, color: scheme.onSurface),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user != null ? 'Backed up' : 'Back up your household',
                          style: text.labelLarge,
                        ),
                        Text(
                          user != null
                              ? 'Saved to ${user.email ?? 'your account'}'
                              : 'Sign in so the log survives a new phone',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  StrokeIcon(
                    StrokeIconKind.chevronRight,
                    size: 16,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                ],
              ),
            ),
          ),
        );
      },
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
  const _MemberRow({required this.member, this.onManage});

  final Member member;

  /// Owner-only "Change role / Remove"; null hides the control.
  final VoidCallback? onManage;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.paws;
    final text = Theme.of(context).textTheme;
    final browserSitter = member.role == MemberRole.sitter && !member.joined;
    final subtitle = [
      member.roleLabel,
      if (member.status != null && member.status!.isNotEmpty) member.status!,
    ].join(' · ');
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 64),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 12, 10),
        child: Row(
          children: [
            // v14: initials on a chip circle; a dashed ring for a sitter
            // link that hasn't opened the app.
            InitialsAvatar(
              label: member.initials,
              size: 40,
              fontSize: member.isYou ? 11 : 13,
              background: browserSitter
                  ? Colors.transparent
                  : tokens.surfaces.subtle,
              foreground: browserSitter
                  ? scheme.onSurfaceVariant
                  : scheme.onSurface,
              showPresence: member.active,
              dashed: browserSitter,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: member.isYou && member.name == 'You'
                              ? 'You'
                              : member.name,
                        ),
                        if (member.isYou && member.name != 'You')
                          TextSpan(
                            text: ' (you)',
                            style: TextStyle(
                              fontWeight: FontWeight.w400,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelLarge,
                  ),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (onManage != null)
              StrokeIcon(
                StrokeIconKind.chevronRight,
                size: 16,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
          ],
        ),
      ),
    );
    return Column(
      children: [
        if (onManage == null)
          row
        else
          Semantics(
            button: true,
            hint: 'Change role or remove',
            child: InkWell(
              key: ValueKey('manage-${member.id}'),
              onTap: onManage,
              child: row,
            ),
          ),
        Divider(height: 1, color: tokens.divider),
      ],
    );
  }
}

/// The first address typed in setup and not yet invited, if any. Optional:
/// screens built without setup state (tests, previews) just show none.
String? _pendingInvite(BuildContext context, {bool listen = true}) {
  try {
    return Provider.of<OnboardingViewModel>(
      context,
      listen: listen,
    ).invites.firstOrNull;
  } on ProviderNotFoundException {
    return null;
  }
}

/// The last row of the people list: an empty seat to fill. Owners only can
/// invite; everyone else sees it disabled with the reason under the card.
class _InviteRow extends StatelessWidget {
  const _InviteRow({
    required this.enabled,
    required this.locked,
    required this.onPressed,
    this.pendingEmail,
  });

  final bool enabled;

  /// The first address from setup, still to be invited.
  final String? pendingEmail;

  /// Free household: the tap opens the paywall, so the label says Pro.
  final bool locked;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final color = enabled ? scheme.primary : scheme.onSurfaceVariant;
    return TextButton(
      onPressed: enabled ? onPressed : null,
      style: TextButton.styleFrom(
        foregroundColor: color,
        minimumSize: const Size.fromHeight(64),
        padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 16, 10),
        alignment: AlignmentDirectional.centerStart,
        shape: const RoundedRectangleBorder(),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: CustomPaint(
              painter: DashedCirclePainter(
                color: color.withValues(alpha: 0.6),
                strokeWidth: 1.5,
              ),
              child: Center(
                child: StrokeIcon(StrokeIconKind.plus, size: 16, color: color),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                WithProLock(
                  locked: locked,
                  child: Text(
                    'Invite someone',
                    style: text.bodyLarge?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Text(
                  pendingEmail == null
                      ? 'Partner, family or a sitter'
                      : '$pendingEmail is waiting from setup',
                  style: text.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.item, required this.showDivider});

  final ActivityItem item;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.paws;
    final text = Theme.of(context).textTheme;
    // v14: green for given, amber for "not sure", chip for skipped.
    final (glyph, tint, ink, outcomeWords) = switch (item.outcome) {
      LogOutcome.given => (
        Icons.check_rounded,
        tokens.states.success.withValues(alpha: 0.1),
        tokens.states.success,
        'given',
      ),
      LogOutcome.uncertain => (
        Icons.question_mark_rounded,
        tokens.amber.withValues(alpha: 0.3),
        tokens.warning,
        'not sure',
      ),
      LogOutcome.skipped => (
        Icons.remove_rounded,
        tokens.surfaces.subtle,
        scheme.onSurface,
        'skipped',
      ),
    };
    final clock = item.time.isEmpty ? item.timeLabel : item.time;
    // Older days lead with the day so "8:05 AM" isn't read as today.
    final time = item.dayLabel == 'Today' || item.dayLabel.isEmpty
        ? clock
        : '${item.dayLabel}, $clock';
    final sentence = [
      item.actor,
      item.action,
      if (item.emphasis.isNotEmpty) item.emphasis,
    ].join(' ');
    return Semantics(
      label:
          '$sentence, $outcomeWords, $time'
          '${item.note == null ? '' : '. Note: ${item.note}'}',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: showDivider
              ? Border(
                  bottom: BorderSide(
                    color: scheme.onSurface.withValues(alpha: 0.07),
                  ),
                )
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
                child: Icon(glyph, size: 15, color: ink),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text.rich(
                        TextSpan(
                          style: text.bodyMedium?.copyWith(
                            fontSize: 14,
                            color: scheme.onSurface,
                          ),
                          children: [
                            TextSpan(
                              text: item.actor,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            TextSpan(text: ' ${item.action}'),
                            if (item.emphasis.isNotEmpty)
                              TextSpan(text: ' ${item.emphasis}'),
                          ],
                        ),
                      ),
                    ),
                    if (item.note != null) ...[
                      const SizedBox(height: 6),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: tokens.surfaces.card,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          child: Text(item.note!, style: text.bodySmall),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text(
                  time,
                  style: text.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
