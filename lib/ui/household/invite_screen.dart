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
import 'package:pawsitive_sync/data/household_api.dart' show SitterLinkInfo;
import 'package:pawsitive_sync/domain/paywall_reason.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_view_model.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pawsitive_sync/core/widgets/system_menu.dart';

/// Shows the household’s invite code and shares it.
class InviteScreen extends StatefulWidget {
  const InviteScreen({super.key, this.initialEmail});

  /// From setup's household step: the first address typed there.
  final String? initialEmail;

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
    final email = widget.initialEmail?.trim() ?? '';
    if (email.isNotEmpty) {
      _via = _Send.email;
      _contact.text = email;
      // "sara@…" → "Sara" as a starting name they can change.
      final local = email.split('@').first.split(RegExp(r'[._+-]')).first;
      if (local.isNotEmpty) {
        _name.text = local[0].toUpperCase() + local.substring(1);
      }
    }
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

  bool _loadingLinks = false;
  bool _linksShown = false;

  /// Owner: fetches the working links on request (no call on screen open).
  Future<void> _showLinks() async {
    if (_loadingLinks) return;
    setState(() => _loadingLinks = true);
    final error = await context.read<CareRepository>().loadSitterLinks();
    if (!mounted) return;
    setState(() {
      _loadingLinks = false;
      _linksShown = error == null;
    });
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
  }

  bool _rotating = false;

  /// Owner: confirm, then swap the code. The old code stops working.
  Future<void> _newCode() async {
    if (_rotating) return;
    final care = context.read<CareRepository>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Make a new code?'),
        content: const Text(
          'The current code stops working right away. People already in the household stay in.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            child: const Text('New code'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _rotating = true);
    final error = await care.rotateInvite();
    if (!mounted) return;
    setState(() {
      _rotating = false;
      _copied = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error ?? 'New code ready. The old one no longer works.'),
      ),
    );
  }

  Future<void> _revoke(SitterLinkInfo link) async {
    final care = context.read<CareRepository>();
    final label = link.label.isEmpty ? 'this link' : link.label;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('Revoke $label?'),
        content: const Text(
          'It stops working right away. Doses already logged with it stay.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final error = await care.revokeSitterLink(link.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(error ?? 'Link revoked.')));
  }

  /// "Expires in 5 days" under the code; null when unknown.
  static String? _expiryText(CareRepository care) {
    if (care.inviteExpiresAt == null) return null;
    if (care.inviteExpired) return 'This code expired. Make a new one.';
    final days = care.inviteDaysLeft ?? 0;
    if (days <= 1) return 'Expires within a day';
    return 'Expires in $days days';
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
    return 'Here’s your link to see and log ${_petNames(care)}\'s doses$until: ${link.url}';
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

  /// v14 InviteFlow, one question per screen: who (name + how to send),
  /// what they can do (family or sitter, and for how long), a review with
  /// an optional note, then the code or link that was sent.
  static const _steps = 4;
  int _step = 0;

  final _name = TextEditingController();
  final _contact = TextEditingController();
  final _note = TextEditingController();
  _Send _via = _Send.text;
  _Audience? _audience;
  int _days = 7;
  bool _sending = false;

  /// The longest note sent along with the invite.
  static const noteMax = 140;

  @override
  void dispose() {
    _name.dispose();
    _contact.dispose();
    _note.dispose();
    super.dispose();
  }

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  /// Null when the address or number is fine (or left blank: the composer
  /// then opens with no recipient and they pick one there).
  String? get _contactError {
    final value = _contact.text.trim();
    if (value.isEmpty || _via == _Send.link) return null;
    if (_via == _Send.email) {
      return _emailPattern.hasMatch(value)
          ? null
          : 'Enter a full email, like sara@example.com';
    }
    final digits = value.replaceAll(RegExp(r'\D'), '');
    final allowed = RegExp(r'^\+?[\d\s().-]+$').hasMatch(value);
    return allowed && digits.length >= 7 ? null : 'Check the phone number';
  }

  String get _firstName => _name.text.trim().split(RegExp(r'\s+')).first;

  void _go(int step) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _step = step);
  }

  /// `Hi Sara! <note>` above the invite itself.
  String _greeting() {
    final note = _note.text.trim();
    return 'Hi $_firstName!${note.isEmpty ? '' : ' $note'}';
  }

  String _familyMessage(CareRepository care) {
    final link = AppLinks.householdJoinLink(care.inviteCode);
    final install = link == null
        ? 'Install Gave It from the App Store'
        : 'Get Gave It: $link';
    return '${_greeting()}\n\nHelp me with ${_petNames(care)}’s medicine, so '
        'no dose is missed or given twice.\n\n$install, tap “I have an invite '
        'code”, and enter: ${care.inviteCode}';
  }

  String _sitterMessage(CareRepository care, {String? url, DateTime? until}) {
    final end = until ?? DateTime.now().add(Duration(days: _days));
    return '${_greeting()}\n\nHere’s your link to see and log '
        '${_petNames(care)}’s doses until ${_shortDate(end)} (no app '
        'needed):\n\n${url ?? '[link made when you send]'}';
  }

  /// The setup address is no longer "waiting" once it's been sent.
  void _clearPending(String to) {
    if (!mounted || to.isEmpty) return;
    try {
      context.read<OnboardingViewModel>().inviteSent(to);
    } on ProviderNotFoundException {
      // No setup state here (tests, previews): nothing was waiting.
    }
  }

  /// Opens Mail or Messages with the text filled in. Falls back to the
  /// share sheet when there's no mail account / SMS (e.g. simulator, iPad).
  Future<void> _deliver(BuildContext buttonContext, String message) async {
    final to = _contact.text.trim();
    final uri = switch (_via) {
      _Send.email => Uri.parse(
        'mailto:${Uri.encodeComponent(to)}'
        '?subject=${Uri.encodeComponent('Help with our pet’s medicine')}'
        '&body=${Uri.encodeComponent(message)}',
      ),
      // "?&body=" is read by both iOS Messages and Android.
      _Send.text => Uri.parse(
        'sms:${to.replaceAll(RegExp(r'[^\d+]'), '')}'
        '?&body=${Uri.encodeComponent(message)}',
      ),
      _Send.link => null,
    };
    if (uri != null) {
      try {
        if (await launchUrl(uri)) {
          AppLog.event('invite.sent', {'via': _via.name});
          _clearPending(to);
          return;
        }
      } catch (error, stack) {
        AppLog.error('invite.compose_failed', error, stack);
      }
      AppLog.event('invite.compose_unavailable', {'via': _via.name});
    }
    if (!buttonContext.mounted) return;
    final box = buttonContext.findRenderObject() as RenderBox?;
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: message,
          subject: 'Help with our pet’s medicine',
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
      AppLog.event('invite.sent', {'via': 'share'});
      _clearPending(to);
    } catch (error, stack) {
      AppLog.error('invite.share_failed', error, stack);
    }
  }

  /// Review → Send. Sitter links are only created here, on purpose (one
  /// server call, never on screen open).
  Future<void> _send(BuildContext buttonContext, CareRepository care) async {
    if (_sending) return;
    final audience = _audience!;
    if (audience == _Audience.family) {
      AppLog.event('invite.share_tapped', {'via': _via.name});
      await _deliver(buttonContext, _familyMessage(care));
      if (mounted) _go(3);
      return;
    }
    setState(() {
      _sending = true;
      _webLinkError = null;
      _webLinkCopied = false;
    });
    final url = await care.ensureSitterWebLink(
      label: _name.text,
      force: true,
      days: _days,
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (url == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(care.lastError ?? 'Couldn’t make the link. Try again.'),
        ),
      );
      return;
    }
    if (buttonContext.mounted) {
      await _deliver(
        buttonContext,
        _sitterMessage(care, url: url, until: care.sitterLink?.expiresAt),
      );
    }
    if (mounted) _go(3);
  }

  static const _dayChoices = [3, 7, 14, 30];

  static String _daysLabel(int days) => switch (days) {
    3 => '3 days',
    7 => '1 week',
    14 => '2 weeks',
    _ => '$days days',
  };

  @override
  Widget build(BuildContext context) {
    final care = context.watch<CareRepository>();
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.paws;
    final text = Theme.of(context).textTheme;
    final code = care.inviteCode;
    final joinLink = AppLinks.householdJoinLink(code);
    final ready = care.isConnected && code.isNotEmpty;
    final audience = _audience;
    final step = _step;
    final sitterLocked = !care.canInviteHousehold;

    /// Why the household isn't ready yet (connecting, an error, or not the
    /// owner); null once the code is in.
    Widget? notReady() {
      if (ready) return null;
      return SurfaceCard(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: _connecting
              ? const CircularProgressIndicator()
              : Column(
                  children: [
                    Text(
                      care.isConnected && !care.canManageHousehold
                          ? 'Only the owner can invite people. Ask them for the code.'
                          : _error ?? 'Getting your household ready…',
                      textAlign: TextAlign.center,
                      style: text.bodyLarge?.copyWith(color: scheme.error),
                    ),
                    if (care.canManageHousehold) ...[
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: _ensureShared,
                        child: const Text('Try again'),
                      ),
                    ],
                  ],
                ),
        ),
      );
    }

    final List<Widget> body;
    final Widget footer;
    switch (step) {
      case 0:
        final error = _contactError;
        body = [
          const _Title(
            'Who are you inviting?',
            'We’ll greet them by name. You can remove anyone at any time.',
          ),
          const FieldLabel('Their name'),
          TextField(
            contextMenuBuilder: appContextMenuBuilder,
            controller: _name,
            maxLength: CareRepository.sitterLabelMax,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() {}),
            onTapOutside: (_) => FocusScope.of(context).unfocus(),
            decoration: const InputDecoration(
              hintText: 'e.g. Sara',
              counterText: '',
            ),
          ),
          const SizedBox(height: 20),
          const FieldLabel('Send it by'),
          ChoicePills<_Send>(
            label: 'Send it by',
            options: _Send.values,
            value: _via,
            labelOf: (v) => v.label,
            onChanged: (v) => setState(() => _via = v),
          ),
          if (_via != _Send.link) ...[
            const SizedBox(height: 12),
            TextField(
              contextMenuBuilder: appContextMenuBuilder,
              controller: _contact,
              keyboardType: _via == _Send.email
                  ? TextInputType.emailAddress
                  : TextInputType.phone,
              autocorrect: false,
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() {}),
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
              decoration: InputDecoration(
                hintText: _via == _Send.email
                    ? 'Email (optional)'
                    : 'Phone number (optional)',
                errorText: error,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            _via == _Send.link
                ? 'You’ll get a message to paste anywhere.'
                : 'Opens ${_via == _Send.email ? 'Mail' : 'Messages'} with '
                      'the invite filled in. Nothing is sent without you.',
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ];
        footer = FilledButton(
          onPressed: _name.text.trim().isEmpty || error != null
              ? null
              : () {
                  AppLog.event('invite.contact', {
                    'via': _via.name,
                    'hasContact': _contact.text.trim().isNotEmpty,
                  });
                  _go(1);
                },
          child: const Text('Continue'),
        );
      case 1:
        body = [
          _Title(
            'What can $_firstName do?',
            'They’ll see the same list and can mark doses as given.',
          ),
          _AudienceCard(
            title: 'Family or partner',
            detail: 'Installs Gave It. Logs doses and manages medicines.',
            icon: StrokeIconKind.people,
            selected: audience == _Audience.family,
            onTap: () => setState(() => _audience = _Audience.family),
          ),
          const SizedBox(height: 10),
          _AudienceCard(
            title: 'Pet sitter',
            detail:
                'No app needed. Logs doses from a browser link that stops '
                'working on a date you choose.',
            icon: StrokeIconKind.link,
            locked: sitterLocked,
            selected: audience == _Audience.sitter,
            onTap: sitterLocked
                ? () => context.push(
                    AppRoutes.paywallWith(
                      reason: PaywallReason.invite.queryValue,
                      from: 'sitter_link',
                    ),
                  )
                : () => setState(() => _audience = _Audience.sitter),
          ),
          if (audience == _Audience.sitter) ...[
            const SizedBox(height: 24),
            const FieldLabel('Access ends after'),
            ChoicePills<int>(
              label: 'Access ends after',
              options: _dayChoices,
              value: _days,
              labelOf: _daysLabel,
              onChanged: (d) => setState(() => _days = d),
            ),
            const SizedBox(height: 8),
            Text(
              'The link stops working on '
              '${_shortDate(DateTime.now().add(Duration(days: _days)))}. '
              'You can revoke it sooner.',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ];
        footer = FilledButton(
          onPressed: audience == null
              ? null
              : () {
                  AppLog.event('invite.audience', {
                    'who': audience.name,
                    if (audience == _Audience.sitter) 'days': _days,
                  });
                  _go(2);
                },
          child: const Text('Continue'),
        );
      case 2:
        final family = audience == _Audience.family;
        final preview = family
            ? (ready ? _familyMessage(care) : null)
            : _sitterMessage(care);
        body = [
          const _Title(
            'Look it over',
            'This is what they’ll get. Add a note if you like.',
          ),
          if (preview == null) notReady()! else _MessageBubble(preview),
          const SizedBox(height: 20),
          const FieldLabel('Add a note (optional)'),
          TextField(
            contextMenuBuilder: appContextMenuBuilder,
            controller: _note,
            maxLength: noteMax,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            onTapOutside: (_) => FocusScope.of(context).unfocus(),
            decoration: const InputDecoration(
              hintText: 'e.g. Insulin is in the fridge door',
            ),
          ),
          const SizedBox(height: 12),
          SurfaceCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _ReviewRow(
                  label: 'To',
                  value: [
                    _name.text.trim(),
                    if (_contact.text.trim().isNotEmpty && _via != _Send.link)
                      _contact.text.trim(),
                  ].join(' · '),
                  onEdit: () => _go(0),
                ),
                Divider(height: 1, color: tokens.hairline),
                _ReviewRow(
                  label: 'Access',
                  value: family
                      ? 'Family · logs and manages'
                      : 'Pet sitter · ${_daysLabel(_days)}',
                  onEdit: () => _go(1),
                ),
              ],
            ),
          ),
        ];
        footer = Builder(
          builder: (buttonContext) => FilledButton.icon(
            onPressed: _sending || !ready
                ? null
                : () => _send(buttonContext, care),
            icon: _sending
                ? SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: scheme.onPrimary,
                    ),
                  )
                : StrokeIcon(
                    StrokeIconKind.share,
                    size: 20,
                    color: scheme.onPrimary,
                  ),
            label: Text(_sending ? 'Making the link…' : _via.action),
          ),
        );
      default:
        body = [
          _Title(
            'Invite ready for $_firstName',
            audience == _Audience.family
                ? 'Once they enter the code, they’re in. Share it again any time.'
                : 'They can log doses from the link until it ends.',
          ),
          if (audience == _Audience.family)
            SurfaceCard(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Text(
                      'Your invite code',
                      style: text.bodySmall?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (ready)
                      Semantics(
                        label: 'Invite code ${code.split('').join(' ')}',
                        child: SelectableText(
                          code,
                          textAlign: TextAlign.center,
                          style: text.displaySmall?.copyWith(
                            letterSpacing: 8,
                            color: scheme.onSurface,
                          ),
                        ),
                      )
                    else
                      notReady()!,
                    if (ready && _expiryText(care) != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        _expiryText(care)!,
                        style: text.bodyMedium?.copyWith(
                          color: care.inviteExpired
                              ? scheme.error
                              : tokens.brandDark,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    if (ready)
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
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
                          ),
                          if (joinLink != null)
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
                    if (ready && care.canManageHousehold)
                      TextButton(
                        onPressed: _rotating ? null : _newCode,
                        child: Text(
                          _rotating ? 'Making a new code…' : 'New code',
                        ),
                      ),
                  ],
                ),
              ),
            )
          else ...[
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
              onShare: (buttonContext) =>
                  _shareSitterLink(buttonContext, care, care.sitterLink!),
            ),
            if (!_linksShown)
              TextButton(
                onPressed: _loadingLinks ? null : _showLinks,
                child: Text(
                  _loadingLinks ? 'Loading links…' : 'See active links',
                ),
              ),
            if (_linksShown && care.sitterLinks.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'No other active links.',
                  style: text.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (care.sitterLinks.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Active sitter links', style: text.titleSmall),
              const SizedBox(height: 8),
              SurfaceCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (final link in care.sitterLinks)
                      ListTile(
                        title: Text(
                          link.label.isEmpty ? 'Sitter link' : link.label,
                        ),
                        subtitle: Text(
                          'Works until ${_shortDate(link.expiresAt)}'
                          '${link.lastUsedAt == null ? '' : ' · last opened ${_shortDate(link.lastUsedAt!)}'}',
                        ),
                        trailing: TextButton(
                          onPressed: () => _revoke(link),
                          child: const Text('Revoke'),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ];
        footer = FilledButton(
          onPressed: () => context.pop(),
          child: const Text('Done'),
        );
    }

    // Close on the first and last step (going back from "ready" would
    // only invite sending twice); otherwise back one step.
    final closes = step == 0 || step == _steps - 1;
    return PopScope(
      canPop: closes,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _go(step - 1);
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: closes ? 'Close' : 'Back',
                      onPressed: () => closes ? context.pop() : _go(step - 1),
                      icon: StrokeIcon(
                        closes
                            ? StrokeIconKind.close
                            : StrokeIconKind.chevronLeft,
                        color: scheme.onSurface,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'Invite someone',
                        textAlign: TextAlign.center,
                        style: text.titleMedium,
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
              Semantics(
                label: 'Step ${step + 1} of $_steps',
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                  child: Row(
                    children: [
                      for (var i = 0; i < _steps; i++) ...[
                        if (i > 0) const SizedBox(width: 4),
                        Expanded(
                          child: AnimatedContainer(
                            duration: tokens.motion.enter,
                            height: 4,
                            decoration: BoxDecoration(
                              color: i <= step
                                  ? scheme.onSurface
                                  : scheme.onSurface.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  key: ValueKey(step),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                  children: body,
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: tokens.hairline)),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: SizedBox(width: double.infinity, child: footer),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// How the invite leaves the phone.
enum _Send {
  text('Text', 'Open Messages'),
  email('Email', 'Open Mail'),
  link('Share', 'Share invite');

  const _Send(this.label, this.action);
  final String label;
  final String action;
}

enum _Audience { family, sitter }

/// The invite as they'll read it (v14 ReviewStep message preview).
class _MessageBubble extends StatelessWidget {
  const _MessageBubble(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final paws = context.paws;
    final text = Theme.of(context).textTheme;
    return Semantics(
      label: 'Message preview. $message',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: paws.surfaces.subtle,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
            bottomRight: Radius.circular(20),
            bottomLeft: Radius.circular(6),
          ),
        ),
        child: Text(message, style: text.bodyMedium?.copyWith(height: 1.45)),
      ),
    );
  }
}

/// "To · Sara · Edit" on the review step.
class _ReviewRow extends StatelessWidget {
  const _ReviewRow({
    required this.label,
    required this.value,
    required this.onEdit,
  });

  final String label;
  final String value;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(child: Text(value, style: text.bodyLarge)),
          TextButton(
            onPressed: onEdit,
            // Brand colour, like Edit on the add-medicine review.
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.primary,
            ),
            child: Text('Edit', semanticsLabel: 'Edit $label'),
          ),
        ],
      ),
    );
  }
}

/// v14 StepHeading inside the invite flow.
class _Title extends StatelessWidget {
  const _Title(this.title, this.subtitle);

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(title, style: text.headlineMedium),
          ),
          const SizedBox(height: 10),
          Text(
            subtitle,
            style: text.bodyLarge?.copyWith(
              fontSize: 16,
              height: 1.45,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// v14 AccessStep option: a radio, a title and what it allows.
class _AudienceCard extends StatelessWidget {
  const _AudienceCard({
    required this.title,
    required this.detail,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.locked = false,
  });

  final String title;
  final String detail;
  final StrokeIconKind icon;
  final bool selected;

  /// Free tier: shows a Pro badge and [onTap] opens the paywall.
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final paws = context.paws;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      label: '$title${locked ? ', Pro' : ''}. $detail',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: PawsElevation.card(Theme.of(context).brightness),
        ),
        child: Material(
          color: paws.surfaces.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: selected
                ? BorderSide(color: scheme.primary, width: 2)
                : BorderSide.none,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected ? scheme.primary : Colors.transparent,
                      border: selected
                          ? null
                          : Border.all(
                              color: scheme.onSurface.withValues(alpha: 0.2),
                              width: 2,
                            ),
                    ),
                    child: selected
                        ? Center(
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: scheme.onPrimary,
                                shape: BoxShape.circle,
                              ),
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: text.titleMedium),
                        const SizedBox(height: 2),
                        Text(
                          detail,
                          style: text.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (locked)
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: paws.brandSoft,
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
                            color: paws.brandDark,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    )
                  else
                    StrokeIcon(icon, size: 20, color: scheme.onSurfaceVariant),
                ],
              ),
            ),
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
            const SizedBox(height: 4),
            // Several sitters: each gets their own link, revocable alone.
            TextButton(
              onPressed: onCreate,
              child: const Text('Create another link'),
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
            contextMenuBuilder: appContextMenuBuilder,
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
