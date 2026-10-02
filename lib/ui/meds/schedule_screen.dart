import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:provider/provider.dart';

/// Adds a repeating medicine: name, amount, times of day, and optional supply.
class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key, this.petId});

  final String? petId;

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  static const _suggestions = [
    'Apoquel',
    'Carprofen',
    'Gabapentin',
    'Insulin',
    'Heartworm',
    'Flea & tick',
    'Antibiotic',
    'Eye drops',
  ];

  final _name = TextEditingController();
  final _amount = TextEditingController();
  final _supply = TextEditingController();
  final _parts = <DayPart>{DayPart.morning};
  String? _petId;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _petId = widget.petId;
    _name.addListener(_refresh);
    _amount.addListener(_refresh);
  }

  void _refresh() => setState(() => _error = null);

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _supply.dispose();
    super.dispose();
  }

  Future<void> _save(CareRepository care, Pet pet) async {
    if (_busy) return;
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Add the medicine name.');
      return;
    }
    if (_parts.isEmpty) {
      setState(() => _error = 'Pick at least one time of day.');
      return;
    }
    setState(() => _busy = true);
    HapticFeedback.lightImpact();
    final ok = await care.addMedication(
      petId: pet.id,
      name: _name.text,
      amount: _amount.text,
      parts: _parts.toList(),
      supplyTotal: int.tryParse(_supply.text.trim()) ?? 0,
    );
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _busy = false;
        _error = care.lastError ?? 'Could not save. Try again.';
      });
      return;
    }
    AppLog.event('medication.saved', {'parts': _parts.length});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${_name.text.trim()} is on ${pet.name}’s Today list.'),
      ),
    );
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.today);
    }
  }

  @override
  Widget build(BuildContext context) {
    final care = context.watch<CareRepository>();
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.paws;
    final text = Theme.of(context).textTheme;
    final pet =
        (_petId == null ? null : care.tryPetById(_petId!)) ?? care.primaryPet;

    final header = Row(
      children: [
        IconButton(
          tooltip: 'Back',
          onPressed: () => context.canPop()
              ? context.pop()
              : context.go(AppRoutes.today),
          icon: StrokeIcon(StrokeIconKind.chevronLeft, color: scheme.onSurface),
        ),
        Expanded(
          child: Text(
            'Add medicine',
            textAlign: TextAlign.center,
            style: text.titleMedium,
          ),
        ),
        const SizedBox(width: 48),
      ],
    );

    if (pet == null) {
      return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                const SizedBox(height: 24),
                Text('Add your pet first', style: text.headlineMedium),
                const SizedBox(height: 8),
                Text(
                  'Medicines belong to a pet, so we know whose dose it is.',
                  style: text.bodyLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () => context.pushReplacement(AppRoutes.addPet),
                  child: const Text('Add a pet'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final name = _name.text.trim();
    final preview = Medication(
      id: 'preview',
      petId: pet.id,
      name: name.isEmpty ? 'Medicine' : name,
      amount: _amount.text.trim(),
      parts: [for (final part in DayPart.values) if (_parts.contains(part)) part],
      supplyTotal: 0,
      dosesLeft: 0,
      startDay: '',
    );

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: header,
            ),
            Expanded(
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                children: [
                  if (care.pets.length > 1) ...[
                    Text('For', style: text.titleSmall),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final item in care.pets)
                          ChoiceChip(
                            label: Text(item.name),
                            selected: item.id == pet.id,
                            onSelected: (_) => setState(() => _petId = item.id),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                  ] else ...[
                    Text(
                      'For ${pet.name}',
                      style: text.bodyLarge?.copyWith(
                        color: tokens.brandDark,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                  Text('What medicine?', style: text.headlineSmall),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _name,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    maxLength: 60,
                    decoration: const InputDecoration(
                      hintText: 'Medicine name',
                      counterText: '',
                    ),
                  ),
                  if (name.isEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final suggestion in _suggestions)
                          ActionChip(
                            label: Text(suggestion),
                            onPressed: () {
                              _name.text = suggestion;
                              _name.selection = TextSelection.collapsed(
                                offset: suggestion.length,
                              );
                            },
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 20),
                  Text('How much each time?', style: text.titleSmall),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _amount,
                    textInputAction: TextInputAction.done,
                    maxLength: 40,
                    decoration: const InputDecoration(
                      hintText: 'e.g. 1 tablet, 2 units (optional)',
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text('When is it given?', style: text.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    'Tap every time of day it is due.',
                    style: text.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      for (final part in DayPart.values) ...[
                        Expanded(
                          child: _PartTile(
                            part: part,
                            selected: _parts.contains(part),
                            onPressed: () => setState(() {
                              _error = null;
                              if (!_parts.remove(part)) _parts.add(part);
                            }),
                          ),
                        ),
                        if (part != DayPart.evening) const SizedBox(width: 8),
                      ],
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text('Doses in the box', style: text.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    'Optional. We warn everyone before it runs out.',
                    style: text.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _supply,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(4),
                    ],
                    decoration: const InputDecoration(hintText: 'e.g. 30'),
                  ),
                  const SizedBox(height: 24),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: tokens.brandSoft,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ON TODAY IT WILL SHOW',
                            style: text.labelSmall?.copyWith(
                              color: tokens.brandDark,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            preview.amount.isEmpty
                                ? preview.name
                                : '${preview.name} · ${preview.amount}',
                            style: text.titleMedium,
                          ),
                          Text(
                            _parts.isEmpty
                                ? 'Pick a time of day'
                                : '${pet.name} · ${preview.whenLabel.toLowerCase()}',
                            style: text.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null) ...[
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: text.bodyMedium?.copyWith(color: scheme.error),
                    ),
                    const SizedBox(height: 8),
                  ],
                  FilledButton(
                    onPressed: _busy ? null : () => _save(care, pet),
                    child: _busy
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save medicine'),
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

class _PartTile extends StatelessWidget {
  const _PartTile({
    required this.part,
    required this.selected,
    required this.onPressed,
  });

  final DayPart part;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.paws;
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      selected: selected,
      label: '${part.label}, ${part.timeLabel}',
      child: Material(
        color: selected ? tokens.brandSoft : scheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(14),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 84),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    selected ? Icons.check_circle : Icons.circle_outlined,
                    size: 22,
                    color: selected ? scheme.primary : scheme.outline,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    part.label,
                    style: text.titleSmall?.copyWith(
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                  Text(part.timeLabel, style: text.bodySmall),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
