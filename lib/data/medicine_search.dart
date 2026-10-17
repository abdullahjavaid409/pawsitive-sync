import 'dart:convert';

import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:pawsitive_sync/ui/meds/medicine_forms.dart';
import 'package:pawsitive_sync/ui/meds/medicine_library.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Signature of the server lookup (CareRepository.searchMedicinesOnline).
typedef MedicineAsk = Future<List<Map<String, dynamic>>> Function(String query);

/// Medicine name search, phone first.
///
/// The built-in list, the on-phone library and every name found online
/// before are searched instantly and offline. Only a query none of them
/// match goes to the server, once: what comes back (even nothing) is saved
/// on this phone and serves every pet afterwards.
///
/// Logs `medicine.search.local`, `.online`, `.online_failed` and `.learned`;
/// never the typed text.
class MedicineSearch {
  MedicineSearch._();

  static const _learnedKey = 'medicine_search.learned.v2';
  static const _askedKey = 'medicine_search.asked.v2';

  /// Shorter queries are too vague to be worth a server call.
  static const minOnlineLength = 3;
  static const maxResults = 8;
  static const _maxLearned = 400;
  static const _maxAsked = 300;

  static final List<CommonMedicine> _learned = [];

  /// Queries already sent to the server, answered or not.
  static final Set<String> _asked = {};
  static bool _loaded = false;

  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final raw in prefs.getStringList(_learnedKey) ?? const <String>[]) {
        if (_decode(raw) case final medicine?) _learned.add(medicine);
      }
      _asked.addAll(prefs.getStringList(_askedKey) ?? const []);
    } catch (error, stack) {
      AppLog.error('medicine.search.load_failed', error, stack);
    }
  }

  /// Matches on the phone, best first: name starts with the query, then
  /// contains it, then the use matches; this pet's species before others.
  static List<CommonMedicine> local(Species species, String query) {
    final q = _normalize(query);
    if (q.isEmpty) return CommonMedicine.suggestionsFor(species, '');
    final seen = <String>{};
    final ranked = <(int, CommonMedicine)>[];
    for (final m in [...CommonMedicine.all, ...medicineLibrary, ..._learned]) {
      final name = m.name.toLowerCase();
      if (!seen.add(name)) continue;
      final match = name.startsWith(q)
          ? 0
          : name.contains(q)
          ? 1
          : m.use.toLowerCase().contains(q)
          ? 2
          : null;
      if (match == null) continue;
      final otherSpecies = m.species.isNotEmpty && !m.species.contains(species);
      ranked.add((match * 2 + (otherSpecies ? 1 : 0), m));
    }
    ranked.sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final (_, m) in ranked.take(maxResults)) m];
  }

  /// True when only the server could add anything for this query.
  static bool shouldAskOnline(Species species, String query) {
    final q = _normalize(query);
    return q.length >= minOnlineLength &&
        !_asked.contains(q) &&
        local(species, q).isEmpty;
  }

  /// One server call; the answer is saved here. Null when unreachable, in
  /// which case nothing is saved and the next search tries again.
  static Future<List<CommonMedicine>?> online(
    String query,
    MedicineAsk ask,
  ) async {
    final q = _normalize(query);
    final watch = Stopwatch()..start();
    final List<Map<String, dynamic>> rows;
    try {
      rows = await ask(q);
    } catch (_) {
      // The failed call itself is logged by the API layer (api.failed).
      AppLog.event('medicine.search.online_failed', {'length': q.length});
      return null;
    }
    final found = [for (final row in rows) ?_fromRow(row)];
    AppLog.event('medicine.search.online', {
      'length': q.length,
      'results': found.length,
      'ms': watch.elapsedMilliseconds,
    });
    await _save(q, found);
    return found;
  }

  /// One line per settled search the phone answered by itself.
  static void logLocal(int results, int length) => AppLog.event(
    'medicine.search.local',
    {'results': results, 'length': length},
  );

  /// Clears what this phone learned (account deleted, tests). The saved copy
  /// goes with the preferences wipe.
  static void forget() {
    _learned.clear();
    _asked.clear();
    _loaded = false;
  }

  static String _normalize(String query) =>
      query.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  static Future<void> _save(String q, List<CommonMedicine> found) async {
    final known = {for (final m in _learned) m.name.toLowerCase()};
    final fresh = [
      for (final m in found)
        if (known.add(m.name.toLowerCase())) m,
    ];
    _learned.addAll(fresh);
    _asked.add(q);
    if (_learned.length > _maxLearned) {
      _learned.removeRange(0, _learned.length - _maxLearned);
    }
    if (_asked.length > _maxAsked) {
      final keep = _asked.skip(_asked.length - _maxAsked).toList();
      _asked
        ..clear()
        ..addAll(keep);
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_learnedKey, [
        for (final m in _learned) _encode(m),
      ]);
      await prefs.setStringList(_askedKey, _asked.toList());
      if (fresh.isNotEmpty) {
        AppLog.event('medicine.search.learned', {
          'added': fresh.length,
          'total': _learned.length,
        });
      }
    } catch (error, stack) {
      AppLog.error('medicine.search.save_failed', error, stack);
    }
  }

  static CommonMedicine? _fromRow(Map<String, dynamic> row) {
    final name = row['name'];
    if (name is! String || name.trim().isEmpty || name.length > 60) {
      return null;
    }
    final use = row['use'] is String ? (row['use'] as String).trim() : '';
    return CommonMedicine(
      _capitalize(name.trim()),
      MedicineForm.values.asNameMap()[row['form']] ?? MedicineForm.other,
      _capitalize(use),
      _species(row['species']),
    );
  }

  static Set<Species> _species(Object? raw) => {
    if (raw is List)
      for (final s in raw) ?Species.values.asNameMap()[s],
  };

  static String _capitalize(String text) =>
      text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);

  static String _encode(CommonMedicine m) => jsonEncode({
    'name': m.name,
    'form': m.form.name,
    'use': m.use,
    'species': [for (final s in m.species) s.name],
  });

  static CommonMedicine? _decode(String raw) {
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final name = map['name'];
      final form = MedicineForm.values.asNameMap()[map['form']];
      if (name is! String || form == null) return null;
      return CommonMedicine(
        name,
        form,
        map['use'] as String? ?? '',
        _species(map['species']),
      );
    } catch (_) {
      return null;
    }
  }
}
