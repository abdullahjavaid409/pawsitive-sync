import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/legal/app_links.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/paws_widgets.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
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
  String? _webLink;
  String? _webLinkError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureShared());
  }

  Future<void> _ensureShared() async {
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
    if (error != null) {
      AppLog.event('invite.connect_failed', {'error': error});
    } else {
      AppLog.event('invite.connect_ready');
      await _loadWebLink();
    }
  }

  Future<void> _loadWebLink() async {
    final care = context.read<CareRepository>();
    if (!care.canInviteHousehold || !care.isConnected) return;
    setState(() => _loadingWebLink = true);
    final link = await care.ensureSitterWebLink();
    if (!mounted) return;
    setState(() {
      _loadingWebLink = false;
      _webLink = link;
      _webLinkError = link == null ? care.lastError : null;
    });
  }

  String _message(CareRepository care) {
    final pets = care.pets.map((pet) => pet.name).toList();
    final who = pets.isEmpty
        ? 'our pet'
        : pets.length == 1
        ? pets.first
        : '${pets.sublist(0, pets.length - 1).join(', ')} and ${pets.last}';
    final web = _webLink;
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
                      SurfaceCard(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_loadingWebLink)
                              const Center(child: CircularProgressIndicator())
                            else if (_webLink != null)
                              SelectableText(
                                _webLink!,
                                style: text.bodyMedium?.copyWith(
                                  color: tokens.brandDark,
                                ),
                              )
                            else
                              Text(
                                _webLinkError ?? 'Could not create a browser link. Try again.',
                                style: text.bodyMedium?.copyWith(
                                  color: scheme.error,
                                ),
                              ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: _webLink == null && !_loadingWebLink
                                  ? _loadWebLink
                                  : _webLink == null
                                  ? null
                                  : () async {
                                      await Clipboard.setData(
                                        ClipboardData(text: _webLink!),
                                      );
                                      if (!mounted) return;
                                      AppLog.event('invite.web_link_copied');
                                      setState(() => _webLinkCopied = true);
                                    },
                              icon: Icon(
                                _webLinkCopied
                                    ? Icons.check_rounded
                                    : Icons.link_rounded,
                                size: 18,
                              ),
                              label: Text(
                                _webLink == null && !_loadingWebLink
                                    ? 'Try again'
                                    : _webLinkCopied
                                    ? 'Link copied'
                                    : 'Copy browser link',
                              ),
                            ),
                          ],
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
