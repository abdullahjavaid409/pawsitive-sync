import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/format/clock_format.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/care_widgets.dart';
import 'package:pawsitive_sync/core/widgets/number_stepper.dart';
import 'package:pawsitive_sync/core/widgets/paws_widgets.dart';
import 'package:pawsitive_sync/core/widgets/post_frame.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';
import 'package:pawsitive_sync/data/care_repository.dart'
    show CareRepository, dayKey;
import 'package:pawsitive_sync/data/reminder_choice.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:pawsitive_sync/ui/meds/dose_time_picker.dart';
import 'package:pawsitive_sync/ui/meds/medicine_forms.dart';
import 'package:pawsitive_sync/ui/meds/medicine_lookup.dart';
import 'package:provider/provider.dart';
import 'package:pawsitive_sync/core/widgets/system_menu.dart';

/// Add a medicine in five short steps (Magic Patterns v14 AddMedicineFlow):
/// name → form → amount → when → review. Each step asks one question; the
/// review lets any answer be changed before saving.
///
/// Rules carried over from the single-page form: Free schedules one morning
/// dose (other parts and out-of-window times open the paywall), Free's
/// medicine cap opens the paywall, Pro is re-checked at save, and saving is
/// local first (works offline; sync follows).
class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key, this.petId});
  final String? petId;

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

enum _Step { name, form, amount, schedule, review }

class _ScheduleScreenState extends State<ScheduleScreen> {
  final _name = TextEditingController();
  final _qty = TextEditingController();
  final _customUnit = TextEditingController();
  final _supply = TextEditingController();
  final _parts = <DayPart>{DayPart.morning};

  /// Times the person picked (minute of day); other parts use defaults.
  /// Kept for unselected parts too, so toggling a part off and on again
  /// doesn't lose the pick.
  final _times = <DayPart, int>{};

  var _step = _Step.name;

  /// Set when "Edit" on the review jumps back: Continue returns to review.
  var _returnToReview = false;
  MedicineForm _form = MedicineForm.tablet;

  /// Injections can be measured in units or ml; other forms have one unit.
  String _unit = MedicineForm.tablet.units.first;
  String? _petId;

  /// 1 every day, 2 every other day, 7 weekly on [_weekday].
  int _everyDays = 1;

  /// Weekly only: DateTime.monday..sunday. Defaults to today's weekday.
  int? _weekday;
  bool _withFood = false;

  /// Drops and topicals: where it's given ("Left eye").
  String _site = '';

  /// A picked last day (from the date picker); wins over [_courseDays].
  DateTime? _endDate;
  int? _courseDays;
  bool _trackSupply = false;
  bool _busy = false;
  String? _error;

  /// Dose reminders on for this phone (Settings); assumed on until read.
  bool _remindersOn = true;

  @override
  void initState() {
    super.initState();
    // Only for the review line: never promise reminders that are off.
    // ReminderChoice.read logs and swallows its own failures.
    ReminderChoice.read().then((on) {
      if (mounted && on != _remindersOn) setState(() => _remindersOn = on);
    });
    _lookup = MedicineLookup(
      context.read<CareRepository>().searchMedicinesOnline,
    )..addListener(_onLookup);
    _petId = widget.petId;
    for (final c in [_name, _qty, _customUnit, _supply]) {
      c.addListener(_refresh);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final care = context.read<CareRepository>();
      final petId = _petId ?? care.primaryPet?.id;
      if (petId != null && !care.canAddMedication(petId)) {
        // billing.paywall.opened reason=more_meds from=schedule_open.
        context.pushReplacement(
          AppRoutes.paywallWith(reason: 'more_meds', from: 'schedule_open'),
        );
      }
    });
  }

  void _refresh() => setState(() => _error = null);

  /// Phone-first name search; the server only when the phone has nothing.
  late final MedicineLookup _lookup;

  void _onLookup() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _lookup
      ..removeListener(_onLookup)
      ..dispose();
    for (final c in [_name, _qty, _customUnit, _supply]) {
      c.dispose();
    }
    super.dispose();
  }

  int _minuteFor(DayPart part) => _times[part] ?? part.defaultMinute;

  bool get _dirty =>
      _name.text.trim().isNotEmpty ||
      _qty.text.trim().isNotEmpty ||
      _supply.text.trim().isNotEmpty;

  // ---------------------------------------------------------------------------
  // Amount

  double? get _qtyValue => double.tryParse(_qty.text.trim());

  String get _unitLabel =>
      _form == MedicineForm.other ? _customUnit.text.trim() : _unit;

  /// "2 units", "½ tablet", "1 drop"; empty when no amount was entered
  /// (the medicine then reads "As prescribed").
  String get _amountText {
    final qty = _qtyValue;
    if (_qty.text.trim().isEmpty || qty == null) return '';
    return formatDose(qty, _unitLabel);
  }

  /// Blocking problems with the amount; null when it can be saved.
  String? get _amountError {
    if (_qty.text.trim().isEmpty) return null;
    final qty = _qtyValue;
    if (qty == null || qty <= 0) return 'Enter an amount greater than 0.';
    final countUnit = _form.units.isNotEmpty && _unit == _form.units.first;
    if (_form.wholeOnly && countUnit && qty != qty.roundToDouble()) {
      return 'A ${_form.units.first} can’t be split. Use a whole number.';
    }
    if (qty > 999) return 'That amount looks too large. Check the label.';
    if (_form == MedicineForm.other && _customUnit.text.trim().isEmpty) {
      return 'Add a unit, like scoop or puff.';
    }
    return null;
  }

  /// Drops and topicals must say where they go before Continue.
  String? get _siteError =>
      _form.sites.isNotEmpty && !_form.sites.contains(_site)
      ? 'Choose where it’s given.'
      : null;

  /// Unusually high for the form: a nudge to re-read the label, not a block.
  String? get _amountWarning {
    final qty = _qtyValue;
    final high = _form.highAt[_unit];
    if (_amountError != null || qty == null || high == null || qty <= high) {
      return null;
    }
    return 'That’s more than usual for ${_form.label.toLowerCase()} doses. '
        'Double-check the label before saving.';
  }

  // ---------------------------------------------------------------------------
  // Schedule

  String? get _supplyError {
    if (!_trackSupply) return null;
    final value = int.tryParse(_supply.text.trim()) ?? 0;
    return value < 1 ? 'Enter the number of doses left.' : null;
  }

  DateTime? _lastDay(DateTime start) {
    if (_endDate case final end?) return end;
    return _courseDays == null
        ? null
        : DateTime(start.year, start.month, start.day + _courseDays! - 1);
  }

  /// First dose day: today, or for weekly the next chosen weekday.
  DateTime _startDay(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    if (_everyDays != 7) return today;
    final weekday = _weekday ?? today.weekday;
    return DateTime(
      today.year,
      today.month,
      today.day + (weekday - today.weekday + 7) % 7,
    );
  }

  static const _weekdayNames = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  /// "Every day", "Every 2 days", "Mondays".
  String get _repeatText => switch (_everyDays) {
    2 => 'Every 2 days',
    7 => '${_weekdayNames[(_weekday ?? DateTime.now().weekday) - 1]}s',
    _ => 'Every day',
  };

  Future<void> _pickEndDate(DateTime now) async {
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? today.add(const Duration(days: 7)),
      firstDate: today,
      lastDate: today.add(const Duration(days: 365 * 2)),
      helpText: 'Last day to give it',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _endDate = picked;
      _courseDays = null;
    });
    AppLog.event('medication.end_picked', {
      'days': picked.difference(today).inDays + 1,
    });
  }

  String _courseSummary(BuildContext context, DateTime start) {
    final last = _lastDay(start);
    if (_endDate != null && last != null) {
      return 'Through ${MaterialLocalizations.of(context).formatMediumDate(last)}';
    }
    return last == null
        ? 'Starts today · ongoing'
        : '$_courseDays days · through '
              '${MaterialLocalizations.of(context).formatMediumDate(last)}';
  }

  String get _timesText => [
    for (final part in DayPart.values)
      if (_parts.contains(part))
        '${part.label} ${ClockFormat.label(_minuteFor(part))}',
  ].join(' · ');

  Future<void> _pickTime(DayPart part) async {
    final minute = await pickDoseTime(context, part, _minuteFor(part));
    if (minute == null || !mounted) return;
    final care = context.read<CareRepository>();
    if (!care.canUseDoseTime(part, minute)) {
      // Free keeps the morning reminder in the morning; the old time stays.
      AppLog.event('medication.add.blocked', {
        'reason': 'free_tier_time_window',
        'part': part.name,
        'from': 'schedule_time',
      });
      await context.push(
        AppRoutes.paywallWith(reason: 'more_dose_times', from: 'schedule_time'),
      );
      if (!mounted || !care.canUseDoseTime(part, minute)) return;
    }
    setState(() {
      _error = null;
      _times[part] = minute;
    });
    AppLog.event('medication.time_picked', {
      'part': part.name,
      'custom': minute != part.defaultMinute,
    });
  }

  /// Free schedules the morning dose only; picking another part opens the
  /// paywall and keeps the pick if they upgrade. Removing is always free.
  Future<void> _togglePart(CareRepository care, DayPart part) async {
    if (_parts.contains(part)) {
      setState(() {
        _error = null;
        _parts.remove(part);
      });
      return;
    }
    if (!care.canScheduleDoseParts({..._parts, part})) {
      AppLog.event('medication.add.blocked', {
        'reason': 'free_tier_times',
        'part': part.name,
        'from': 'schedule_part',
      });
      await context.push(
        AppRoutes.paywallWith(reason: 'more_dose_times', from: 'schedule_part'),
      );
      if (!mounted || !care.canScheduleDoseParts({..._parts, part})) return;
    }
    setState(() {
      _error = null;
      _parts.add(part);
    });
  }

  // ---------------------------------------------------------------------------
  // Steps

  /// Why Continue is disabled on [step]; null when the step is complete.
  String? _blocker(_Step step) => switch (step) {
    _Step.name =>
      _name.text.trim().isEmpty
          ? 'Type a name or pick one from the list'
          : null,
    _Step.form => null,
    _Step.amount => _amountError ?? _siteError,
    _Step.schedule =>
      _parts.isEmpty ? 'Select at least one time of day.' : _supplyError,
    // Review re-checks everything, in step order.
    _Step.review =>
      _blocker(_Step.name) ??
          _blocker(_Step.amount) ??
          _blocker(_Step.schedule),
  };

  void _go(_Step step) {
    FocusScope.of(context).unfocus();
    AppLog.event('medication.add.step', {'step': step.name});
    setState(() {
      _error = null;
      _step = step;
    });
  }

  void _next() {
    if (_blocker(_step) != null) return;
    if (_returnToReview && _step != _Step.review) {
      _returnToReview = false;
      _go(_Step.review);
      return;
    }
    _go(_Step.values[_step.index + 1]);
  }

  void _back() {
    if (_step == _Step.name) {
      _close();
      return;
    }
    _returnToReview = false;
    _go(_Step.values[_step.index - 1]);
  }

  /// Leaving with typed details asks first: nothing is lost by accident.
  Future<void> _close() async {
    if (_busy) return;
    if (_dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Discard this medicine?'),
          content: const Text('What you’ve entered so far won’t be saved.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialog).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialog).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(dialog).colorScheme.error,
              ),
              child: const Text('Discard'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
      AppLog.event('medication.add.discarded', {'step': _step.name});
    }
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.today);
    }
  }

  void _chooseForm(MedicineForm form) {
    if (form == _form) return;
    setState(() {
      _form = form;
      _unit = form.units.isEmpty ? '' : form.units.first;
      _site = '';
      // Keep the amount only if it still makes sense for the new form.
      final qty = _qtyValue;
      if (qty != null && form.wholeOnly && qty != qty.roundToDouble()) {
        _qty.clear();
      }
    });
  }

  /// A suggestion sets the name and form, then moves on to the amount.
  void _pickSuggestion(CommonMedicine medicine) {
    _name.text = medicine.name;
    _chooseForm(medicine.form);
    _qty.clear();
    _go(_Step.form);
  }

  Future<void> _choosePet(CareRepository care) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: context.paws.surfaces.card,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final pet in care.pets)
              ListTile(
                leading: PetPortrait(pet, size: 36),
                title: Text(pet.name),
                trailing: pet.id == (_petId ?? care.primaryPet?.id)
                    ? const StrokeIcon(StrokeIconKind.check, size: 18)
                    : null,
                onTap: () => Navigator.of(sheet).pop(pet.id),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _petId = picked);
  }

  Future<void> _save(CareRepository care, Pet pet) async {
    if (_busy) return;
    // Another pet picked here may already be at the Free cap. Everything
    // typed stays, so saving after upgrading needs no retyping.
    if (!care.canAddMedication(pet.id)) {
      AppLog.event('medication.add.blocked', {
        'reason': 'free_tier',
        'petId': pet.id,
        'from': 'schedule_save',
      });
      await context.push(
        AppRoutes.paywallWith(reason: 'more_meds', from: 'schedule_save'),
      );
      return;
    }
    // Pro can end while the flow is open (expiry, refund): a schedule picked
    // on Pro then needs Pro again, not a silent failed save.
    final morning = _times[DayPart.morning];
    if (!care.canScheduleDoseParts(_parts) ||
        (_parts.contains(DayPart.morning) &&
            morning != null &&
            !care.canUseDoseTime(DayPart.morning, morning))) {
      AppLog.event('medication.add.blocked', {
        'reason': 'free_tier_times',
        'petId': pet.id,
        'from': 'schedule_save',
      });
      await context.push(
        AppRoutes.paywallWith(reason: 'more_dose_times', from: 'schedule_save'),
      );
      return;
    }
    if (_blocker(_Step.review) case final problem?) {
      AppLog.event('medication.form_invalid', {'problem': problem});
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    HapticFeedback.lightImpact();
    final lastDay = _lastDay(care.now);
    final ok = await care.addMedication(
      petId: pet.id,
      name: _name.text,
      amount: _amountText,
      parts: [
        for (final part in DayPart.values)
          if (_parts.contains(part)) part,
      ],
      supplyTotal: _trackSupply ? int.parse(_supply.text.trim()) : 0,
      endDay: lastDay == null ? '' : dayKey(lastDay),
      times: _times,
      everyDays: _everyDays,
      withFood: _withFood,
      site: _form.sites.isEmpty ? '' : _site,
      startDay: dayKey(_startDay(care.now)),
    );
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _busy = false;
        _error = care.lastError ?? 'Could not save. Try again.';
      });
      return;
    }
    // medication.add.completed (parts, endDay, tracksSupply) is the log line.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${_name.text.trim()} is on ${pet.name}’s Today list.'),
      ),
    );
    afterThisFrame(context, () {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(AppRoutes.today);
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Build

  @override
  Widget build(BuildContext context) {
    final care = context.watch<CareRepository>();
    final pet = care.tryPetById(_petId ?? '') ?? care.primaryPet;
    if (pet == null) return _NoPet(busy: _busy);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final blocker = _blocker(_step);
    final last = _step == _Step.review;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _FlowHeader(
                    pet: pet,
                    step: _step.index,
                    steps: _Step.values.length,
                    busy: _busy,
                    onBack: _back,
                    onCancel: _step == _Step.name ? null : _close,
                    onPet: care.pets.length > 1 ? () => _choosePet(care) : null,
                  ),
                  Expanded(
                    child: AbsorbPointer(
                      absorbing: _busy,
                      child: AnimatedSwitcher(
                        duration: context.paws.motion.enter,
                        switchInCurve: Curves.easeOutCubic,
                        child: ListView(
                          key: ValueKey(_step),
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                          children: switch (_step) {
                            _Step.name => _nameStep(care, pet),
                            _Step.form => _formStep(),
                            _Step.amount => _amountStep(),
                            _Step.schedule => _scheduleStep(care, pet),
                            _Step.review => _reviewStep(care, pet),
                          },
                        ),
                      ),
                    ),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: context.paws.hairline),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_error case final error?) ...[
                            Semantics(
                              liveRegion: true,
                              child: Text(
                                error,
                                textAlign: TextAlign.center,
                                style: text.bodyMedium?.copyWith(
                                  color: scheme.error,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                          FilledButton(
                            onPressed: _busy || blocker != null
                                ? null
                                : last
                                ? () => _save(care, pet)
                                : _next,
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(52),
                              textStyle: text.titleMedium,
                            ),
                            child: _busy
                                ? SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: scheme.onPrimary,
                                      semanticsLabel: 'Saving medicine',
                                    ),
                                  )
                                : Text(
                                    last
                                        ? 'Save medicine'
                                        : _returnToReview
                                        ? 'Back to review'
                                        : 'Continue',
                                  ),
                          ),
                          if (blocker != null && !_busy) ...[
                            const SizedBox(height: 8),
                            Semantics(
                              liveRegion: true,
                              child: Text(
                                blocker,
                                textAlign: TextAlign.center,
                                style: text.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _nameStep(CareRepository care, Pet pet) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final query = _name.text.trim().toLowerCase();
    // Runs after this frame: the lookup notifies, which rebuilds.
    afterThisFrame(context, () => _lookup.update(pet.species, query));
    final duplicate = care
        .medicationsFor(pet.id)
        .where((m) => m.name.trim().toLowerCase() == query)
        .firstOrNull;
    final speciesWord = switch (pet.species) {
      Species.cat => 'cats',
      Species.dog => 'dogs',
      _ => 'pets',
    };
    return [
      const _StepTitle(
        'What’s the medicine called?',
        'Use the name on the label or the vet’s note.',
      ),
      TextField(
        contextMenuBuilder: appContextMenuBuilder,
        controller: _name,
        autofocus: true,
        maxLength: 60,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.next,
        onSubmitted: (_) => _next(),
        decoration: const InputDecoration(
          hintText: 'Search or type a name',
          counterText: '',
          prefixIcon: Padding(
            padding: EdgeInsets.all(14),
            child: StrokeIcon(StrokeIconKind.medicine, size: 20),
          ),
        ),
      ),
      if (duplicate != null) ...[
        const SizedBox(height: 10),
        _Note(
          '${pet.name} already takes ${duplicate.name}. You can still add it, '
          'for example a second strength.',
        ),
      ],
      const SizedBox(height: 24),
      FieldLabel(query.isEmpty ? 'Common for $speciesWord' : 'Suggestions'),
      MedicineSuggestionList(
        results: query.isEmpty
            ? CommonMedicine.suggestionsFor(pet.species, '')
            : _lookup.results,
        searching: query.isNotEmpty && _lookup.searching,
        typed: _name.text,
        onUseTyped: _next,
        onPick: _pickSuggestion,
      ),
      const SizedBox(height: 12),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          'Suggestions are for convenience only. Always follow your vet’s '
          'instructions.',
          style: text.bodySmall?.copyWith(
            fontSize: 12,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ),
    ];
  }

  List<Widget> _formStep() {
    return [
      const _StepTitle(
        'What form is it?',
        'Pick the closest match. It sets the right units for you.',
      ),
      LayoutBuilder(
        builder: (context, constraints) {
          // Four across on a phone; two at large text so labels fit.
          final perRow =
              MediaQuery.textScalerOf(context).scale(1) > 1.3 ||
                  constraints.maxWidth < 300
              ? 2
              : 4;
          const gap = 8.0;
          final width = (constraints.maxWidth - gap * (perRow - 1)) / perRow;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final form in MedicineForm.values)
                SizedBox(
                  width: width,
                  child: _FormTile(
                    form: form,
                    selected: form == _form,
                    onTap: () => _chooseForm(form),
                  ),
                ),
            ],
          );
        },
      ),
    ];
  }

  List<Widget> _amountStep() {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final paws = context.paws;
    final error = _amountError;
    final warning = _amountWarning;
    final qtyField = SizedBox(
      width: 156,
      child: NumberStepper(
        controller: _qty,
        semanticLabel: 'Amount per dose',
        decimal: true,
        autofocus: true,
        step: amountStep(_form, _unit),
        min: amountStep(_form, _unit),
        // No placeholder: a grey number looks like a value.
      ),
    );
    final Widget unit;
    if (_form == MedicineForm.other) {
      unit = Expanded(
        child: TextField(
          contextMenuBuilder: appContextMenuBuilder,
          controller: _customUnit,
          maxLength: 20,
          decoration: const InputDecoration(
            hintText: 'scoop, puff…',
            counterText: '',
          ),
        ),
      );
    } else if (_form.units.length > 1) {
      unit = Expanded(
        child: ChoicePills<String>(
          label: 'Unit',
          options: _form.units,
          value: _unit,
          labelOf: (u) => u,
          onChanged: (u) => setState(() => _unit = u),
        ),
      );
    } else {
      unit = Expanded(
        child: Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(
            unitWord(_qtyValue ?? 1, _unit),
            style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      );
    }
    return [
      _StepTitle(
        'How much each time?',
        'Check the label for ${_name.text.trim()}. Leave it blank to follow '
            'the vet’s instructions as written.',
      ),
      const FieldLabel('Amount · optional'),
      Row(children: [qtyField, const SizedBox(width: 10), unit]),
      // Quick amounts are counts of the form's own unit, not mg.
      if (_form.quick.isNotEmpty && _unit == _form.units.first) ...[
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final q in _form.quick)
              _QuickChip(
                label: formatAmount(double.parse(q)),
                selected: _qty.text.trim() == q,
                onTap: () {
                  _qty.text = q;
                  _qty.selection = TextSelection.collapsed(offset: q.length);
                },
              ),
          ],
        ),
      ],
      if (_form.sites.isNotEmpty) ...[
        const SizedBox(height: 24),
        const FieldLabel('Where'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final site in _form.sites)
              _QuickChip(
                label: site,
                selected: _site == site,
                onTap: () => setState(() => _site = site),
              ),
          ],
        ),
      ],
      if (error != null) ...[
        const SizedBox(height: 10),
        Semantics(
          liveRegion: true,
          child: Text(
            error,
            style: text.bodySmall?.copyWith(color: scheme.error),
          ),
        ),
      ] else if (warning != null) ...[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: paws.warningBg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            warning,
            style: text.bodySmall?.copyWith(color: paws.warning),
          ),
        ),
      ],
    ];
  }

  List<Widget> _scheduleStep(CareRepository care, Pet pet) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final paws = context.paws;
    final courses = <(String, int?)>[
      ('Ongoing', null),
      ('7 days', 7),
      ('14 days', 14),
      ('30 days', 30),
    ];
    return [
      _StepTitle(
        'When does ${pet.name} take it?',
        'Reminders go to everyone in the household.',
      ),
      const FieldLabel('How often'),
      ChoicePills<int>(
        label: 'How often',
        options: Medication.repeatOptions,
        value: _everyDays,
        labelOf: (days) => switch (days) {
          2 => 'Every 2 days',
          7 => 'Once a week',
          _ => 'Every day',
        },
        onChanged: (days) => setState(() {
          _everyDays = days;
          if (days == 7) _weekday ??= care.now.weekday;
        }),
      ),
      if (_everyDays == 7) ...[
        const SizedBox(height: 12),
        _WeekdayPicker(
          value: _weekday ?? care.now.weekday,
          onChanged: (day) => setState(() => _weekday = day),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'First dose ${MaterialLocalizations.of(context).formatMediumDate(_startDay(care.now))}.',
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      ],
      const SizedBox(height: 24),
      const FieldLabel('At what time'),
      SurfaceCard(
        child: Column(
          children: [
            for (final (i, part) in DayPart.values.indexed)
              _TimeRow(
                key: ValueKey('part-${part.name}'),
                part: part,
                time: ClockFormat.label(_minuteFor(part)),
                selected: _parts.contains(part),
                locked: !care.canScheduleDoseParts({part}),
                divider: i < DayPart.values.length - 1,
                onToggle: () => _togglePart(care, part),
                onTime: _parts.contains(part) ? () => _pickTime(part) : null,
              ),
          ],
        ),
      ),
      if (!care.isPro) ...[
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'Free includes one morning dose (4 AM to noon) and its reminder. '
            'Pro adds afternoon, evening and any time.',
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      ],
      const SizedBox(height: 24),
      const FieldLabel('How long'),
      ChoicePills<int?>(
        label: 'Course length',
        options: [for (final c in courses) c.$2],
        // A picked date shows as no chip selected.
        value: _endDate == null ? _courseDays : -1,
        labelOf: (days) => courses.firstWhere((c) => c.$2 == days).$1,
        onChanged: (days) => setState(() {
          _courseDays = days;
          _endDate = null;
        }),
      ),
      const SizedBox(height: 4),
      Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                _courseSummary(context, care.now),
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ),
          TextButton(
            onPressed: () => _pickEndDate(care.now),
            style: TextButton.styleFrom(foregroundColor: scheme.primary),
            child: Text(_endDate == null ? 'Pick a date' : 'Change date'),
          ),
        ],
      ),
      const SizedBox(height: 16),
      SurfaceCard(
        child: SwitchListTile(
          value: _withFood,
          contentPadding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
          title: Text('Give with food', style: text.titleMedium),
          subtitle: Text(
            'Shown as a reminder on every dose.',
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          onChanged: (value) => setState(() => _withFood = value),
        ),
      ),
      const SizedBox(height: 24),
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile(
              value: _trackSupply,
              contentPadding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
              title: Text('Track remaining doses', style: text.titleMedium),
              subtitle: Text(
                'Optional · see when a refill is needed.',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              onChanged: (value) => setState(() => _trackSupply = value),
            ),
            if (_trackSupply)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Divider(height: 1, color: paws.divider),
                    const SizedBox(height: 14),
                    const FieldLabel('Doses remaining'),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: SizedBox(
                        width: 156,
                        child: NumberStepper(
                          controller: _supply,
                          semanticLabel: 'Doses remaining',
                          min: 1,
                          max: 9999,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        'Count complete doses, not individual tablets.',
                        style: text.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _reviewStep(CareRepository care, Pet pet) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final paws = context.paws;
    final lastDay = _lastDay(care.now);
    final rows = <(String, String, _Step)>[
      ('Form', _form.label, _Step.form),
      (
        'Each dose',
        _amountText.isEmpty ? 'As prescribed' : _amountText,
        _Step.amount,
      ),
      ('Schedule', '$_repeatText · $_timesText', _Step.schedule),
      if (_form.sites.isNotEmpty) ('Where', _site, _Step.amount),
      ('With food', _withFood ? 'Yes' : 'No', _Step.schedule),
      (
        'Ends',
        lastDay == null
            ? 'Ongoing'
            : MaterialLocalizations.of(context).formatMediumDate(lastDay),
        _Step.schedule,
      ),
      (
        'On hand',
        _trackSupply ? '${_supply.text.trim()} doses' : 'Not tracked',
        _Step.schedule,
      ),
    ];
    return [
      const _StepTitle('Look right?', 'You can change any of this later.'),
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  MedicineFormIcon(form: _form, size: 52),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _name.text.trim(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: text.headlineSmall,
                        ),
                        Text(
                          'For ${pet.name}',
                          style: text.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            for (final (label, value, step) in rows)
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: paws.divider)),
                ),
                child: Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 84,
                        child: Text(
                          label,
                          style: text.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            value,
                            style: text.bodyMedium?.copyWith(
                              color: scheme.onSurface,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          _returnToReview = true;
                          _go(step);
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: scheme.primary,
                          minimumSize: const Size(44, 44),
                        ),
                        child: Text(
                          'Edit',
                          semanticsLabel: 'Edit ${label.toLowerCase()}',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          care.isConnected
              ? 'Everyone in the household will see ${_name.text.trim()} and '
                    'get its reminders.'
              : _remindersOn
              ? 'It shows on Today with a reminder at each time.'
              : 'It shows on Today. Turn on reminders in Settings to get a '
                    'nudge at each time.',
          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ),
    ];
  }
}

/// Close/back, a "For Miso" pill (tap to switch pet), Cancel, and a clay
/// progress bar (v14 AddMedicineFlow header).
class _FlowHeader extends StatelessWidget {
  const _FlowHeader({
    required this.pet,
    required this.step,
    required this.steps,
    required this.busy,
    required this.onBack,
    required this.onCancel,
    required this.onPet,
  });

  final Pet pet;
  final int step;
  final int steps;
  final bool busy;
  final VoidCallback onBack;
  final VoidCallback? onCancel;

  /// Null with a single pet: the pill is a label, not a control.
  final VoidCallback? onPet;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final paws = context.paws;
    final pill = Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
      decoration: BoxDecoration(
        color: paws.surfaces.card,
        borderRadius: BorderRadius.circular(999),
        boxShadow: PawsElevation.card(Theme.of(context).brightness),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PetPortrait(pet, size: 24),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'For ${pet.name}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.labelLarge?.copyWith(fontSize: 13),
            ),
          ),
          if (onPet != null) ...[
            const SizedBox(width: 4),
            Icon(Icons.expand_more, size: 16, color: scheme.onSurfaceVariant),
          ],
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                tooltip: step == 0 ? 'Close' : 'Back',
                onPressed: busy ? null : onBack,
                icon: StrokeIcon(
                  step == 0 ? StrokeIconKind.close : StrokeIconKind.chevronLeft,
                  size: 20,
                ),
              ),
              Expanded(
                child: Center(
                  child: onPet == null
                      ? pill
                      : Semantics(
                          button: true,
                          label: 'For ${pet.name}, change pet',
                          excludeSemantics: true,
                          child: GestureDetector(
                            onTap: busy ? null : onPet,
                            child: pill,
                          ),
                        ),
                ),
              ),
              SizedBox(
                width: 88,
                child: onCancel == null
                    ? null
                    : TextButton(
                        onPressed: busy ? null : onCancel,
                        style: TextButton.styleFrom(
                          foregroundColor: scheme.onSurfaceVariant,
                        ),
                        child: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('Cancel', maxLines: 1),
                        ),
                      ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Semantics(
            label: 'Step ${step + 1} of $steps',
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  for (var i = 0; i < steps; i++) ...[
                    if (i > 0) const SizedBox(width: 4),
                    Expanded(
                      child: AnimatedContainer(
                        duration: paws.motion.enter,
                        height: 4,
                        decoration: BoxDecoration(
                          color: i <= step
                              ? scheme.primary
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
        ],
      ),
    );
  }
}

class _StepTitle extends StatelessWidget {
  const _StepTitle(this.title, this.subtitle);

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

class _Note extends StatelessWidget {
  const _Note(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(Icons.info_outline, size: 14, color: scheme.onSurface),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            message,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: scheme.onSurface),
          ),
        ),
      ],
    );
  }
}

class _FormTile extends StatelessWidget {
  const _FormTile({
    required this.form,
    required this.selected,
    required this.onTap,
  });

  final MedicineForm form;
  final bool selected;
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
      label: form.label,
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
              padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
              child: Column(
                children: [
                  AnimatedScale(
                    scale: selected ? 1.06 : 1,
                    duration: paws.motion.micro,
                    child: MedicineFormIcon(form: form, size: 44),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    form.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall?.copyWith(
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: selected ? scheme.primary : scheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickChip extends StatelessWidget {
  const _QuickChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final paws = context.paws;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Amount $label',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        // Sized by its label: no alignment, so the Wrap can flow chips.
        child: AnimatedContainer(
          duration: paws.motion.micro,
          constraints: const BoxConstraints(minWidth: 48, minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? scheme.onSurface : paws.surfaces.card,
            borderRadius: BorderRadius.circular(999),
            boxShadow: selected
                ? null
                : PawsElevation.card(Theme.of(context).brightness),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
              color: selected ? scheme.surface : scheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

/// Seven round day buttons, Monday first (v14 weekly picker).
class _WeekdayPicker extends StatelessWidget {
  const _WeekdayPicker({required this.value, required this.onChanged});

  /// DateTime.monday..DateTime.sunday.
  final int value;
  final ValueChanged<int> onChanged;

  static const _names = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final paws = context.paws;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (var day = 1; day <= 7; day++)
          Semantics(
            inMutuallyExclusiveGroup: true,
            checked: day == value,
            button: true,
            label: _names[day - 1],
            excludeSemantics: true,
            child: GestureDetector(
              onTap: () => onChanged(day),
              child: AnimatedContainer(
                duration: paws.motion.micro,
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: day == value ? scheme.onSurface : paws.surfaces.card,
                  boxShadow: day == value
                      ? null
                      : PawsElevation.card(Theme.of(context).brightness),
                ),
                child: Text(
                  _names[day - 1][0],
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: day == value ? scheme.surface : scheme.onSurface,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// "Morning   8:00 AM ›   ○" — tap the row to include it, the time to
/// change it. Free sees a lock on parts that need Pro.
class _TimeRow extends StatelessWidget {
  const _TimeRow({
    super.key,
    required this.part,
    required this.time,
    required this.selected,
    required this.locked,
    required this.divider,
    required this.onToggle,
    required this.onTime,
  });

  final DayPart part;
  final String time;
  final bool selected;
  final bool locked;
  final bool divider;
  final VoidCallback onToggle;

  /// Null when the part isn't selected: its time can't be changed yet.
  final VoidCallback? onTime;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final paws = context.paws;
    final indicator = locked && !selected
        ? StrokeIcon(
            StrokeIconKind.lock,
            size: 16,
            color: scheme.onSurfaceVariant,
          )
        : CheckMark(selected: selected);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: divider
            ? Border(bottom: BorderSide(color: paws.divider))
            : null,
      ),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              button: true,
              checked: selected,
              label: '${part.label}, $time${locked ? ', Pro' : ''}',
              excludeSemantics: true,
              child: InkWell(
                onTap: onToggle,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 56),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                    child: Row(
                      children: [
                        StrokeIcon(
                          switch (part) {
                            DayPart.morning => StrokeIconKind.sunrise,
                            DayPart.afternoon => StrokeIconKind.sun,
                            DayPart.evening => StrokeIconKind.moon,
                          },
                          size: 20,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(part.label, style: text.bodyLarge),
                        ),
                        indicator,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          // The time sits apart from the toggle so each has its own target.
          TextButton(
            onPressed: onTime,
            style: TextButton.styleFrom(
              foregroundColor: scheme.primary,
              minimumSize: const Size(88, 44),
              textStyle: text.bodyMedium?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            child: Text(
              time,
              semanticsLabel: 'Change ${part.label.toLowerCase()} time, $time',
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

/// No pet yet: medicines belong to a pet, so add one first.
class _NoPet extends StatelessWidget {
  const _NoPet({required this.busy});

  final bool busy;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      bottom: false,
      child: ListView(
        padding: carePagePaddingOf(context),
        children: [
          CarePageHeader(
            title: 'Add medicine',
            subtitle: 'Add a pet before adding medicine.',
            leading: CareBackButton(
              fallbackRoute: AppRoutes.today,
              enabled: !busy,
            ),
          ),
          const SizedBox(height: 24),
          CareEmptyState(
            title: 'Who are we caring for?',
            description: 'Add your pet first to keep their medicines and doses together.',
            action: 'Add a pet',
            onAction: () => context.pushReplacement(AppRoutes.addPet),
          ),
        ],
      ),
    ),
  );
}
