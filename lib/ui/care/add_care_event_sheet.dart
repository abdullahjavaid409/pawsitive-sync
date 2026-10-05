import 'package:flutter/material.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/care_widgets.dart';
import 'package:pawsitive_sync/core/widgets/dismiss_keyboard.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:provider/provider.dart';

/// Named so the navigation log reads `nav.push to=add_care_event`.
Future<void> showAddCareEventSheet(BuildContext context, {String? petId}) {
  return showModalBottomSheet<void>(
    context: context,
    routeSettings: const RouteSettings(name: 'add_care_event'),
    isScrollControlled: true,
    useSafeArea: true,
    useRootNavigator: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) =>
        DismissKeyboard(child: _AddCareEventSheet(initialPetId: petId)),
  );
}

class _AddCareEventSheet extends StatefulWidget {
  const _AddCareEventSheet({this.initialPetId});
  final String? initialPetId;
  @override
  State<_AddCareEventSheet> createState() => _AddCareEventSheetState();
}

class _AddCareEventSheetState extends State<_AddCareEventSheet> {
  final _title = TextEditingController();
  final _note = TextEditingController();
  CareEventKind _kind = CareEventKind.vetVisit;
  late DateTime _due;
  String? _petId;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _petId = widget.initialPetId;
    final now = context.read<CareRepository>().now;
    _due = DateTime(now.year, now.month, now.day + 7);
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = context.read<CareRepository>().now;
    final picked = await showDatePicker(
      context: context,
      initialDate: _due,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 2, now.month, now.day),
    );
    if (picked != null && mounted) setState(() => _due = picked);
  }

  Future<void> _save() async {
    if (_busy) return;
    final care = context.read<CareRepository>();
    final petId = _petId ?? care.primaryPet?.id;
    if (petId == null) {
      setState(() => _error = 'Add a pet first.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await care.addCareEvent(
      petId: petId,
      title: _title.text.trim().isEmpty ? _defaultTitle(_kind) : _title.text,
      kind: _kind,
      dueDate: _due,
      note: _note.text,
    );
    if (!mounted) return;
    // care_event.added / rejected are logged by the repository.
    if (!ok) {
      setState(() {
        _busy = false;
        _error = care.lastError ?? 'Could not save. Try again.';
      });
      return;
    }
    Navigator.of(context).pop();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Care event added to Today.')));
  }

  String _defaultTitle(CareEventKind kind) => switch (kind) {
    CareEventKind.vaccine => 'Vaccine due',
    CareEventKind.vetVisit => 'Vet checkup',
    CareEventKind.refill => 'Medicine refill',
    CareEventKind.other => 'Care appointment',
  };

  @override
  Widget build(BuildContext context) {
    final care = context.watch<CareRepository>();
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final pet = care.tryPetById(_petId ?? '') ?? care.primaryPet;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The drag handle comes from the theme (showDragHandle).
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Add care event', style: text.headlineMedium),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: _busy ? null : () => Navigator.pop(context),
                    icon: const StrokeIcon(StrokeIconKind.close, size: 21),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: AbsorbPointer(
                  absorbing: _busy,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Keep upcoming dates on Today.',
                        style: text.bodyLarge?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (care.pets.length > 1)
                        CarePetPicker(
                          pets: care.pets,
                          selectedId: pet?.id,
                          onSelected: (id) => setState(() => _petId = id),
                        )
                      else if (pet != null)
                        Row(
                          children: [
                            PetPortrait(pet, size: 38),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'For ${pet.name}',
                                style: text.titleMedium,
                              ),
                            ),
                          ],
                        ),
                      const SizedBox(height: 24),
                      Text('Type of care', style: text.titleSmall),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final kind in CareEventKind.values)
                            ChoiceChip(
                              label: Text(kind.kindLabel),
                              selected: _kind == kind,
                              selectedColor: context.paws.brandSoft,
                              checkmarkColor: context.paws.brandDark,
                              labelStyle: text.titleSmall?.copyWith(
                                color: _kind == kind
                                    ? context.paws.brandDark
                                    : scheme.onSurfaceVariant,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              side: BorderSide(
                                color: _kind == kind
                                    ? scheme.primary
                                    : scheme.outlineVariant,
                              ),
                              onSelected: (_) => setState(() => _kind = kind),
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text('Event name · optional', style: text.titleSmall),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _title,
                        textCapitalization: TextCapitalization.sentences,
                        textInputAction: TextInputAction.next,
                        maxLength: 80,
                        decoration: InputDecoration(
                          hintText: _defaultTitle(_kind),
                          counterText: '',
                        ),
                      ),
                      const SizedBox(height: 16),
                      Material(
                        color: scheme.surfaceContainerLowest,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(color: scheme.outlineVariant),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: ListTile(
                          onTap: _pickDate,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 6,
                          ),
                          leading: StrokeIcon(
                            StrokeIconKind.calendar,
                            color: context.paws.brandDark,
                          ),
                          title: Text('Date', style: text.bodySmall),
                          subtitle: Text(
                            MaterialLocalizations.of(context)
                                .formatMediumDate(_due),
                            style: text.titleMedium,
                          ),
                          trailing: const StrokeIcon(
                            StrokeIconKind.chevronRight,
                            size: 20,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text('Notes · optional', style: text.titleSmall),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _note,
                        textCapitalization: TextCapitalization.sentences,
                        minLines: 2,
                        maxLines: 4,
                        maxLength: 300,
                        decoration: const InputDecoration(
                          hintText:
                              'Clinic, booking details, or anything to bring',
                          counterText: '',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null) ...[
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _error!,
                        style: text.bodyMedium?.copyWith(color: scheme.error),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  FilledButton(
                    onPressed: _busy ? null : _save,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(54),
                    ),
                    child: _busy
                        ? SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: scheme.onPrimary,
                              semanticsLabel: 'Saving care event',
                            ),
                          )
                        : const Text('Save event'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
