import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/layout/app_art_size.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/care_widgets.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';
import 'package:pawsitive_sync/data/care_repository.dart'
    show CareRepository, dayKey;
import 'package:pawsitive_sync/domain/models.dart';
import 'package:provider/provider.dart';

/// A daily medicine routine, with optional tracking of complete doses left.
class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key, this.petId});
  final String? petId;

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  final _form = GlobalKey<FormState>();
  final _nameField = GlobalKey<FormFieldState<String>>();
  final _scheduleKey = GlobalKey();
  final _supplyField = GlobalKey<FormFieldState<String>>();
  final _name = TextEditingController();
  final _amount = TextEditingController();
  final _supply = TextEditingController();
  final _parts = <DayPart>{DayPart.morning};
  String? _petId;
  int? _courseDays;
  bool _trackSupply = false;
  bool _attemptedSave = false;
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

  DateTime? _lastDay(DateTime start) => _courseDays == null
      ? null
      : DateTime(start.year, start.month, start.day + _courseDays! - 1);

  String _courseSummary(BuildContext context, DateTime start) {
    final last = _lastDay(start);
    return last == null
        ? 'Starts today · ongoing'
        : '$_courseDays days · through ${MaterialLocalizations.of(context).formatMediumDate(last)}';
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _supply.dispose();
    super.dispose();
  }

  Future<void> _save(CareRepository care, Pet pet) async {
    if (_busy) return;
    setState(() => _attemptedSave = true);
    final validFields = _form.currentState!.validate();
    if (!validFields || _parts.isEmpty) {
      final target = _nameField.currentState?.hasError == true
          ? _nameField.currentContext
          : _parts.isEmpty
          ? _scheduleKey.currentContext
          : _supplyField.currentContext;
      if (target != null) {
        await Scrollable.ensureVisible(target, alignment: 0.2);
      }
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    HapticFeedback.lightImpact();
    final lastDay = _lastDay(care.now);
    final endDay = lastDay == null ? '' : dayKey(lastDay);
    final ok = await care.addMedication(
      petId: pet.id,
      name: _name.text,
      amount: _amount.text,
      parts: _parts.toList(),
      supplyTotal: _trackSupply ? int.parse(_supply.text.trim()) : 0,
      endDay: endDay,
    );
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _busy = false;
        _error = care.lastError ?? 'Could not save. Try again.';
      });
      return;
    }
    AppLog.event('medication.saved', {
      'parts': _parts.length,
      'courseDays': _courseDays ?? 'ongoing',
      'tracksSupply': _trackSupply,
    });
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
    final text = Theme.of(context).textTheme;
    final pet = care.tryPetById(_petId ?? '') ?? care.primaryPet;
    final name = _name.text.trim();

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: pet == null
                ? ListView(
                    padding: carePagePaddingOf(context),
                    children: [
                      CarePageHeader(
                        title: 'Daily care',
                        subtitle: 'Add a pet before adding medicine.',
                        leading: CareBackButton(
                          fallbackRoute: AppRoutes.today,
                          enabled: !_busy,
                        ),
                      ),
                      const SizedBox(height: 24),
                      CareEmptyState(
                        title: 'Who are we caring for?',
                        description: 'Add your pet first to keep their medicines and doses together.',
                        action: 'Add a pet',
                        onAction: () =>
                            context.pushReplacement(AppRoutes.addPet),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      Expanded(
                        child: AbsorbPointer(
                          absorbing: _busy,
                          child: Form(
                            key: _form,
                            autovalidateMode: _attemptedSave
                                ? AutovalidateMode.onUserInteraction
                                : AutovalidateMode.disabled,
                            child: ListView(
                              keyboardDismissBehavior:
                                  ScrollViewKeyboardDismissBehavior.onDrag,
                              padding: const EdgeInsets.fromLTRB(
                                24,
                                12,
                                24,
                                24,
                              ),
                               children: [
                                 CarePageHeader(
                                   title: 'Add medicine',
                                   subtitle: 'A simple routine for ${pet.name}.',
                                   leading: CareBackButton(
                                     fallbackRoute: AppRoutes.today,
                                     enabled: !_busy,
                                   ),
                                   action: PetPortrait(pet, size: 58),
                                 ),
                                if (care.pets.length > 1) ...[
                                  const SizedBox(height: 20),
                                  CarePetPicker(
                                    pets: care.pets,
                                    selectedId: pet.id,
                                    onSelected: (id) =>
                                        setState(() => _petId = id),
                                  ),
                                ],
                                const SizedBox(height: 28),
                                const CareSectionHeader('Medicine details'),
                                const SizedBox(height: 18),
                                const _FieldLabel('Medicine name'),
                                const SizedBox(height: 8),
                                TextFormField(
                                  key: _nameField,
                                  controller: _name,
                                  textCapitalization: TextCapitalization.words,
                                  textInputAction: TextInputAction.next,
                                  maxLength: 60,
                                  decoration: const InputDecoration(
                                    hintText: 'e.g. Apoquel',
                                    counterText: '',
                                    prefixIcon: Padding(
                                      padding: EdgeInsets.all(14),
                                      child: StrokeIcon(
                                        StrokeIconKind.medicine,
                                        size: 22,
                                      ),
                                    ),
                                    errorMaxLines: 3,
                                  ),
                                  validator: (value) =>
                                      value == null || value.trim().isEmpty
                                      ? 'Enter the medicine name.'
                                      : null,
                                ),
                                const SizedBox(height: 18),
                                const _FieldLabel(
                                  'Amount per dose',
                                  optional: true,
                                ),
                                const SizedBox(height: 8),
                                TextFormField(
                                  controller: _amount,
                                  textInputAction: TextInputAction.done,
                                  maxLength: 40,
                                  decoration: const InputDecoration(
                                    hintText: 'e.g. 1 tablet or 2 units',
                                    counterText: '',
                                    helperText: 'Use the amount in your vet’s instructions.',
                                    helperMaxLines: 3,
                                  ),
                                  onFieldSubmitted: (_) =>
                                      FocusScope.of(context).unfocus(),
                                ),
                                const SizedBox(height: 28),
                                CareSectionHeader(
                                  'Daily schedule',
                                  key: _scheduleKey,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Repeats every day. Select each time it’s given.',
                                  style: text.bodyLarge?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                LayoutBuilder(
                                  builder: (context, constraints) {
                                    final stacked =
                                        constraints.maxWidth < 310 ||
                                        MediaQuery.textScalerOf(context)
                                                .scale(14) >
                                            18;
                                    final tiles = [
                                      for (final part in DayPart.values)
                                        _PartTile(
                                          part: part,
                                          selected: _parts.contains(part),
                                          horizontal: stacked,
                                          onPressed: () => setState(() {
                                            _error = null;
                                            if (!_parts.remove(part)) {
                                              _parts.add(part);
                                            }
                                          }),
                                        ),
                                    ];
                                    return stacked
                                        ? Column(
                                            children: [
                                              for (final tile in tiles)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        bottom: 8,
                                                      ),
                                                  child: tile,
                                                ),
                                            ],
                                          )
                                        : Row(
                                            children: [
                                              for (
                                                var i = 0;
                                                i < tiles.length;
                                                i++
                                              ) ...[
                                                Expanded(child: tiles[i]),
                                                if (i < tiles.length - 1)
                                                  const SizedBox(width: 8),
                                              ],
                                            ],
                                          );
                                  },
                                ),
                                if (_attemptedSave && _parts.isEmpty) ...[
                                  const SizedBox(height: 8),
                                  Semantics(
                                    liveRegion: true,
                                    child: Text(
                                      'Select at least one time of day.',
                                      style: text.bodyMedium?.copyWith(
                                        color: scheme.error,
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 28),
                                const CareSectionHeader('Course length'),
                                const SizedBox(height: 8),
                                Text(
                                  'Starts today. Use the duration in your vet’s instructions.',
                                  style: text.bodyLarge?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final (label, days) in [
                                      ('Ongoing', null),
                                      ('7 days', 7),
                                      ('14 days', 14),
                                      ('30 days', 30),
                                    ])
                                      ChoiceChip(
                                        label: Text(label),
                                        selected: _courseDays == days,
                                        selectedColor: context.paws.brandSoft,
                                        checkmarkColor: context.paws.brandDark,
                                        labelStyle: text.titleSmall?.copyWith(
                                          color: _courseDays == days
                                              ? context.paws.brandDark
                                              : scheme.onSurfaceVariant,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                        ),
                                        side: BorderSide(
                                          color: _courseDays == days
                                              ? scheme.primary
                                              : scheme.outlineVariant,
                                        ),
                                        onSelected: (_) =>
                                            setState(() => _courseDays = days),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  _courseSummary(context, care.now),
                                  style: text.bodyMedium,
                                ),
                                const SizedBox(height: 28),
                                Material(
                                  color: scheme.surfaceContainerLowest,
                                  clipBehavior: Clip.antiAlias,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                    side: BorderSide(
                                      color: scheme.outlineVariant,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      SwitchListTile.adaptive(
                                        value: _trackSupply,
                                        contentPadding:
                                            const EdgeInsets.fromLTRB(
                                              16,
                                              8,
                                              12,
                                              8,
                                            ),
                                        title: Text(
                                          'Track remaining doses',
                                          style: text.titleMedium,
                                        ),
                                        subtitle: const Padding(
                                          padding: EdgeInsets.only(top: 4),
                                          child: Text(
                                            'Optional · see when a refill is needed.',
                                          ),
                                        ),
                                        onChanged: (value) => setState(
                                          () => _trackSupply = value,
                                        ),
                                      ),
                                      if (_trackSupply)
                                        Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                            16,
                                            0,
                                            16,
                                            18,
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              const Divider(),
                                              const SizedBox(height: 16),
                                              const _FieldLabel(
                                                'Doses remaining',
                                              ),
                                              const SizedBox(height: 8),
                                              TextFormField(
                                                key: _supplyField,
                                                controller: _supply,
                                                keyboardType:
                                                    TextInputType.number,
                                                textInputAction:
                                                    TextInputAction.done,
                                                inputFormatters: [
                                                  FilteringTextInputFormatter
                                                      .digitsOnly,
                                                  LengthLimitingTextInputFormatter(
                                                    4,
                                                  ),
                                                ],
                                                decoration:
                                                    const InputDecoration(
                                                      hintText: 'e.g. 30',
                                                      errorMaxLines: 3,
                                                      helperText: 'Count complete doses, not individual tablets.',
                                                      helperMaxLines: 3,
                                                    ),
                                                validator: (value) =>
                                                    (int.tryParse(
                                                              value?.trim() ??
                                                                  '',
                                                            ) ??
                                                            0) <
                                                        1
                                                    ? 'Enter the number of doses left.'
                                                    : null,
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                if (name.isNotEmpty && _parts.isNotEmpty) ...[
                                  const SizedBox(height: 20),
                                  Container(
                                    padding: const EdgeInsets.all(18),
                                    decoration: BoxDecoration(
                                      color: context.paws.brandSoft,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        StrokeIcon(
                                          StrokeIconKind.calendar,
                                          size: 22,
                                          color: context.paws.brandDark,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Your daily routine',
                                                style: text.labelSmall
                                                    ?.copyWith(
                                                      color: context
                                                          .paws
                                                          .brandDark,
                                                    ),
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                _amount.text.trim().isEmpty
                                                    ? name
                                                    : '$name · ${_amount.text.trim()}',
                                                style: text.titleMedium,
                                              ),
                                              const SizedBox(height: 5),
                                              Text(
                                                '${pet.name} · ${[for (final part in DayPart.values)
                                                  if (_parts.contains(part)) part.label].join(' & ')}',
                                                style: text.bodyMedium,
                                              ),
                                              const SizedBox(height: 5),
                                              Text(
                                                _courseSummary(
                                                  context,
                                                  care.now,
                                                ),
                                                style: text.bodyMedium,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          color: scheme.surface,
                          border: Border(
                            top: BorderSide(color: scheme.outlineVariant),
                          ),
                        ),
                        padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_error != null) ...[
                              Semantics(
                                liveRegion: true,
                                child: Text(
                                  _error!,
                                  style: text.bodyMedium?.copyWith(
                                    color: scheme.error,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],
                            FilledButton(
                              onPressed: _busy ? null : () => _save(care, pet),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(54),
                              ),
                              child: _busy
                                  ? SizedBox.square(
                                      dimension: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: scheme.onPrimary,
                                        semanticsLabel: 'Saving medicine',
                                      ),
                                    )
                                  : const Text('Save medicine'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label, {this.optional = false});
  final String label;
  final bool optional;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 4,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Text(label, style: Theme.of(context).textTheme.titleSmall),
      if (optional)
        Text('Optional', style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}

class _PartTile extends StatelessWidget {
  const _PartTile({
    required this.part,
    required this.selected,
    required this.onPressed,
    required this.horizontal,
  });
  final DayPart part;
  final bool selected;
  final bool horizontal;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final color = selected ? context.paws.brandDark : scheme.onSurfaceVariant;
    final icon = StrokeIcon(
      switch (part) {
        DayPart.morning => StrokeIconKind.sunrise,
        DayPart.afternoon => StrokeIconKind.sun,
        DayPart.evening => StrokeIconKind.moon,
      },
      color: color,
      size: appPartIconSize(context),
    );
    final check = Container(
      width: 19,
      height: 19,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? scheme.primary : Colors.transparent,
        border: selected ? null : Border.all(color: scheme.outline),
      ),
      child: selected
          ? StrokeIcon(StrokeIconKind.check, size: 13, color: scheme.onPrimary)
          : null,
    );
    final label = Column(
      crossAxisAlignment: horizontal
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        Text(part.label, style: text.titleSmall?.copyWith(color: color)),
        const SizedBox(height: 5),
        Text(part.timeLabel, style: text.bodySmall?.copyWith(color: color)),
      ],
    );
    return Semantics(
      button: true,
      selected: selected,
      label: '${part.label}, ${part.timeLabel}',
      excludeSemantics: true,
      child: Material(
        color: selected
            ? context.paws.brandSoft
            : scheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: horizontal ? 16 : 8,
              vertical: 14,
            ),
            child: horizontal
                ? Row(
                    children: [
                      icon,
                      const SizedBox(width: 14),
                      Expanded(child: label),
                      const SizedBox(width: 8),
                      check,
                    ],
                  )
                : Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [icon, check],
                      ),
                      const SizedBox(height: 14),
                      label,
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
