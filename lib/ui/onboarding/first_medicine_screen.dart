import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/format/clock_format.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/number_stepper.dart';
import 'package:pawsitive_sync/core/widgets/paws_widgets.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:pawsitive_sync/ui/meds/medicine_forms.dart';
import 'package:pawsitive_sync/ui/meds/medicine_lookup.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_view_model.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_visuals.dart';
import 'package:provider/provider.dart';
import 'package:pawsitive_sync/core/widgets/system_menu.dart';

/// v14 MedicineStep: the medicine given most often, on one page — name,
/// form, amount, how often, times, food and supply. Skippable; saved once
/// the pet exists (the paywall's finish).
class FirstMedicineScreen extends StatefulWidget {
  const FirstMedicineScreen({super.key});

  @override
  State<FirstMedicineScreen> createState() => _FirstMedicineScreenState();
}

class _FirstMedicineScreenState extends State<FirstMedicineScreen> {
  late final OnboardingViewModel _model = context.read<OnboardingViewModel>();
  late final _name = TextEditingController(text: _model.medName);
  late final _amount = TextEditingController(text: _model.medAmount);
  late final _supply = TextEditingController(text: _model.medSupply);
  late final _customUnit = TextEditingController(
    text: _model.medForm == MedicineForm.other ? _model.medUnit : '',
  );

  /// Drops and topicals: where it's given. Required for those forms.
  String _site = '';

  /// Phone-first name search (server only when the phone has nothing).
  late final MedicineLookup _lookup;

  @override
  void initState() {
    super.initState();
    _lookup = MedicineLookup(
      context.read<CareRepository>().searchMedicinesOnline,
    )..addListener(_onLookup);
  }

  /// The name came from a suggestion: hide the list until it's edited.
  String? _pickedName;

  void _onLookup() {
    if (mounted) setState(() {});
  }

  /// A suggestion fills the name and picks its form, like Add medicine.
  void _pickSuggestion(CommonMedicine medicine) {
    _name.text = medicine.name;
    _pickedName = medicine.name;
    _flagged
      ..remove(_Field.name)
      ..remove(_Field.form);
    if (medicine.form != _model.medForm || !_model.medFormPicked) {
      _amount.clear();
      _customUnit.clear();
    }
    _model.setForm(medicine.form);
    setState(() => _site = '');
    FocusScope.of(context).unfocus();
  }

  @override
  void dispose() {
    _lookup
      ..removeListener(_onLookup)
      ..dispose();
    for (final c in [_name, _amount, _supply, _customUnit]) {
      c.dispose();
    }
    super.dispose();
  }

  double? get _qty => double.tryParse(_amount.text.trim());

  /// True once Continue was tapped with something missing. Nothing is red
  /// before that: an empty form on arrival isn't a mistake.
  bool _tried = false;

  /// Fields showing a message: set by Continue, cleared as soon as that
  /// field is edited.
  final Set<_Field> _flagged = {};

  /// Scroll targets, so Continue can bring the first problem into view.
  final _keys = {for (final f in _Field.values) f: GlobalKey()};

  /// Every blocking problem at once, in screen order, so nobody fixes one
  /// thing only to be told about the next. Empty when it can be saved.
  Map<_Field, String> get _issues {
    final form = _model.medForm;
    final issues = <_Field, String>{};
    if (_name.text.trim().isEmpty) {
      issues[_Field.name] = 'Add the medicine’s name, or skip this step';
    }
    if (!_model.medFormPicked) {
      issues[_Field.form] = 'Pick the form it comes in';
      // Amount, unit and where only appear once a form is picked.
      if (!_model.medEveryPicked) issues[_Field.often] = 'Pick how often';
      return _withSupply(issues);
    }
    final qty = _qty;
    if (_amount.text.trim().isEmpty || qty == null || qty <= 0) {
      issues[_Field.amount] = 'Add how much $_petName gets each time';
    } else if (form.wholeOnly &&
        _model.medUnit == form.units.firstOrNull &&
        qty != qty.roundToDouble()) {
      issues[_Field.amount] =
          'A ${form.units.first} can’t be split. Use a whole number';
    }
    if (form == MedicineForm.other && _model.medUnit.trim().isEmpty) {
      issues[_Field.unit] = 'Add the unit, like scoop or puff';
    }
    if (form.sites.isNotEmpty && _site.isEmpty) {
      issues[_Field.site] = 'Pick where it’s given';
    }
    if (!_model.medEveryPicked) issues[_Field.often] = 'Pick how often';
    return _withSupply(issues);
  }

  Map<_Field, String> _withSupply(Map<_Field, String> issues) {
    final supply = _supply.text.trim();
    if (supply.isNotEmpty && (int.tryParse(supply) ?? 0) <= 0) {
      issues[_Field.supply] = 'Use a whole number, or leave it blank';
    }
    return issues;
  }

  String get _petName {
    final name = _model.petName.trim();
    return name.isEmpty ? 'your pet' : name;
  }

  /// One line under Continue naming everything still missing, only after
  /// Continue was tried; before that the button just reads "Continue".
  String? _summary(Map<_Field, String> issues) {
    if (!_tried || issues.isEmpty) return null;
    if (issues.length == 1) return '${issues.values.first}.';
    return 'Still needed: ${issues.keys.map((f) => f.short).join(' · ')}';
  }

  /// The field's own message, once Continue has been tried.
  Widget _errorFor(_Field field, Map<_Field, String> issues) {
    final message = issues[field];
    if (!_flagged.contains(field) || message == null) {
      return const SizedBox.shrink();
    }
    return _FieldError(message);
  }

  void _onContinue() {
    final issues = _issues;
    if (issues.isEmpty) return _continue();
    HapticFeedback.mediumImpact();
    AppLog.event('onboarding.medicine_blocked', {
      'missing': issues.keys.map((f) => f.name).join(','),
    });
    setState(() {
      _tried = true;
      _flagged
        ..clear()
        ..addAll(issues.keys);
    });
    FocusScope.of(context).unfocus();
    final target = _keys[issues.keys.first]?.currentContext;
    if (target != null) {
      Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        alignment: 0.2,
      );
    }
  }

  /// A gentle double-check above the usual amount for this unit.
  String? get _warning {
    final qty = _qty;
    // Forms with no known usual amount (Other) still get a check: few pets
    // get more than 20 of anything at once.
    final high = _model.medForm.highAt[_model.medUnit] ?? 20;
    if (qty == null || qty <= high) return null;
    return 'That’s more than usual. Check the label or your vet’s note.';
  }

  void _continue() {
    final m = _model;
    m.updateMedicine((m) {
      m.medName = _name.text.trim();
      m.medAmount = _amount.text.trim();
      m.medSupply = _supply.text.trim();
      if (m.medForm == MedicineForm.other) m.medUnit = _customUnit.text.trim();
      m.hasMedicine = true;
      m.medSite = _site;
    });
    AppLog.event('onboarding.step', {
      'step': 'medicine',
      'form': m.medForm.name,
      'parts': m.medParts.length,
      'everyDays': m.medEveryDays,
      'tracksSupply': m.medSupply.isNotEmpty,
    });
    FocusScope.of(context).unfocus();
    context.go(AppRoutes.caregivers);
  }

  void _skip() {
    _model.updateMedicine((m) => m.hasMedicine = false);
    AppLog.event('onboarding.step', {'step': 'medicine', 'skipped': true});
    FocusScope.of(context).unfocus();
    context.go(AppRoutes.caregivers);
  }

  /// Amount per dose (and where, for drops and topicals): shown once a
  /// form is picked, since units and steps depend on it.
  Widget _amountSection(
    OnboardingViewModel model,
    Map<_Field, String> issues,
    String? warning,
  ) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final form = model.medForm;
    final pet = _petName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        FieldLabel('Amount per dose', key: _keys[_Field.amount]),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
          child: Text(
            'How much $pet gets each time. Tap − or +, or type it. '
            'Check the label if unsure.',
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
        Row(
          children: [
            SizedBox(
              width: 156,
              child: NumberStepper(
                controller: _amount,
                semanticLabel: 'Amount per dose',
                decimal: true,
                step: amountStep(form, model.medUnit),
                min: amountStep(form, model.medUnit),
                // No placeholder: a grey number looks like a value.
                onChanged: (_) {
                  _flagged.remove(_Field.amount);
                  setState(() {});
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: form == MedicineForm.other
                  ? TextField(
                      contextMenuBuilder: appContextMenuBuilder,
                      controller: _customUnit,
                      maxLength: 16,
                      onChanged: (v) {
                        _flagged.remove(_Field.unit);
                        model.updateMedicine((m) => m.medUnit = v.trim());
                      },
                      onTapOutside: (_) => FocusScope.of(context).unfocus(),
                      // Same height as the stepper beside it.
                      decoration: const InputDecoration(
                        hintText: 'Unit, like scoop',
                        counterText: '',
                        constraints: BoxConstraints.tightFor(height: 52),
                        contentPadding: EdgeInsets.symmetric(horizontal: 16),
                      ),
                    )
                  : form.units.length > 1
                  ? _UnitSegments(
                      units: form.units,
                      selected: model.medUnit,
                      onSelected: (u) =>
                          model.updateMedicine((m) => m.medUnit = u),
                    )
                  : Text(
                      unitWord(_qty ?? 1, model.medUnit),
                      style: text.bodyLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
            ),
          ],
        ),
        if (form.quick.isNotEmpty &&
            model.medUnit == form.units.firstOrNull) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final q in form.quick)
                _QuickChip(
                  label: formatAmount(double.parse(q)),
                  selected: _amount.text.trim() == q,
                  onTap: () => setState(() {
                    _flagged.remove(_Field.amount);
                    _amount.text = q;
                  }),
                ),
            ],
          ),
        ],
        _errorFor(_Field.unit, issues),
        _errorFor(_Field.amount, issues),
        if (warning != null) ...[
          const SizedBox(height: 8),
          Text(
            warning,
            style: text.bodySmall?.copyWith(color: context.paws.warning),
          ),
        ],
        if (form.sites.isNotEmpty) ...[
          const SizedBox(height: 24),
          FieldLabel('Where', key: _keys[_Field.site]),
          ChoicePills<String>(
            label: 'Where',
            options: form.sites,
            value: _site.isEmpty ? null : _site,
            labelOf: (s) => s,
            onChanged: (s) => setState(() {
              _flagged.remove(_Field.site);
              _site = s;
            }),
          ),
          _errorFor(_Field.site, issues),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final model = context.watch<OnboardingViewModel>();
    final care = context.watch<CareRepository>();
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final pet = model.petName.trim().isEmpty
        ? 'your pet'
        : model.petName.trim();
    final form = model.medForm;
    final issues = _issues;
    final warning = _warning;

    return OnboardingStep(
      onBack: () => context.go(AppRoutes.pet),
      child: OnboardingShell(
        header: OnboardingHeader(
          step: 2,
          onBack: () => context.go(AppRoutes.pet),
          onSkip: _skip,
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OnboardingTitle(
              'What does $pet take?',
              'Add the medicine you give most often. The rest can wait.',
            ),
            const SizedBox(height: 28),
            FieldLabel('Medicine', key: _keys[_Field.name]),
            TextField(
              contextMenuBuilder: appContextMenuBuilder,
              controller: _name,
              maxLength: 40,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              onChanged: (value) {
                _flagged.remove(_Field.name);
                _lookup.update(model.species, value);
                setState(() {});
              },
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
              decoration: const InputDecoration(
                hintText: 'Insulin, Apoquel, eye drops…',
                counterText: '',
              ),
            ),
            _errorFor(_Field.name, issues),
            // Matches as they type; gone once one is picked.
            if (_name.text.trim().isNotEmpty && _name.text != _pickedName) ...[
              const SizedBox(height: 8),
              MedicineSuggestionList(
                results: _lookup.results.take(4).toList(),
                searching: _lookup.searching,
                onPick: _pickSuggestion,
              ),
            ],
            const SizedBox(height: 24),
            FieldLabel('Form', key: _keys[_Field.form]),
            _FormGrid(
              selected: model.medFormPicked ? form : null,
              onSelected: (f) {
                if (f != form) {
                  // A new form has its own units: an amount typed for
                  // tablets doesn't carry over to ml.
                  _amount.clear();
                  _customUnit.clear();
                  _flagged.removeAll([_Field.amount, _Field.unit]);
                }
                _flagged.remove(_Field.form);
                model.setForm(f);
                setState(() => _site = '');
              },
            ),
            _errorFor(_Field.form, issues),
            // Amount and where depend on the form, so they appear once it's
            // picked.
            AnimatedSize(
              duration: context.paws.motion.micro,
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: model.medFormPicked
                  ? _amountSection(model, issues, warning)
                  : const SizedBox(width: double.infinity),
            ),
            const SizedBox(height: 24),
            FieldLabel('How often', key: _keys[_Field.often]),
            _FrequencyGrid(
              everyDays: model.medEveryPicked ? model.medEveryDays : null,
              onChanged: (d) {
                _flagged.remove(_Field.often);
                model.updateMedicine((m) {
                  m.medEveryDays = d;
                  m.medEveryPicked = true;
                });
              },
            ),
            _errorFor(_Field.often, issues),
            const SizedBox(height: 24),
            const FieldLabel('At what time'),
            _TimesCard(
              parts: model.medParts,
              canUse: (part) => care.canScheduleDoseParts({part}),
              onToggle: (part) => model.updateMedicine((m) {
                // At least one time stays picked.
                if (m.medParts.contains(part)) {
                  if (m.medParts.length > 1) m.medParts.remove(part);
                } else {
                  m.medParts.add(part);
                }
              }),
            ),
            if (!care.isPro) ...[
              const SizedBox(height: 8),
              // Same 4pt inset as the other helper lines on this page.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'Free includes a morning time. Afternoon and evening come '
                  'with Pro, and you can add them after setup.',
                  style: text.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            SurfaceCard(
              child: SwitchListTile(
                value: model.medWithFood,
                onChanged: (v) =>
                    model.updateMedicine((m) => m.medWithFood = v),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                title: Text('Give with food', style: text.titleSmall),
                subtitle: Text(
                  'Shown as a reminder on every dose',
                  style: text.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            FieldLabel('Doses on hand · optional', key: _keys[_Field.supply]),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: SizedBox(
                width: 156,
                child: NumberStepper(
                  controller: _supply,
                  semanticLabel: 'Doses on hand',
                  min: 1,
                  max: 9999,
                  // Blank means supply isn't tracked.
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ),
            _errorFor(_Field.supply, issues),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                'We’ll let the household know before it runs out.',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
        footer: OnboardingCta(
          label: 'Continue',
          hint: _summary(issues),
          hintIsError: _tried,
          onPressed: _onContinue,
        ),
      ),
    );
  }
}

/// v14 FormPicker: four photo tiles a row; the picked one gets a clay
/// border, a check and a clay label.
class _FormGrid extends StatelessWidget {
  const _FormGrid({required this.selected, required this.onSelected});

  /// Null until the person picks one.
  final MedicineForm? selected;
  final ValueChanged<MedicineForm> onSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Two rows of four; three a row when text is large or space short.
        final perRow =
            constraints.maxWidth < 300 ||
                MediaQuery.textScalerOf(context).scale(1) > 1.3
            ? 3
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
                  selected: form == selected,
                  onTap: () => onSelected(form),
                ),
              ),
          ],
        );
      },
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
    final scheme = Theme.of(context).colorScheme;
    final paws = context.paws;
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      inMutuallyExclusiveGroup: true,
      checked: selected,
      label: form.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: paws.motion.micro,
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
          decoration: BoxDecoration(
            color: paws.surfaces.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? scheme.primary : Colors.transparent,
              width: 1.5,
            ),
            boxShadow: PawsElevation.card(Theme.of(context).brightness),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(child: MedicineFormIcon(form: form, size: 36)),
                  const SizedBox(height: 4),
                  Text(
                    form.label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelMedium?.copyWith(
                      fontSize: 12,
                      color: selected ? scheme.primary : scheme.onSurface,
                    ),
                  ),
                ],
              ),
              if (selected)
                Positioned(
                  top: -2,
                  right: 0,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: StrokeIcon(
                      StrokeIconKind.check,
                      size: 10,
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

/// "units | ml": a soft track with the picked unit raised (v14 DoseFields).
class _UnitSegments extends StatelessWidget {
  const _UnitSegments({
    required this.units,
    required this.selected,
    required this.onSelected,
  });

  final List<String> units;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final paws = context.paws;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: paws.surfaces.subtle,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          for (final unit in units)
            Expanded(
              child: Semantics(
                button: true,
                selected: unit == selected,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onSelected(unit),
                  child: AnimatedContainer(
                    duration: paws.motion.micro,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: unit == selected
                          ? paws.surfaces.card
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: unit == selected
                          ? PawsElevation.card(Theme.of(context).brightness)
                          : null,
                    ),
                    child: Text(
                      unit,
                      style: text.labelLarge?.copyWith(
                        color: unit == selected
                            ? scheme.onSurface
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
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
    final paws = context.paws;
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        // Sized to its label (`alignment` on the Container would fill the
        // whole Wrap width).
        child: Container(
          constraints: const BoxConstraints(minWidth: 56, minHeight: 36),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: selected ? scheme.onSurface : paws.surfaces.card,
            borderRadius: BorderRadius.circular(999),
            boxShadow: selected
                ? null
                : PawsElevation.card(Theme.of(context).brightness),
          ),
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: selected ? scheme.surface : scheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Every day / Every 2 days / Once a week, two a row.
class _FrequencyGrid extends StatelessWidget {
  const _FrequencyGrid({required this.everyDays, required this.onChanged});

  /// Null until the person picks one.
  final int? everyDays;
  final ValueChanged<int> onChanged;

  static const _options = [
    (1, 'Every day'),
    (2, 'Every 2 days'),
    (7, 'Once a week'),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 8.0;
        final width = (constraints.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final (days, label) in _options)
              SizedBox(
                width: width,
                child: ChoicePills<int>(
                  label: label,
                  options: [days],
                  value: everyDays,
                  labelOf: (_) => label,
                  onChanged: onChanged,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// v14 "At what time": Morning / Afternoon / Evening with their times and a
/// round check. Free shows "Pro" on the times it doesn't include.
class _TimesCard extends StatelessWidget {
  const _TimesCard({
    required this.parts,
    required this.canUse,
    required this.onToggle,
  });

  final Set<DayPart> parts;
  final bool Function(DayPart part) canUse;
  final ValueChanged<DayPart> onToggle;

  static String _label(DayPart part) => switch (part) {
    DayPart.morning => 'Morning',
    DayPart.afternoon => 'Afternoon',
    DayPart.evening => 'Evening',
  };

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final paws = context.paws;
    return SurfaceCard(
      child: Column(
        children: [
          for (final (i, part) in DayPart.values.indexed) ...[
            if (i > 0) Divider(height: 1, color: paws.hairline),
            Builder(
              builder: (context) {
                final allowed = canUse(part);
                final on = parts.contains(part) && allowed;
                return Semantics(
                  button: true,
                  checked: on,
                  label:
                      '${_label(part)}, ${ClockFormat.label(part.defaultMinute)}'
                      '${allowed ? '' : ', Pro'}',
                  excludeSemantics: true,
                  child: InkWell(
                    // A locked time says why instead of ignoring the tap;
                    // no paywall mid-setup (it comes after "Go to Today").
                    onTap: allowed
                        ? () => onToggle(part)
                        : () {
                            AppLog.event('onboarding.locked_time_tap', {
                              'part': part.name,
                            });
                            ScaffoldMessenger.of(context)
                              ..hideCurrentSnackBar()
                              ..showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '${_label(part)} comes with Pro. You can '
                                    'add it after setup.',
                                  ),
                                ),
                              );
                          },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          // Name left, time right; large text wraps the
                          // time under the name instead of overflowing.
                          Expanded(
                            child: Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 8,
                              children: [
                                Text(
                                  _label(part),
                                  style: text.bodyLarge?.copyWith(
                                    color: allowed
                                        ? scheme.onSurface
                                        : scheme.onSurfaceVariant,
                                  ),
                                ),
                                Text(
                                  ClockFormat.label(part.defaultMinute),
                                  style: text.bodyMedium?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          if (!allowed)
                            Text(
                              'Pro',
                              style: text.labelMedium?.copyWith(
                                color: scheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            )
                          else
                            CheckMark(selected: on),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// The fields Continue checks, in screen order.
enum _Field {
  name('name'),
  form('form'),
  amount('amount'),
  unit('unit'),
  site('where it’s given'),
  often('how often'),
  supply('doses on hand');

  const _Field(this.short);

  /// How the field reads in "Still needed: …".
  final String short;
}

/// A field's own problem, under it, once Continue has been tried.
class _FieldError extends StatelessWidget {
  const _FieldError(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
      child: Semantics(
        liveRegion: true,
        child: Text(
          message,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
      ),
    );
  }
}
