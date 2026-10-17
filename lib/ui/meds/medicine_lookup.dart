import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/paws_widgets.dart';
import 'package:pawsitive_sync/data/medicine_search.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:pawsitive_sync/ui/meds/medicine_forms.dart';

/// Suggestions for a medicine name field: the phone's matches on every
/// keystroke and, only when there are none, one server lookup once typing
/// pauses. [searching] is true only while that lookup is pending.
class MedicineLookup extends ChangeNotifier {
  MedicineLookup(this._ask);

  final MedicineAsk _ask;

  /// Typing pause before going online, and before logging a search.
  static const _pause = Duration(milliseconds: 450);

  List<CommonMedicine> results = const [];
  bool searching = false;

  String _query = '';
  Species? _species;
  Timer? _timer;

  /// Bumped per query so a late answer to an older query is ignored.
  int _generation = 0;
  bool _disposed = false;

  void update(Species species, String text) {
    final q = text.trim().toLowerCase();
    if (q == _query && species == _species) return;
    _query = q;
    _species = species;
    _timer?.cancel();
    final generation = ++_generation;
    results = MedicineSearch.local(species, q);
    searching = MedicineSearch.shouldAskOnline(species, q);
    if (searching) {
      _timer = Timer(_pause, () async {
        final found = await MedicineSearch.online(q, _ask);
        if (_disposed || generation != _generation) return;
        searching = false;
        results = found ?? const [];
        notifyListeners();
      });
    } else if (q.isNotEmpty) {
      _timer = Timer(_pause, () {
        if (!_disposed && generation == _generation) {
          MedicineSearch.logLocal(results.length, q.length);
        }
      });
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}

/// Matches under a medicine name field, a "Searching more medicines…" row
/// while the server is asked, and an optional "Use “typed name”" row so any
/// name still works.
class MedicineSuggestionList extends StatelessWidget {
  const MedicineSuggestionList({
    super.key,
    required this.results,
    required this.searching,
    required this.onPick,
    this.typed = '',
    this.onUseTyped,
  });

  final List<CommonMedicine> results;
  final bool searching;
  final ValueChanged<CommonMedicine> onPick;
  final String typed;
  final VoidCallback? onUseTyped;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final paws = context.paws;
    final name = typed.trim();
    final exact = results.any(
      (m) => m.name.toLowerCase() == name.toLowerCase(),
    );
    final rows = <Widget>[
      if (onUseTyped != null && name.isNotEmpty && !exact)
        _Row(
          leading: const SizedBox.square(dimension: 40),
          title: 'Use “$name”',
          onTap: () {
            AppLog.event('medicine.search.typed', {'length': name.length});
            onUseTyped!();
          },
        ),
      for (final medicine in results)
        _Row(
          leading: MedicineFormIcon(form: medicine.form, size: 40),
          title: medicine.name,
          subtitle: [
            medicine.form.label,
            if (medicine.use.isNotEmpty) medicine.use,
          ].join(' · '),
          onTap: () {
            // Form only: the log records the choice, not what the pet takes.
            AppLog.event('medicine.search.picked', {
              'form': medicine.form.name,
              'row': results.indexOf(medicine),
            });
            onPick(medicine);
          },
        ),
      if (searching)
        Semantics(
          liveRegion: true,
          label: 'Searching more medicines',
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Searching more medicines…',
                  style: text.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    return SurfaceCard(
      child: Column(
        children: [
          for (final (i, row) in rows.indexed) ...[
            if (i > 0) Divider(height: 1, color: paws.hairline),
            row,
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.leading,
    required this.title,
    required this.onTap,
    this.subtitle,
  });

  final Widget leading;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              leading,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: text.titleSmall),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: text.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
