import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/paws_widgets.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:provider/provider.dart';

/// Shows one pet's weight, conditions, and notes from this week.
class PetProfileScreen extends StatefulWidget {
  const PetProfileScreen({super.key});

  @override
  State<PetProfileScreen> createState() => _PetProfileScreenState();
}

class _PetProfileScreenState extends State<PetProfileScreen> {
  String? _petId;

  @override
  Widget build(BuildContext context) {
    final care = context.watch<CareRepository>();
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.paws;
    final text = Theme.of(context).textTheme;
    final pet =
        (_petId == null ? null : care.tryPetById(_petId!)) ?? care.primaryPet;
    if (pet == null) {
      return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Pets', style: text.displaySmall),
                const SizedBox(height: 8),
                Text(
                  'No pet here yet. Add one, or join the household of the person who invited you.',
                  style: text.bodyLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => context.push(AppRoutes.addPet),
                  child: const Text('Add a pet'),
                ),
                if (!care.isConnected)
                  TextButton(
                    onPressed: () => context.push(AppRoutes.join),
                    child: const Text('I have an invite code'),
                  ),
              ],
            ),
          ),
        ),
      );
    }
    final weightLabel = pet.weightKg > 0 ? '${pet.weightKg} kg' : '—';
    final meds = care.medicationsFor(pet.id);
    final week = care.reportFor(pet.id, 7);
    final weekGiven = week.lines.fold<int>(0, (sum, line) => sum + line.given);
    final weekExpected = week.lines.fold<int>(
      0,
      (sum, line) => sum + line.expected,
    );
    final onTime = weekExpected == 0
        ? '—'
        : '${(weekGiven * 100 / weekExpected).round()}%';
    final details = [
      pet.speciesLabel,
      if (pet.breed.isNotEmpty) pet.breed,
      if (pet.ageYears > 0) '${pet.ageYears} yrs',
      if (pet.sex.isNotEmpty) pet.sex,
    ].join(' · ');

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
              children: [
                for (final item in care.pets) ...[
                  _PetTab(
                    label: item.name,
                    selected: item.id == pet.id,
                    onPressed: () => setState(() => _petId = item.id),
                  ),
                  const SizedBox(width: 8),
                ],
                Semantics(
                  button: true,
                  label: 'Add pet',
                  child: InkWell(
                    onTap: () => context.push(AppRoutes.addPet),
                    customBorder: const CircleBorder(),
                    child: Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: scheme.outline),
                      ),
                      child: StrokeIcon(
                        StrokeIconKind.plus,
                        size: 16,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                InitialsAvatar(
                  label: pet.name.characters.first,
                  size: 72,
                  fontSize: 26,
                  background: tokens.brandSoft,
                  foreground: tokens.brandDark,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(pet.name, style: text.headlineMedium),
                      Text(
                        details,
                        style: text.titleSmall?.copyWith(
                          fontWeight: FontWeight.w400,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => context.push(AppRoutes.editPet(pet.id)),
                  child: const Text('Edit'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                for (final condition in pet.conditions)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: tokens.neutral,
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      child: Text(
                        condition,
                        style: text.bodyMedium?.copyWith(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _Stat(label: 'Weight', value: weightLabel),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _Stat(
                    label: 'Doses a day',
                    value:
                        '${meds.fold<int>(0, (sum, item) => sum + item.parts.length)}',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _Stat(label: 'Given (7 days)', value: onTime),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(child: Text('Medicines', style: text.titleMedium)),
                TextButton.icon(
                  onPressed: () =>
                      context.push('${AppRoutes.schedule}?pet=${pet.id}'),
                  icon: StrokeIcon(
                    StrokeIconKind.plus,
                    size: 16,
                    color: scheme.primary,
                  ),
                  label: const Text('Add'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            SurfaceCard(
              child: meds.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'No medicines yet',
                            style: text.titleSmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Add one and it shows on Today for everyone.',
                            style: text.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: () => context.push(
                              '${AppRoutes.schedule}?pet=${pet.id}',
                            ),
                            child: Text('Add ${pet.name}’s medicine'),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        for (final (index, item) in meds.indexed)
                          ListTile(
                            minTileHeight: 60,
                            title: Text(item.name),
                            subtitle: Text(item.detail),
                            trailing: item.isLow
                                ? Text(
                                    'Low',
                                    style: text.bodyMedium?.copyWith(
                                      color: tokens.warning,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  )
                                : const Icon(Icons.chevron_right_rounded),
                            shape: index == meds.length - 1
                                ? null
                                : Border(
                                    bottom: BorderSide(color: tokens.divider),
                                  ),
                            onTap: () =>
                                context.push(AppRoutes.medication(item.id)),
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => context.go(AppRoutes.reports),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                foregroundColor: tokens.brandDark,
              ),
              icon: StrokeIcon(
                StrokeIconKind.file,
                size: 18,
                color: tokens.brandDark,
              ),
              label: const Text('Prepare vet report'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PetTab extends StatelessWidget {
  const _PetTab({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.secondary : scheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: selected ? scheme.secondary : scheme.outlineVariant,
        ),
      ),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            label,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: selected ? scheme.onSecondary : scheme.onSurface,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      radius: 14,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontSize: 20),
          ),
        ],
      ),
    );
  }
}
