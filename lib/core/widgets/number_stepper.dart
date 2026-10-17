import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/system_menu.dart';

/// A number field with − and + either side: tap to step, hold to repeat,
/// or tap the number to type it. For people who don't want to type, and
/// for anyone unsure what to write: the buttons show it's just a count.
///
/// The [controller] stays the source of truth, so screens keep their
/// existing validation and saved text unchanged.
class NumberStepper extends StatefulWidget {
  const NumberStepper({
    super.key,
    required this.controller,
    required this.semanticLabel,
    this.step = 1,
    this.min = 0,
    this.max = 999,
    this.decimal = false,
    this.hintText,
    this.autofocus = false,
    this.onChanged,
  });

  final TextEditingController controller;

  /// What the number is, read with the buttons ("Amount", "Doses on hand").
  final String semanticLabel;

  /// One tap's change; + and − also snap to a multiple of it.
  final double step;

  /// − stops here; a value at or below it disables −.
  final double min;
  final double max;

  /// Allows typing a decimal point (amounts); supply counts are whole.
  final bool decimal;
  final String? hintText;
  final bool autofocus;
  final ValueChanged<String>? onChanged;

  @override
  State<NumberStepper> createState() => _NumberStepperState();
}

class _NumberStepperState extends State<NumberStepper> {
  Timer? _repeat;

  /// Steps taken during the current hold, logged once when it ends.
  int _held = 0;

  /// "Amount per dose" → "amount_per_dose", for log fields.
  String get _field =>
      widget.semanticLabel.toLowerCase().replaceAll(RegExp(r'[^a-z]+'), '_');

  double? get _value => double.tryParse(widget.controller.text.trim());

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onText);
  }

  @override
  void didUpdateWidget(NumberStepper old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onText);
      widget.controller.addListener(_onText);
    }
  }

  @override
  void dispose() {
    _repeat?.cancel();
    widget.controller.removeListener(_onText);
    super.dispose();
  }

  /// Button states follow typed text and quick chips too.
  void _onText() => setState(() {});

  bool get _canLess {
    final v = _value;
    return v != null && v > widget.min + 1e-9;
  }

  bool get _canMore {
    final v = _value;
    return v == null || v < widget.max - 1e-9;
  }

  void _tap(int direction) {
    final changed = _bump(direction);
    AppLog.event(changed ? 'stepper.step' : 'stepper.limit', {
      'field': _field,
      'dir': direction > 0 ? 'up' : 'down',
      'value': widget.controller.text.trim(),
    });
  }

  /// Steps to the next multiple of [NumberStepper.step], so ¼ + ½ lands on
  /// ½ rather than ¾ — the values people actually give. False when already
  /// at a limit (or − on an empty field).
  bool _bump(int direction) {
    final step = widget.step;
    final current = _value;
    double next;
    if (current == null) {
      // Empty field: + starts at one (or one step if that's larger).
      if (direction < 0) return false;
      next = step >= 1 ? step : 1;
    } else {
      final units = current / step;
      final snapped = direction > 0
          ? (units + 1e-9).floor() + 1
          : (units - 1e-9).ceil() - 1;
      next = snapped * step;
    }
    next = next.clamp(widget.min, widget.max).toDouble();
    if (current != null && (next - current).abs() < 1e-9) {
      _repeat?.cancel();
      return false;
    }
    HapticFeedback.selectionClick();
    final text = _format(next);
    widget.controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    widget.onChanged?.call(text);
    return true;
  }

  static String _format(double v) =>
      v.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

  void _startRepeat(int direction) {
    _repeat?.cancel();
    _held = 0;
    _repeat = Timer.periodic(const Duration(milliseconds: 90), (_) {
      if (_bump(direction)) _held++;
    });
  }

  /// One line per hold, not one per repeat.
  void _stopRepeat(int direction) {
    final wasHolding = _repeat != null;
    _repeat?.cancel();
    _repeat = null;
    if (!wasHolding) return;
    AppLog.event('stepper.held', {
      'field': _field,
      'dir': direction > 0 ? 'up' : 'down',
      'steps': _held,
      'value': widget.controller.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final paws = context.paws;
    final value = widget.controller.text.trim();
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: paws.surfaces.input,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _StepButton(
            icon: Icons.remove_rounded,
            label: 'Less',
            hint: '${widget.semanticLabel}: ${value.isEmpty ? 'empty' : value}',
            enabled: _canLess,
            onTap: () => _tap(-1),
            onHoldStart: () => _startRepeat(-1),
            onHoldEnd: () => _stopRepeat(-1),
          ),
          Expanded(
            child: TextField(
              contextMenuBuilder: appContextMenuBuilder,
              controller: widget.controller,
              autofocus: widget.autofocus,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.numberWithOptions(
                decimal: widget.decimal,
              ),
              inputFormatters: [
                if (widget.decimal) ...[
                  // Comma too: a decimal keyboard in many locales has no dot.
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  TextInputFormatter.withFunction(
                    (old, value) =>
                        value.copyWith(text: value.text.replaceAll(',', '.')),
                  ),
                ] else
                  FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              onChanged: widget.onChanged,
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
              style: text.titleMedium?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              decoration: InputDecoration(
                hintText: widget.hintText,
                filled: false,
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          _StepButton(
            icon: Icons.add_rounded,
            label: 'More',
            hint: '${widget.semanticLabel}: ${value.isEmpty ? 'empty' : value}',
            enabled: _canMore,
            onTap: () => _tap(1),
            onHoldStart: () => _startRepeat(1),
            onHoldEnd: () => _stopRepeat(1),
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.label,
    required this.hint,
    required this.enabled,
    required this.onTap,
    required this.onHoldStart,
    required this.onHoldEnd,
  });

  final IconData icon;
  final String label;
  final String hint;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldEnd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final paws = context.paws;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      value: hint,
      excludeSemantics: true,
      onTap: enabled ? onTap : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        onLongPressStart: enabled ? (_) => onHoldStart() : null,
        onLongPressEnd: (_) => onHoldEnd(),
        onLongPressCancel: onHoldEnd,
        child: SizedBox(
          width: 52,
          height: 52,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: enabled ? paws.surfaces.card : Colors.transparent,
                shape: BoxShape.circle,
                boxShadow: enabled
                    ? PawsElevation.card(Theme.of(context).brightness)
                    : null,
              ),
              child: Icon(
                icon,
                size: 20,
                color: enabled
                    ? scheme.onSurface
                    : scheme.onSurfaceVariant.withValues(alpha: 0.4),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
