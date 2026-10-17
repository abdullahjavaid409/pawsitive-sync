import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/format/clock_format.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/ui/care/coming_up_section.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/care_tab_builder.dart';
import 'package:pawsitive_sync/core/widgets/care_widgets.dart';
import 'package:pawsitive_sync/core/widgets/paws_widgets.dart';
import 'package:pawsitive_sync/core/widgets/pet_mark.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:pawsitive_sync/ui/pets/widgets/pet_photo_sheet.dart';
import 'package:pawsitive_sync/ui/today/dose_sheets.dart';
import 'package:pawsitive_sync/ui/today/today_cards.dart';
import 'package:pawsitive_sync/ui/today/today_v14.dart';
import 'package:pawsitive_sync/core/widgets/system_menu.dart';

class PetProfileScreen extends StatefulWidget {
  const PetProfileScreen({super.key});
  @override
  State<PetProfileScreen> createState() => _PetProfileScreenState();
}

class _PetProfileScreenState extends State<PetProfileScreen> {
  String? _petId;

  /// Opens Add pet, then shows the new pet.
  Future<void> _addPet() async {
    final id = await context.push<String>(AppRoutes.addPet);
    if (id != null && mounted) setState(() => _petId = id);
  }

  /// Guards double taps while the sheet, picker or local save is open.
  bool _photoBusy = false;

  /// Take, choose or remove a photo. Saving is local and instant; the upload
  /// runs behind it with a thin bar on the photo.
  Future<void> _changePhoto(CareRepository care, Pet pet) async {
    if (_photoBusy) return;
    setState(() => _photoBusy = true);
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
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  /// Opens the note editor; saving is local first and syncs (pet.note).
  Future<void> _editNote(CareRepository care, Pet pet) async {
    final messenger = ScaffoldMessenger.of(context);
    final text = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: context.paws.surfaces.card,
      routeSettings: const RouteSettings(name: 'pet_note'),
      builder: (_) => _NoteSheet(pet: pet),
    );
    if (text == null || !mounted) return;
    final ok = await care.setCareNote(pet.id, text);
    if (!ok && care.lastError != null) {
      messenger.showSnackBar(SnackBar(content: Text(care.lastError!)));
    }
  }

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
          padding: carePagePaddingOf(context),
          children: [
            // v14 header: serif "Pets", the pet switcher on the right.
            _PetsHeader(
              care: care,
              selectedId: pet?.id,
              onSelect: (id) => setState(() => _petId = id),
              onAdd: () {
                if (!care.canAddPet) {
                  // billing.paywall.opened from=add_pet_pets_tab.
                  context.push(
                    AppRoutes.paywallWith(
                      reason: 'second_pet',
                      from: 'add_pet_pets_tab',
                    ),
                  );
                  return;
                }
                _addPet();
              },
            ),
            const SizedBox(height: 8),
            if (pet == null) ...[
              CareEmptyState(
                photo: 'assets/photos/empty-no-pet.jpg',
                title: 'Meet your care companion.',
                description: 'Add a pet to keep their medicines, details, and care history together.',
                action: 'Add a pet',
                onAction: _addPet,
              ),
              if (!care.isConnected)
                TextButton(
                  onPressed: () => context.push(AppRoutes.join),
                  child: const Text('I have an invite code'),
                ),
            ] else ...[
              _PetIdentity(
                pet: pet,
                progress: care.photoUploadProgress(pet.id),
                onPhoto: () => _changePhoto(care, pet),
                onEdit: () => context.push(AppRoutes.editPet(pet.id)),
              ),
              const SizedBox(height: 16),
              _NextDoseCard(care: care, pet: pet),
              if (_weekStats(care, pet, meds!, given, expected) case final stats
                  when stats.isNotEmpty) ...[
                const SizedBox(height: 12),
                _WeekStrip(stats: stats),
              ],
              if (pet.conditions.isNotEmpty) ...[
                const SizedBox(height: 12),
                _CareNeeds(conditions: pet.conditions),
              ],
              const SizedBox(height: 16),
              _HouseholdNote(
                care: care,
                pet: pet,
                onEdit: () => _editNote(care, pet),
              ),
              const SizedBox(height: 24),
              const CareSectionHeader('Medicines'),
              const SizedBox(height: 10),
              if (meds.isEmpty)
                SurfaceCard(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'No medicines yet. Add one and everyone in the household '
                    'gets the reminders.',
                    style: text.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              for (final item in meds) ...[
                _MedicineCard(
                  care: care,
                  medication: item,
                  onTap: () => context.push(AppRoutes.medication(item.id)),
                ),
                const SizedBox(height: 16),
              ],
              if (meds.isEmpty) const SizedBox(height: 16),
              SurfaceCard(
                child: _AddMedicineRow(
                  first: meds.isEmpty,
                  onTap: () =>
                      context.push('${AppRoutes.schedule}?pet=${pet.id}'),
                ),
              ),
              const SizedBox(height: 24),
              ComingUpSection(care: care, petId: pet.id),
            ],
          ],
        ),
      ),
    );
  }
}

/// Up to three facts for the week, only the ones with real data: no "—"
/// placeholders. Next care event, else weight, fills the third slot.
List<({String value, String label})> _weekStats(
  CareRepository care,
  Pet pet,
  List<Medication> meds,
  int given,
  int expected,
) {
  final next = care
      .upcomingCareEvents()
      .where((event) => event.petId == pet.id)
      .firstOrNull;
  return [
    if (expected > 0) (value: '$given of $expected', label: 'Given this week'),
    if (meds.isNotEmpty)
      (
        value: '${meds.length}',
        label: meds.length == 1 ? 'Medicine' : 'Medicines',
      ),
    if (next != null)
      (
        value: _shortDate(next.dueDay),
        label: 'Next ${next.kindLabel.toLowerCase()}',
      )
    else if (pet.weightKg > 0)
      (value: '${pet.weightKg} kg', label: 'Weight'),
  ];
}

const _months = [
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

/// "2026-10-21" → "Oct 21"; anything unparsable is shown as stored.
String _shortDate(String day) {
  final date = DateTime.tryParse(day);
  return date == null ? day : '${_months[date.month - 1]} ${date.day}';
}

/// v14 "Household note": what everyone should know before giving a dose,
/// signed and dated. Empty: one quiet row to add the first note.
class _HouseholdNote extends StatelessWidget {
  const _HouseholdNote({
    required this.care,
    required this.pet,
    required this.onEdit,
  });

  final CareRepository care;
  final Pet pet;
  final VoidCallback onEdit;

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

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    if (pet.careNote.isEmpty) {
      return SurfaceCard(
        child: InkWell(
          onTap: onEdit,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Row(
              children: [
                Icon(Icons.push_pin_outlined, size: 18, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Add a household note',
                    style: text.bodyLarge?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final by = pet.careNoteBy.isEmpty ? null : care.memberById(pet.careNoteBy);
    final day = DateTime.tryParse(pet.careNoteDay);
    final signed = [
      if (by != null) by.isYou ? 'You' : by.name,
      if (day != null) 'updated ${_months[day.month - 1]} ${day.day}',
    ].join(' · ');
    return SurfaceCard(
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.push_pin_outlined,
                    size: 14,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Household note',
                      style: text.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Text(
                    'Edit',
                    style: text.bodySmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                pet.careNote,
                style: text.bodyMedium?.copyWith(
                  color: scheme.onSurface,
                  height: 1.45,
                ),
              ),
              if (signed.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  signed,
                  style: text.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Edits the household note. Pops the new text (empty clears), or null.
class _NoteSheet extends StatefulWidget {
  const _NoteSheet({required this.pet});

  final Pet pet;

  @override
  State<_NoteSheet> createState() => _NoteSheetState();
}

class _NoteSheetState extends State<_NoteSheet> {
  late final _controller = TextEditingController(text: widget.pet.careNote);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Household note', style: text.headlineMedium),
          const SizedBox(height: 6),
          Text(
            'Everyone who cares for ${widget.pet.name} sees this before '
            'giving a dose.',
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          TextField(
            contextMenuBuilder: appContextMenuBuilder,
            controller: _controller,
            autofocus: true,
            minLines: 3,
            maxLines: 6,
            maxLength: Pet.maxNoteLength,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText:
                  'e.g. Give insulin only after ${widget.pet.name} has eaten.',
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () => Navigator.pop(context, _controller.text),
            child: const Text('Save note'),
          ),
          if (widget.pet.careNote.isNotEmpty)
            TextButton(
              onPressed: () => Navigator.pop(context, ''),
              style: TextButton.styleFrom(foregroundColor: scheme.error),
              child: const Text('Remove note'),
            ),
        ],
      ),
    );
  }
}

/// "Pets" in the serif with the pet switcher beside it (v14 PetSwitcher):
/// a ringed photo per pet and a dashed + to add one.
class _PetsHeader extends StatelessWidget {
  const _PetsHeader({
    required this.care,
    required this.selectedId,
    required this.onSelect,
    required this.onAdd,
  });

  final CareRepository care;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final pets = care.pets;
    final switcher = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // v14 PetSwitcher: every pet's photo (one pet too, so the header
        // always shows whose page this is), then the dashed add button.
        if (pets.isNotEmpty)
          for (final pet in pets) ...[
            Semantics(
              button: true,
              selected: pet.id == selectedId,
              label: 'Show ${pet.name}',
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onSelect(pet.id),
                child: AnimatedContainer(
                  duration: context.paws.motion.micro,
                  width: 44,
                  height: 44,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: pet.id == selectedId && pets.length > 1
                          ? scheme.onSurface
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: Opacity(
                    opacity: pet.id == selectedId ? 1 : 0.8,
                    child: PetAvatar(
                      species: pet.species,
                      photoPath: pet.photoPath,
                      photoVersion: pet.photoVersion,
                      size: 34,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
        Tooltip(
          message: 'Add pet',
          child: Semantics(
            button: true,
            label: care.canAddPet ? 'Add pet' : 'Add pet, needs Pro',
            excludeSemantics: true,
            child: InkWell(
              onTap: onAdd,
              customBorder: const CircleBorder(),
              child: SizedBox.square(
                dimension: 44,
                child: CustomPaint(
                  painter: DashedCirclePainter(
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                    strokeWidth: 1.5,
                  ),
                  child: Center(
                    // Free with one pet: a small lock says "Pro" before
                    // the tap (honest paywall), on the v14 plus.
                    child: Badge(
                      isLabelVisible: !care.canAddPet,
                      backgroundColor: scheme.primary,
                      offset: const Offset(10, -10),
                      label: StrokeIcon(
                        StrokeIconKind.lock,
                        size: 9,
                        color: scheme.onPrimary,
                      ),
                      child: StrokeIcon(
                        StrokeIconKind.plus,
                        size: 16,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 0, 8),
      child: Row(
        children: [
          Semantics(
            header: true,
            child: Text('Pets', style: text.displaySmall),
          ),
          const SizedBox(width: 12),
          // Many pets scroll sideways instead of pushing the title off.
          Expanded(
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: true,
                child: switcher,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Photo tile with a camera button, serif name, "Cat · 4 years · 4.2 kg",
/// and an "Edit profile" pill (v14 PetIdentity).
class _PetIdentity extends StatelessWidget {
  const _PetIdentity({
    required this.pet,
    required this.progress,
    required this.onPhoto,
    required this.onEdit,
  });

  final Pet pet;

  /// Photo upload progress, null when nothing is uploading.
  final double? progress;
  final VoidCallback onPhoto;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final paws = context.paws;
    final meta = [
      pet.speciesLabel,
      if (pet.ageYears > 0)
        '${pet.ageYears} ${pet.ageYears == 1 ? 'year' : 'years'}',
      if (pet.weightKg > 0) '${pet.weightKg} kg',
    ].join(' · ');
    final photo = Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 66,
          height: 66,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: PawsElevation.card(Theme.of(context).brightness),
            color: paws.surfaces.subtle,
          ),
          clipBehavior: Clip.antiAlias,
          child: pet.hasPhoto
              ? Image.file(
                  File(pet.photoPath!),
                  key: ValueKey('${pet.photoPath}#${pet.photoVersion}'),
                  fit: BoxFit.cover,
                  cacheWidth: (66 * MediaQuery.devicePixelRatioOf(context))
                      .round(),
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) =>
                      Center(child: PetMark(species: pet.species, size: 52)),
                )
              : Center(child: PetMark(species: pet.species, size: 52)),
        ),
        if (progress case final value?)
          Positioned(
            left: 6,
            right: 6,
            bottom: 4,
            child: ExcludeSemantics(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  // Indeterminate until the first bytes go out.
                  value: value <= 0 ? null : value,
                  minHeight: 3,
                ),
              ),
            ),
          ),
        // A 44 pt hit area around a small visual button.
        Positioned(
          right: -12,
          bottom: -12,
          child: Semantics(
            button: true,
            label: pet.hasPhoto
                ? 'Change photo of ${pet.name}'
                : 'Add photo of ${pet.name}',
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onPhoto,
              child: SizedBox.square(
                dimension: 44,
                child: Center(
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: paws.surfaces.card,
                      shape: BoxShape.circle,
                      boxShadow: PawsElevation.card(
                        Theme.of(context).brightness,
                      ),
                    ),
                    child: Center(
                      child: StrokeIcon(
                        StrokeIconKind.camera,
                        size: 14,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
    return Row(
      children: [
        photo,
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                pet.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.headlineSmall,
              ),
              const SizedBox(height: 4),
              Text(
                meta,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        TextButton(
          onPressed: onEdit,
          style: TextButton.styleFrom(
            backgroundColor: paws.surfaces.subtle,
            foregroundColor: scheme.onSurface,
            minimumSize: const Size(44, 44),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            shape: const StadiumBorder(),
            textStyle: text.labelLarge?.copyWith(fontSize: 13),
          ),
          child: const Text('Edit profile'),
        ),
      ],
    );
  }
}

/// "Next dose tomorrow · 8:00 AM" (v14), or a plain "all logged" line when
/// nothing is scheduled in the coming week (a course that just ended).
String _afterTodayNote(BuildContext context, CareRepository care, Pet pet) {
  final next = care.nextAfterToday(petId: pet.id);
  if (next == null) return 'Every dose for ${pet.name} is logged.';
  final at = next.at;
  final tomorrow = DateTime(care.now.year, care.now.month, care.now.day + 1);
  final day = DateUtils.isSameDay(at, tomorrow)
      ? 'tomorrow'
      : MaterialLocalizations.of(context).formatMediumDate(at);
  return 'Next dose $day · ${ClockFormat.label(at.hour * 60 + at.minute)}';
}

/// "Next dose · Today", the time large, medicine and amount, "Mark given",
/// then a chip per dose of that medicine today (v14 NextDoseCard).
class _NextDoseCard extends StatelessWidget {
  const _NextDoseCard({required this.care, required this.pet});

  final CareRepository care;
  final Pet pet;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final paws = context.paws;
    final doses = care.doses.where((d) => d.petId == pet.id).toList()
      ..sort((a, b) => doseMinute(a) - doseMinute(b));
    final next =
        doses.where((d) => d.status == DoseStatus.due).firstOrNull ??
        doses.where((d) => d.status == DoseStatus.upcoming).firstOrNull;
    if (next == null) {
      final none = doses.isEmpty;
      return SurfaceCard(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: none ? paws.surfaces.subtle : paws.states.success,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: StrokeIcon(
                  none ? StrokeIconKind.medicine : StrokeIconKind.check,
                  size: 18,
                  color: none ? scheme.onSurfaceVariant : paws.states.onSuccess,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    none ? 'Nothing due today' : 'All given today',
                    style: text.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    none
                        ? 'Doses show here once ${pet.name} has a medicine.'
                        : _afterTodayNote(context, care, pet),
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
    final time = next.timeLabel;
    // "8:00 PM" → "8:00" large + "PM" small; 24 h clocks have no suffix.
    final split = time.lastIndexOf(' ');
    final clock = split < 0 ? time : time.substring(0, split);
    final suffix = split < 0 ? '' : time.substring(split + 1);
    final siblings = doses
        .where((d) => d.medicationId == next.medicationId)
        .toList();
    final medication = care.medicationById(next.medicationId);
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  dueWord(next, care.now),
                  style: text.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                'Today',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            spacing: 12,
            runSpacing: 12,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: clock),
                        if (suffix.isNotEmpty)
                          TextSpan(
                            text: ' $suffix',
                            style: TextStyle(
                              fontSize: 22,
                              letterSpacing: 0,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                    style: text.displaySmall?.copyWith(
                      fontSize: 46,
                      height: 1,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    next.title,
                    style: text.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              // Not due yet: details, never a give-now action.
              if (next.status == DoseStatus.upcoming)
                TextButton(
                  onPressed: () =>
                      context.push(AppRoutes.medication(next.medicationId)),
                  style: TextButton.styleFrom(
                    backgroundColor: paws.surfaces.subtle,
                    foregroundColor: scheme.onSurface,
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    shape: const StadiumBorder(),
                    textStyle: text.labelLarge,
                  ),
                  child: const Text('View medicine'),
                )
              else
                FilledButton(
                  onPressed: () => showLogDoseSheet(context, next),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    textStyle: text.labelLarge,
                  ),
                  child: Text(
                    next.givenById != null ? 'Review dose' : 'Mark given',
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: paws.divider),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final dose in siblings)
                _DoseChip(
                  label: dose.timeLabel,
                  given: dose.status == DoseStatus.given,
                ),
              if (medication != null && medication.isLow)
                _LowChip(left: medication.dosesLeft),
            ],
          ),
        ],
      ),
    );
  }
}

class _DoseChip extends StatelessWidget {
  const _DoseChip({required this.label, required this.given});

  final String label;
  final bool given;

  @override
  Widget build(BuildContext context) {
    final paws = context.paws;
    final scheme = Theme.of(context).colorScheme;
    final color = given ? paws.states.success : scheme.onSurface;
    return Semantics(
      label: '$label, ${given ? 'given' : 'not given yet'}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: given
              ? paws.states.success.withValues(alpha: 0.1)
              : paws.surfaces.subtle,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (given)
              StrokeIcon(StrokeIconKind.check, size: 12, color: color)
            else
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: color.withValues(alpha: 0.6),
                    width: 1.5,
                  ),
                ),
              ),
            const SizedBox(width: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: 12,
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LowChip extends StatelessWidget {
  const _LowChip({required this.left});

  final int left;

  @override
  Widget build(BuildContext context) {
    final paws = context.paws;
    return Semantics(
      label: '$left left, low supply',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: paws.amber.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          '$left left',
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(fontSize: 12, color: paws.warning),
        ),
      ),
    );
  }
}

/// Three facts in one row with hairlines between (v14 WeekStrip).
class _WeekStrip extends StatelessWidget {
  const _WeekStrip({required this.stats});

  final List<({String value, String label})> stats;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SurfaceCard(
      radius: 16,
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: IntrinsicHeight(
        child: Row(
          children: [
            for (var i = 0; i < stats.length; i++) ...[
              if (i > 0) VerticalDivider(width: 1, color: context.paws.divider),
              Expanded(
                child: Semantics(
                  label: '${stats[i].label}: ${stats[i].value}',
                  excludeSemantics: true,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            stats[i].value,
                            maxLines: 1,
                            style: text.titleMedium?.copyWith(
                              fontSize: 17,
                              fontWeight: FontWeight.w500,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                        Text(
                          stats[i].label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.labelSmall?.copyWith(
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// "Care needs" with a cream chip per condition, on one line where it fits.
class _CareNeeds extends StatelessWidget {
  const _CareNeeds({required this.conditions});

  final List<String> conditions;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 2),
            child: Text(
              'Care needs',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          for (final condition in conditions)
            DecoratedBox(
              decoration: BoxDecoration(
                color: context.paws.surfaces.card,
                borderRadius: BorderRadius.circular(999),
                boxShadow: PawsElevation.card(Theme.of(context).brightness),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                child: Text(
                  condition,
                  style: text.bodySmall?.copyWith(color: scheme.onSurface),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A medicine card (kind icon, name, schedule, supply, chevron), then a row
/// per dose today with "Give" or who gave it (v14 MedicineList).
class _MedicineCard extends StatelessWidget {
  const _MedicineCard({
    required this.care,
    required this.medication,
    required this.onTap,
  });

  final CareRepository care;
  final Medication medication;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final paws = context.paws;
    final text = Theme.of(context).textTheme;
    final doses =
        care.doses.where((d) => d.medicationId == medication.id).toList()
          ..sort((a, b) => doseMinute(a) - doseMinute(b));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SurfaceCard(
          radius: 16,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 12, 12),
              child: Row(
                children: [
                  MedicineTile(amount: medication.amount),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(medication.name, style: text.titleMedium),
                        Text(
                          medication.detail,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (medication.tracksSupply) ...[
                    const SizedBox(width: 8),
                    if (medication.isLow)
                      _LowChip(left: medication.dosesLeft)
                    else
                      Text(
                        '${medication.dosesLeft} left',
                        style: text.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                  ],
                  const SizedBox(width: 4),
                  StrokeIcon(
                    StrokeIconKind.chevronRight,
                    size: 16,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                ],
              ),
            ),
          ),
        ),
        for (final dose in doses) ...[
          const SizedBox(height: 6),
          _DoseLine(care: care, dose: dose, medication: medication, paws: paws),
        ],
      ],
    );
  }
}

/// "8:00 AM dose" with "Given by Sam at 8:04 AM" or a "Give" button.
class _DoseLine extends StatelessWidget {
  const _DoseLine({
    required this.care,
    required this.dose,
    required this.medication,
    required this.paws,
  });

  final CareRepository care;
  final Dose dose;
  final Medication medication;
  final PawsTokens paws;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final given = dose.status == DoseStatus.given;
    final unsure = dose.status == DoseStatus.due && dose.givenById != null;
    final upcoming = dose.status == DoseStatus.upcoming;
    final giver = switch (dose.givenById) {
      final id? => care.memberById(id),
      null => null,
    };
    final note = given
        ? giver == null
              ? 'Given at ${dose.givenAt}'
              : giver.isYou
              ? 'Given by you at ${dose.givenAt}'
              : 'Given by ${giver.name} at ${dose.givenAt}'
        : unsure
        ? 'Not sure if given · check first'
        : dueWord(dose, care.now);
    return SurfaceCard(
      radius: 14,
      child: InkWell(
        onTap: () => given
            ? showDoubleDoseGuard(context, dose)
            : upcoming
            ? context.push(AppRoutes.medication(dose.medicationId))
            : showLogDoseSheet(context, dose),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              if (given)
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: paws.states.success,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: StrokeIcon(
                      StrokeIconKind.check,
                      size: 14,
                      color: paws.states.onSuccess,
                    ),
                  ),
                )
              else
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: scheme.onSurface.withValues(alpha: 0.25),
                      width: 2,
                    ),
                  ),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${dose.timeLabel} dose',
                      style: text.labelLarge?.copyWith(fontSize: 14),
                    ),
                    Text(
                      note,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.labelSmall?.copyWith(
                        fontSize: 12,
                        fontWeight: given ? FontWeight.w500 : FontWeight.w400,
                        color: given
                            ? paws.states.success
                            : unsure
                            ? paws.warning
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (!given && !upcoming)
                TextButton(
                  onPressed: () => showLogDoseSheet(context, dose),
                  style: TextButton.styleFrom(
                    foregroundColor: unsure ? paws.warning : scheme.primary,
                    minimumSize: const Size(44, 44),
                    textStyle: text.labelLarge?.copyWith(fontSize: 14),
                  ),
                  child: Text(
                    unsure ? 'Check' : 'Give',
                    semanticsLabel: unsure
                        ? 'Check ${medication.name} ${dose.timeLabel} dose'
                        : 'Give ${medication.name} ${dose.timeLabel} dose',
                  ),
                )
              else
                const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddMedicineRow extends StatelessWidget {
  const _AddMedicineRow({required this.first, required this.onTap});

  /// No medicines yet: the row says what it starts.
  final bool first;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = context.paws.brandDark;
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: color,
        minimumSize: const Size.fromHeight(60),
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
                color: scheme.outline,
                strokeWidth: 1.5,
              ),
              child: Center(
                child: StrokeIcon(StrokeIconKind.plus, size: 18, color: color),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Wraps at large text instead of running off a small phone.
          Flexible(
            child: Text(
              first ? 'Add first medicine' : 'Add medicine',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
