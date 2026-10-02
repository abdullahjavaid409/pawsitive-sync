import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/paws_widgets.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:provider/provider.dart';

class InviteScreen extends StatefulWidget {
  const InviteScreen({super.key});

  @override
  State<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends State<InviteScreen> {
  InviteRole _role = InviteRole.sitter;
  bool _notify = true;
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final care = context.watch<CareRepository>();
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.paws;
    final text = Theme.of(context).textTheme;
    final pets = care.pets.map((pet) => pet.name).join(', ');

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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
              Text('Who are you inviting?', style: text.headlineMedium),
              const SizedBox(height: 16),
              _RoleTile(
                title: 'Caregiver',
                subtitle: 'Partner or family. Sees and logs everything.',
                selected: _role == InviteRole.caregiver,
                onPressed: () => setState(() => _role = InviteRole.caregiver),
              ),
              const SizedBox(height: 8),
              _RoleTile(
                title: 'Sitter',
                subtitle: 'Only what they need, for set dates. Access ends on its own.',
                selected: _role == InviteRole.sitter,
                onPressed: () => setState(() => _role = InviteRole.sitter),
              ),
              const SizedBox(height: 16),
              SurfaceCard(
                child: Column(
                  children: [
                    _InfoRow(
                      icon: StrokeIconKind.calendar,
                      label: 'Access',
                      value: 'Oct 5 – Oct 12',
                    ),
                    _InfoRow(
                      icon: StrokeIconKind.paw,
                      label: 'Pets',
                      value: pets,
                    ),
                    _InfoRow(
                      icon: StrokeIconKind.file,
                      label: 'Can see',
                      value: "Today's doses, notes",
                    ),
                    SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                      ),
                      secondary: StrokeIcon(
                        StrokeIconKind.bell,
                        color: scheme.onSurface,
                      ),
                      title: const Text('Tell me when they log a dose'),
                      value: _notify,
                      onChanged: (value) => setState(() => _notify = value),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SurfaceCard(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    StrokeIcon(
                      StrokeIconKind.check,
                      color: scheme.primary,
                      strokeWidth: 2.2,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Invite link ready', style: text.titleSmall),
                          Text(
                            'Works once · expires in 48 hours',
                            style: text.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        await Clipboard.setData(
                          const ClipboardData(
                            text: 'https://pawsitivesync.app/join/miso-juniper',
                          ),
                        );
                        if (!mounted) return;
                        setState(() => _copied = true);
                      },
                      child: Text(_copied ? 'Copied' : 'Copy'),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Invite ready to share.')),
                  );
                  context.pop();
                },
                icon: StrokeIcon(
                  StrokeIconKind.plus,
                  size: 18,
                  color: scheme.onPrimary,
                ),
                label: const Text('Share invite'),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  _role == InviteRole.sitter ? 'Sitter access ends on Oct 12.' : 'Caregivers stay on the schedule until you remove them.',
                  style: text.bodySmall?.copyWith(color: tokens.brandDark),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleTile extends StatelessWidget {
  const _RoleTile({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onPressed,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? scheme.primary : scheme.outline,
                    width: selected ? 6 : 1.5,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final StrokeIconKind icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          StrokeIcon(icon, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyLarge),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: scheme.onSurface),
          ),
        ],
      ),
    );
  }
}
