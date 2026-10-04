import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/legal/app_links.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/paws_widgets.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/domain/paywall_reason.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

/// Shows the household's invite code and shares it.
class InviteScreen extends StatefulWidget {
  const InviteScreen({super.key});

  @override
  State<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends State<InviteScreen> {
  bool _copied = false;
  bool _linkCopied = false;
  bool _webLinkCopied = false;
  bool _connecting = false;
  bool _loadingWebLink = false;
  String? _error;
  String? _webLinkError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureShared());
  }

  Future<void> _ensureShared() async {
    if (!mounted || _connecting) return;
    final care = context.read<CareRepository>();
    if (care.isConnected) {
      await _loadWebLink();
      return;
    }
    setState(() {
      _connecting = true;
      _error = null;
    });
    final error = await care.connect();
    if (!mounted) return;
    setState(() {
      _connecting = false;
      _error = error;
    });
    // household.connected / connect_failed are logged by the repository.
    if (error == null) await _loadWebLink();
  }

  /// On open: the cached link only (no server call). A new link is created
  /// only from the explicit "Create browser link" sheet.
  Future<void> _loadWebLink() async {
    if (!mounted) return;
    await context.read<CareRepository>().loadSitterLink();
  }

  Future<void> _createWebLink() async {
    if (_loadingWebLink) return;
    final care = context.read<CareRepository>();
    // Logged as nav.push to=sitter_label (the sheet).
    final label = await showModalBottomSheet<String>(
      context: context,
      routeSettings: const RouteSettings(name: 'sitter_label'),
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _SitterLabelSheet(initial: care.defaultSitterLabel()),
    );
    if (!mounted) return;
    if (label == null) {
      AppLog.event('sitter.create_cancelled');
      return;
    }
    setState(() {
      _loadingWebLink = true;
      _webLinkError = null;
      _webLinkCopied = false;
    });
    final url = await care.ensureSitterWebLink(label: label, force: true);
    if (!mounted) return;
    setState(() {
      _loadingWebLink = false;
      _webLinkError = url == null ? care.lastError : null;
    });
  }

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static String _shortDate(DateTime day) {
    final local = day.toLocal();
    return '${_months[local.month - 1]} ${local.day}';
  }

  static String _petNames(CareRepository care) {
    final pets = care.pets.map((pet) => pet.name).toList();
    return pets.isEmpty
        ? 'our pet'
        : pets.length == 1
        ? pets.first
        : '${pets.sublist(0, pets.length - 1).join(', ')} and ${pets.last}';
  }

  String _sitterShareText(CareRepository care, SitterLink link) {
    final expires = link.expiresAt;
    final until = expires == null ? '' : ' until ${_shortDate(expires)}';
    return 'Here\'s your link to see and log ${_petNames(care)}\'s doses$until: ${link.url}';
  }

  Future<void> _copySitterLink(SitterLink link) async {
    await Clipboard.setData(ClipboardData(text: link.url));
    if (!mounted) return;
    AppLog.event('sitter.link_copied');
    setState(() => _webLinkCopied = true);
  }

  Future<void> _shareSitterLink(
    BuildContext buttonContext,
    CareRepository care,
    SitterLink link,
  ) async {
    AppLog.event('sitter.link_shared');
    final box = buttonContext.findRenderObject() as RenderBox?;
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: _sitterShareText(care, link),
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } catch (error, stack) {
      AppLog.error('sitter.link_share_failed', error, stack);
    }
  }

  String _message(CareRepository care) {
    final who = _petNames(care);
    final web = care.sitterLink?.url;
    if (web != null && web.isNotEmpty) {
      return 'Help me with $who’s medicine today — log doses here (no app needed):\n\n$web';
    }
    final link = AppLinks.householdJoinLink(care.inviteCode);
    final install = link == null
        ? 'Install Pawsitive from the App Store'
        : 'Get Pawsitive: $link';
    return 'Help me with $who’s medicine on Pawsitive, so no dose is missed or given twice.\n\n'
        '$install, tap “I have an invite code”, and enter: ${care.inviteCode}';
  }

  Future<void> _share(BuildContext buttonContext, CareRepository care) async {
    AppLog.event('invite.share_tapped');
    final box = buttonContext.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        text: _message(care),
        subject: 'Join our Pawsitive household',
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final care = context.watch<CareRepository>();
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.paws;
    final text = Theme.of(context).textTheme;
    final code = care.inviteCode;
    final joinLink = AppLinks.householdJoinLink(code);
    final ready = care.isConnected && code.isNotEmpty;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    onPressed: () => context.pop(),
                    icon: StrokeIcon(
                      StrokeIconKind.chevronLeft,
                      color: scheme.onSurface,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'Invite',
                      textAlign: TextAlign.center,
                      style: text.titleMedium,
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  children: [
                    Text(
                      'Invite someone who helps',
                      style: text.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'A partner, family member, or sitter. They see the same list and can mark doses as given.',
                      style: text.bodyLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 24),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: tokens.brandSoft,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            Text(
                              'YOUR INVITE CODE',
                              style: text.labelSmall?.copyWith(
                                color: tokens.brandDark,
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (ready)
                              Semantics(
                                label:
                                    'Invite code ${code.split('').join(' ')}',
                                child: SelectableText(
                                  code,
                                  textAlign: TextAlign.center,
                                  style: text.displaySmall?.copyWith(
                                    letterSpacing: 8,
                                    fontWeight: FontWeight.w600,
                                    color: tokens.brandDark,
                                  ),
                                ),
                              )
                            else if (_connecting)
                              const Padding(
                                padding: EdgeInsets.all(12),
                                child: CircularProgressIndicator(),
                              )
                            else
                              Text(
                                _error ?? 'Getting your code…',
                                textAlign: TextAlign.center,
                                style: text.bodyLarge?.copyWith(
                                  color: scheme.error,
                                ),
                              ),
                            const SizedBox(height: 12),
                            if (ready)
                              OutlinedButton.icon(
                                onPressed: () async {
                                  await Clipboard.setData(
                                    ClipboardData(text: code),
                                  );
                                  if (!mounted) return;
                                  AppLog.event('invite.copied');
                                  setState(() => _copied = true);
                                },
                                icon: Icon(
                                  _copied
                                      ? Icons.check_rounded
                                      : Icons.copy_rounded,
                                  size: 18,
                                ),
                                label: Text(_copied ? 'Copied' : 'Copy code'),
                              )
                            else if (!_connecting)
                              OutlinedButton(
                                onPressed: _ensureShared,
                                child: const Text('Try again'),
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (ready) ...[
                      const SizedBox(height: 24),
                      Text('Browser link for sitters', style: text.titleMedium),
                      const SizedBox(height: 8),
                      Text(
                        'No app install — open in Safari or Chrome, see today’s doses, tap I gave this.',
                        style: text.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (!care.canInviteHousehold)
                        _LockedSitterLink(
                          onTap: () {
                            AppLog.event('sitter.link_locked');
                            context.push(
                              AppRoutes.paywallWith(
                                reason: PaywallReason.invite.queryValue,
                              ),
                            );
                          },
                        )
                      else
                        _SitterLinkCard(
                          link: care.sitterLink,
                          loading: _loadingWebLink,
                          error: _webLinkError,
                          copied: _webLinkCopied,
                          expiryLabel: care.sitterLink?.expiresAt == null
                              ? null
                              : 'Works until ${_shortDate(care.sitterLink!.expiresAt!)}',
                          onCreate: _createWebLink,
                          onCopy: () => _copySitterLink(care.sitterLink!),
                          onShare: (buttonContext) => _shareSitterLink(
                            buttonContext,
                            care,
                            care.sitterLink!,
                          ),
                        ),
                      if (joinLink != null) ...[
                        const SizedBox(height: 24),
                        Text(
                          'App invite (partner / family)',
                          style: text.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'For people who will install the app — code is prefilled.',
                          style: text.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SurfaceCard(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SelectableText(
                                joinLink,
                                style: text.bodyMedium?.copyWith(
                                  color: tokens.brandDark,
                                ),
                              ),
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                onPressed: () async {
                                  await Clipboard.setData(
                                    ClipboardData(text: joinLink),
                                  );
                                  if (!mounted) return;
                                  AppLog.event('invite.link_copied');
                                  setState(() => _linkCopied = true);
                                },
                                icon: Icon(
                                  _linkCopied
                                      ? Icons.check_rounded
                                      : Icons.link_rounded,
                                  size: 18,
                                ),
                                label: Text(
                                  _linkCopied ? 'Link copied' : 'Copy app link',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                    const SizedBox(height: 24),
                    Text('How they join', style: text.titleMedium),
                    const SizedBox(height: 8),
                    SurfaceCard(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          const _Step(
                            number: 1,
                            text: 'Sitter: open the browser link. Partner: install the app.',
                          ),
                          const _Step(
                            number: 2,
                            text: 'They see today’s doses and who already logged.',
                          ),
                          const _Step(
                            number: 3,
                            text: 'They tap I gave this — everyone stays in sync.',
                            last: true,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Builder(
                builder: (buttonContext) => FilledButton.icon(
                  onPressed: ready ? () => _share(buttonContext, care) : null,
                  icon: StrokeIcon(
                    StrokeIconKind.share,
                    size: 20,
                    color: scheme.onPrimary,
                  ),
                  label: const Text('Share invite'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pro: the named browser link, or a button to create one.
class _SitterLinkCard extends StatelessWidget {
  const _SitterLinkCard({
    required this.link,
    required this.loading,
    required this.error,
    required this.copied,
    required this.expiryLabel,
    required this.onCreate,
    required this.onCopy,
    required this.onShare,
  });

  final SitterLink? link;
  final bool loading;
  final String? error;
  final bool copied;
  final String? expiryLabel;
  final VoidCallback onCreate;
  final VoidCallback onCopy;
  final void Function(BuildContext buttonContext) onShare;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final current = link;
    return SurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (loading)
            const Center(child: CircularProgressIndicator())
          else if (current != null) ...[
            Text(
              current.label.isEmpty ? 'Sitter link' : current.label,
              style: text.titleSmall,
            ),
            if (expiryLabel != null) ...[
              const SizedBox(height: 4),
              Text(
                expiryLabel!,
                style: text.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onCopy,
                    icon: Icon(
                      copied ? Icons.check_rounded : Icons.link_rounded,
                      size: 18,
                    ),
                    label: Text(copied ? 'Link copied' : 'Copy'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Builder(
                    builder: (buttonContext) => OutlinedButton.icon(
                      onPressed: () => onShare(buttonContext),
                      icon: const Icon(Icons.ios_share_rounded, size: 18),
                      label: const Text('Share'),
                    ),
                  ),
                ),
              ],
            ),
          ] else ...[
            if (error != null) ...[
              Text(
                error!,
                style: text.bodyMedium?.copyWith(color: scheme.error),
              ),
              const SizedBox(height: 12),
            ],
            OutlinedButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.link_rounded, size: 18),
              label: const Text('Create browser link'),
            ),
          ],
        ],
      ),
    );
  }
}

/// "Who is this link for?" — names the link so the owner can tell several
/// sitters apart. Returns the text on Create, null on dismiss.
class _SitterLabelSheet extends StatefulWidget {
  const _SitterLabelSheet({required this.initial});

  final String initial;

  @override
  State<_SitterLabelSheet> createState() => _SitterLabelSheetState();
}

class _SitterLabelSheetState extends State<_SitterLabelSheet> {
  late final TextEditingController _label = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  void _create() {
    FocusScope.of(context).unfocus();
    Navigator.of(context).pop(_label.text);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _label,
            autofocus: true,
            maxLength: CareRepository.sitterLabelMax,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _create(),
            onTapOutside: (_) => FocusScope.of(context).unfocus(),
            decoration: const InputDecoration(
              labelText: 'Who is this link for?',
              hintText: 'e.g. Sara — weekend sitter',
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _create,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}

/// Free tier: the sitter browser link is a Pro feature. Shown locked, and
/// the link is never requested from the server.
class _LockedSitterLink extends StatelessWidget {
  const _LockedSitterLink({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.paws;
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: 'Browser link for sitters, Pro',
      excludeSemantics: true,
      child: SurfaceCard(
        padding: EdgeInsets.zero,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(PawsRadii.cardValue),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  Icons.lock_outline_rounded,
                  color: scheme.onSurfaceVariant,
                ),
                const Spacer(),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: tokens.brandSoft,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    child: Text(
                      'Pro',
                      style: text.labelMedium?.copyWith(
                        color: tokens.brandDark,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.text, this.last = false});

  final int number;
  final String text;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final tokens = context.paws;
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: tokens.brandSoft,
            child: Text(
              '$number',
              style: theme.titleSmall?.copyWith(color: tokens.brandDark),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: theme.bodyLarge)),
        ],
      ),
    );
  }
}
