import 'package:pawsitive_sync/domain/models.dart';

/// Custom reminder times per part of the day, as minutes after local
/// midnight (wall clock, so 07:00 stays 07:00 across DST and travel).
///
/// Wire format (server + local store): `{"morning": "07:00"}`, 24-hour
/// `HH:mm`. Any time 00:00–23:59 is allowed for any part — the part stays
/// the dose's name and identity (log keys never change), the time only
/// moves the reminder and when the dose counts as due (see
/// [Medication.dueFromMinute]). Parts without a custom time use
/// [DayPartLabel.defaultMinute].
abstract final class DoseTimes {
  static final _pattern = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$');

  /// Minute of day for a valid `HH:mm`, else null.
  static int? parseClock(Object? value) {
    if (value is! String) return null;
    final match = _pattern.firstMatch(value);
    if (match == null) return null;
    return int.parse(match.group(1)!) * 60 + int.parse(match.group(2)!);
  }

  /// `HH:mm` for a minute of day.
  static String clock(int minute) {
    final m = minute.clamp(0, 24 * 60 - 1);
    return '${(m ~/ 60).toString().padLeft(2, '0')}:'
        '${(m % 60).toString().padLeft(2, '0')}';
  }

  /// Tolerant parse of the wire map: unknown parts, junk values and
  /// defaults are dropped, so old/garbled data falls back to the default
  /// times instead of failing.
  static Map<DayPart, int> parse(Object? json) {
    if (json is! Map) return const {};
    final result = <DayPart, int>{};
    for (final part in DayPart.values) {
      final minute = parseClock(json[part.name]);
      if (minute != null && minute != part.defaultMinute) result[part] = minute;
    }
    return result;
  }

  /// Wire map for [times], parts in day order.
  static Map<String, String> encode(Map<DayPart, int> times) => {
    for (final part in DayPart.values)
      if (times[part] != null) part.name: clock(times[part]!),
  };

  /// [times] limited to [parts] and without default values: the canonical
  /// form saved and compared.
  static Map<DayPart, int> normalize(
    Map<DayPart, int> times,
    Iterable<DayPart> parts,
  ) {
    final keep = parts.toSet();
    return {
      for (final part in DayPart.values)
        if (keep.contains(part) &&
            times[part] != null &&
            times[part] != part.defaultMinute)
          part: times[part]!.clamp(0, 24 * 60 - 1),
    };
  }

  /// Order-insensitive equality.
  static bool same(Map<DayPart, int> a, Map<DayPart, int> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }
}
