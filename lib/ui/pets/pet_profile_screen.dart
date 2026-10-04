import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/care_tab_builder.dart';
import 'package:pawsitive_sync/core/widgets/care_widgets.dart';
import 'package:pawsitive_sync/core/widgets/paws_widgets.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:pawsitive_sync/ui/pets/widgets/pet_photo_sheet.dart';

class PetProfileScreen extends StatefulWidget {
  const PetProfileScreen({super.key});
  @override
  State<PetProfileScreen> createState() => _PetProfileScreenState();
}

class _PetProfileScreenState extends State<PetProfileScreen> {
  String? _petId;

  // Tab screen: rebuilds on data changes only while visible.
  @override
  Widget build(BuildContext context) => CareTabBuilder(builder: _build);

  Widget _build(BuildContext context, CareRepository care) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final pet = care.tryPetById(_petId ?? '') ?? care.primaryPet;
    final meds = pet == null ? null : care.medicationsFor(pet.id);
    final week = pet == null ? null : care.reportFor(pet.id, 7);
    final given =
        week?.lines.fold<int>(0, (sum, line) => sum + line.given) ?? 0;
    final expected =
        week?.lines.fold<int>(0, (sum, line) => sum + line.expected) ?? 0;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: carePagePadding,
          children: [
            CarePageHeader(
              title: 'Pets',
              subtitle: 'Their little world of care.',
              action: IconButton(
                tooltip: 'Add pet',
                onPressed: () {
                  if (!care.canAddPet) {
                    // billing.paywall.opened from=add_pet_pets_tab.
                    context.push(
                      AppRoutes.paywallWith(from: 'add_pet_pets_tab'),
                    );
                    return;
                  }
                  context.push(AppRoutes.addPet);
                },
                style: IconButton.styleFrom(
                  backgroundColor: scheme.primaryContainer,
                  minimumSize: const Size(44, 44),
                ),
                icon: StrokeIcon(
                  StrokeIconKind.plus,
                  size: 22,
                  color: context.paws.brandDark,
                ),
              ),
            ),
            const SizedBox(height: 24),
            if (pet == null) ...[
              CareEmptyState(
                title: 'Meet your care companion.',
                description: 'Add a pet to keep their medicines, details, and care history together.',
                action: 'Add a pet',
                onAction: () => context.push(AppRoutes.addPet),
              ),
              if (!care.isConnected)
                TextButton(
                  onPressed: () => context.push(AppRoutes.join),
                  child: const Text('I have an invite code'),
                ),
            ] else ...[
              if (care.pets.length > 1) ...[
                CarePetPicker(
                  pets: care.pets,
                  selectedId: pet.id,
                  verticalWhenMany: true,
                  onSelected: (id) => setState(() => _petId = id),
                ),
                const SizedBox(height: 20),
              ],
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _PetPhotoButton(pet: pet, care: care),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () =>
                                  context.push(AppRoutes.editPet(pet.id)),
                              style: TextButton.styleFrom(
                                foregroundColor: context.paws.brandDark,
                              ),
                              child: const Text('Edit profile'),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      pet.name,
                      style: text.displaySmall?.copyWith(fontSize: 30),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      [
                        pet.speciesLabel,
                        if (pet.breed.isNotEmpty) pet.breed,
                        if (pet.ageYears > 0)
                          '${pet.ageYears} ${pet.ageYears == 1 ? 'year' : 'years'} old',
                        if (pet.sex.isNotEmpty) pet.sex,
                      ].join(' · '),
                      style: text.bodyLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 22),
                    Divider(color: scheme.outlineVariant),
                    const SizedBox(height: 18),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: CareMetric(
                            value: pet.weightKg > 0 ? '${pet.weightKg}' : '—',
                            label: 'Weight (kg)',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: CareMetric(
                            value: '${meds!.length}',
                            label: 'Medicines',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: CareMetric(
                            value: expected == 0
                                ? '—'
                                : '${(given * 100 / expected).round()}%',
                            label: 'Given in 7 days',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (pet.conditions.isNotEmpty) ...[
                const SizedBox(height: 24),
                const CareSectionHeader('Care needs'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final condition in pet.conditions)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: scheme.outlineVariant),
                        ),
                        child: Text(
                          condition,
                          style: text.bodyMedium?.copyWith(
                            color: scheme.onSurface,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 24),
              CareSectionHeader(
                'Medicines',
                action: 'Add',
                onAction: () =>
                    context.push('${AppRoutes.schedule}?pet=${pet.id}'),
              ),
              const SizedBox(height: 8),
              if (meds.isEmpty)
                SurfaceCard(
                  radius: 20,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Their routine starts here', style: text.titleLarge),
                      const SizedBox(height: 8),
                      Text(
                        'Add a medicine to see it on Today and start building a care history.',
                        style: text.bodyLarge?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 18),
                      FilledButton(
                        onPressed: () =>
                            context.push('${AppRoutes.schedule}?pet=${pet.id}'),
                        child: const Text('Add medicine'),
                      ),
                    ],
                  ),
                ),
              for (final item in meds) ...[
                SurfaceCard(
                  radius: 20,
                  child: InkWell(
                    onTap: () => context.push(AppRoutes.medication(item.id)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(11),
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: StrokeIcon(
                              StrokeIconKind.calendar,
                              size: 22,
                              color: context.paws.brandDark,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.name, style: text.titleMedium),
                                const SizedBox(height: 5),
                                Text(item.detail, style: text.bodyMedium),
                                if (item.isLow) ...[
                                  const SizedBox(height: 5),
                                  Text(
                                    '${item.dosesLeft} doses left · refill soon',
                                    style: text.bodySmall?.copyWith(
                                      color: context.paws.warning,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          StrokeIcon(
                            StrokeIconKind.chevronRight,
                            size: 20,
                            color: scheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => context.go(AppRoutes.reports),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                icon: StrokeIcon(
                  StrokeIconKind.file,
                  size: 19,
                  color: context.paws.brandDark,
                ),
                label: const Text('Prepare vet report'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The profile avatar doubles as the photo control: tap to take, choose or
/// remove a photo. Saving is local and instant; the upload runs behind it
/// with a small ring, and the screen stays usable throughout.
class _PetPhotoButton extends StatefulWidget {
  const _PetPhotoButton({required this.pet, required this.care});

  final Pet pet;
  final CareRepository care;

  @override
  State<_PetPhotoButton> createState() => _PetPhotoButtonState();
}

class _PetPhotoButtonState extends State<_PetPhotoButton> {
  /// Guards double taps while the sheet, picker or local save is open.
  bool _busy = false;

  Future<void> _change() async {
    if (_busy) return;
    setState(() => _busy = true);
    final pet = widget.pet;
    final care = widget.care;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final choice = await showPetPhotoSheet(
        context,
        hasPhoto: pet.hasPhoto,
        petId: pet.id,
      );
      final ok = switch (choice) {
        PetPhotoPicked(:final bytes, :final source) => await care.setPetPhoto(
          pet.id,
          bytes,
          source: source,
        ),
        PetPhotoRemoved() => await care.removePetPhoto(pet.id),
        null => true,
      };
      if (!ok && care.lastError != null) {
        messenger.showSnackBar(SnackBar(content: Text(care.lastError!)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pet = widget.pet;
    final progress = widget.care.photoUploadProgress(pet.id);
    const size = 90.0;
    return Semantics(
      button: true,
      label: pet.hasPhoto
          ? 'Change photo of ${pet.name}'
          : 'Add a photo of ${pet.name}',
      child: GestureDetector(
        onTap: _change,
        child: SizedBox.square(
          dimension: size,
          child: Stack(
            children: [
              PetPortrait(pet, size: size),
              if (progress != null)
                Positioned.fill(
                  child: ExcludeSemantics(
                    child: CircularProgressIndicator(
                      // Indeterminate until the first bytes go out.
                      value: progress <= 0 ? null : progress,
                      strokeWidth: 3,
                      color: scheme.primary,
                      backgroundColor: scheme.surface.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: scheme.primaryContainer,
                      width: 3,
                    ),
                  ),
                  child: StrokeIcon(
                    StrokeIconKind.camera,
                    size: 13,
                    color: scheme.onPrimary,
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
