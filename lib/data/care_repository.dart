import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io' show FileSystemException;
import 'dart:math';

import 'package:characters/characters.dart';
import 'package:flutter/foundation.dart';
import 'package:pawsitive_sync/core/constants/pet_limits.dart';
import 'package:pawsitive_sync/core/legal/app_links.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/data/analytics_service.dart';
import 'package:pawsitive_sync/data/apple_widgets.dart';
import 'package:pawsitive_sync/data/care_events_store.dart';
import 'package:pawsitive_sync/data/dose_reminders.dart';
import 'package:pawsitive_sync/data/household_api.dart';
import 'package:pawsitive_sync/data/household_store.dart';
import 'package:pawsitive_sync/data/local_database.dart';
import 'package:pawsitive_sync/data/push_service.dart';
import 'package:pawsitive_sync/data/sync_engine.dart';
import 'package:pawsitive_sync/data/sync_outbox.dart';
import 'package:pawsitive_sync/data/sync_policy.dart';
import 'package:pawsitive_sync/data/onboarding_profile.dart';
import 'package:pawsitive_sync/data/onboarding_state.dart';
import 'package:pawsitive_sync/data/pet_photo_codec.dart';
import 'package:pawsitive_sync/data/pet_photo_store.dart';
import 'package:pawsitive_sync/data/reminder_choice.dart';
import 'package:pawsitive_sync/data/whats_new_state.dart';
import 'package:pawsitive_sync/data/upgrade_nudge_state.dart';
import 'package:pawsitive_sync/data/revenue_cat_service.dart';
import 'package:pawsitive_sync/data/secure_tokens.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_view_model.dart';
import 'package:purchases_flutter/purchases_flutter.dart' show Package;
import 'package:shared_preferences/shared_preferences.dart';

part 'care_repository_account.dart';
part 'care_repository_household.dart';
part 'care_repository_photos.dart';

/// Local calendar day as YYYY-MM-DD.
String dayKey(DateTime time) =>
    '${time.year.toString().padLeft(4, '0')}-'
    '${time.month.toString().padLeft(2, '0')}-'
    '${time.day.toString().padLeft(2, '0')}';

final _random = Random.secure();

String newId(String prefix) {
  final hex = [
    for (var i = 0; i < 6; i++)
      _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();
  return '$prefix-$hex';
}

/// One medicine's line in the vet report.
class ReportLine {
  const ReportLine({
    required this.medication,
    required this.given,
    required this.expected,
    this.skipped = 0,
    this.uncertain = 0,
    this.removed = false,
  });

  final Medication medication;
  final int given;

  /// Doses the schedule asked for in the range (at least the logged count).
  final int expected;

  /// Skipped on purpose.
  final int skipped;

  /// Logged as "not sure if given".
  final int uncertain;

  /// The medicine was stopped/removed; kept so the period stays complete.
  final bool removed;

  /// Scheduled doses with no log at all. Never negative.
  int get missed => max(expected - given - skipped - uncertain, 0);

  double get fraction => expected == 0 ? 0 : (given / expected).clamp(0, 1);
}

/// A scheduled dose with no log in the report range.
class MissedDose {
  const MissedDose({
    required this.medicationName,
    required this.day,
    required this.part,
    this.timeLabel = '',
  });

  final String medicationName;
  final DateTime day;
  final DayPart part;

  /// The scheduled time ("7:00 AM"), custom or the part's default.
  final String timeLabel;
}

/// One logged dose in the report range (any outcome), newest first.
class ReportEntry {
  const ReportEntry({
    required this.medicationId,
    required this.medicationName,
    required this.day,
    required this.timeLabel,
    required this.who,
    required this.outcome,
  });

  final String medicationId;
  final String medicationName;
  final String day;
  final String timeLabel;
  final String who;
  final LogOutcome outcome;
}

class PetReport {
  const PetReport({
    required this.from,
    required this.to,
    required this.lines,
    required this.skipped,
    required this.notes,
    this.uncertain = 0,
    this.missedDoses = const [],
    this.recent = const [],
  });

  final DateTime from;
  final DateTime to;
  final List<ReportLine> lines;

  /// Skipped on purpose (all medicines).
  final int skipped;

  /// "Not sure if given" (all medicines).
  final int uncertain;

  /// Note text and how many times it was logged.
  final Map<String, int> notes;

  /// Scheduled doses with no log, newest first (capped at [maxMissedListed]).
  final List<MissedDose> missedDoses;

  /// Logged doses in range, newest first (capped at [maxRecent]).
  final List<ReportEntry> recent;

  static const maxMissedListed = 100;
  static const maxRecent = 60;

  int get given => lines.fold(0, (sum, line) => sum + line.given);
  int get missed => lines.fold(0, (sum, line) => sum + line.missed);

  bool get isEmpty =>
      lines.every((line) => line.given == 0) && skipped == 0 && uncertain == 0;
}

/// A named browser link for a sitter. The token is a secret: it lives only
/// in secure storage and in the URL the person chooses to share.
class SitterLink {
  const SitterLink({
    required this.token,
    this.label = '',
    this.expiresAt,
    this.id = '',
  });

  final String token;

  /// Server link id (for revoke). Empty for links made before v5 servers.
  final String id;

  /// "Who is this link for?" — empty for links made by older builds.
  final String label;
  final DateTime? expiresAt;

  String get url => AppLinks.sitterWebLink(token);

  String toCache() => jsonEncode({
    'token': token,
    'label': label,
    if (id.isNotEmpty) 'id': id,
    if (expiresAt != null) 'expiresAt': expiresAt!.toIso8601String(),
  });

  /// Accepts the JSON written by [toCache] or a bare legacy token.
  factory SitterLink.fromCache(String raw) {
    if (raw.startsWith('{')) {
      try {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        final expires = json['expiresAt'];
        return SitterLink(
          token: '${json['token'] ?? ''}',
          label: '${json['label'] ?? ''}',
          expiresAt: expires is String ? DateTime.tryParse(expires) : null,
          id: '${json['id'] ?? ''}',
        );
      } on Object {
        // Fall through: treat as an opaque token.
      }
    }
    return SitterLink(token: raw);
  }
}

/// The household: pets, people, medicine schedules, and every logged dose.
///
/// Works on the phone first and saves locally. When the API is set, the
/// household is created on the server and shared with everyone who joins.
class CareRepository extends ChangeNotifier {
  CareRepository({
    this._api,
    this._store,
    CareEventsStore? eventsStore,
    SyncEngine? syncEngine,
    PetPhotoStore? photoStore,
    PetPhotoTransfer? photoTransfer,
    DateTime Function()? clock,
    bool sample = false,
  }) : _eventsStore = eventsStore ?? CareEventsStore(),
       _syncEngine = syncEngine ?? SyncEngine(),
       _photos = photoStore,
       _photoTransfer = photoTransfer ?? PetPhotoTransfer(),
       _clock = clock ?? DateTime.now {
    if (sample) loadSampleData();
  }

  /// Demo household for widget tests only — never reachable from the app.
  @visibleForTesting
  factory CareRepository.sample({
    HouseholdApi? api,
    DateTime Function()? clock,
  }) => CareRepository(
    api: api,
    clock: clock ?? () => DateTime(2026, 10, 2, 13, 6),
    sample: true,
  );

  final HouseholdApi? _api;
  final HouseholdStore? _store;
  final CareEventsStore _eventsStore;
  final SyncEngine _syncEngine;
  final DateTime Function() _clock;

  /// Null where photos are off (most widget tests); set by `bootstrap`.
  final PetPhotoStore? _photos;
  final PetPhotoTransfer _photoTransfer;
  Future<void>? _photoSyncRunning;
  Future<void>? _photoCacheRunning;
  final Set<String> _photoCacheHitLogged = {};

  /// Upload progress (0..1) per pet while a photo PUT is in flight.
  final Map<String, double> _photoProgress = {};

  /// Backoff after a network failure: 5 s, 30 s, 2 min, then wait for the
  /// next sync/resume. Never a tight retry loop on a bad connection.
  @visibleForTesting
  static List<Duration> photoRetryDelays = const [
    Duration(seconds: 5),
    Duration(seconds: 30),
    Duration(minutes: 2),
  ];
  int _photoRetryAttempt = 0;
  Timer? _photoRetryTimer;

  /// Account deletion in flight, shared by repeated taps.
  Future<String?>? _deleting;
  bool _accountDeletePending = false;

  @override
  void dispose() {
    _photoRetryTimer?.cancel();
    _proExpiryTimer?.cancel();
    super.dispose();
  }

  bool syncing = false;
  String? syncError;

  /// The last write problem, worded for the person.
  String? lastError;

  String _memberId = 'you';
  String _inviteCode = '';
  DateTime? _inviteExpiresAt;
  String _householdId = '';
  final List<Member> _members = [];
  final List<Pet> _pets = [];
  final List<Medication> _medications = [];
  final List<DoseRecord> _logs = [];
  final List<CareEvent> _careEvents = [];

  /// Stopped medicines (each with [Medication.archivedAt]): never on Today,
  /// reminders, the widget or any schedule — only used to label their dose
  /// history (activity, vet report). Filled from the server's
  /// `archivedMedications` and from medicines stopped on this phone.
  final List<Medication> _archivedMedications = [];

  /// Log ids to delete from disk on the next save (see [StoredHousehold]).
  final Set<String> _deletedLogIds = {};

  /// Set by a join: the next save drops every saved log first.
  bool _replaceSavedLogs = false;

  /// The server's snapshot cap (`loadHousehold` LIMIT): also how many logs
  /// a new household uploads.
  static const _serverLogCap = 3000;

  void _archive(Iterable<Medication> removed) {
    final today = dayKey(now);
    final at = now.toUtc().toIso8601String();
    for (final m in removed) {
      _archivedMedications
        ..removeWhere((a) => a.id == m.id)
        ..add(
          m.copyWith(
            endDay: m.endDay.isEmpty || m.endDay.compareTo(today) > 0
                ? today
                : null,
            archivedAt: m.archivedAt ?? at,
          ),
        );
    }
  }

  /// Stopped medicines after a server snapshot: the server's list (real
  /// names and stop times, including medicines stopped before this phone
  /// joined) plus ones this phone stopped whose logs are older than the
  /// server's window. A medicine that is active again is never archived.
  void _mergeArchived(List<Medication> remote, List<Medication> active) {
    final activeIds = {for (final m in active) m.id};
    final byId = {for (final m in _archivedMedications) m.id: m};
    for (final m in remote) {
      byId[m.id] = m;
    }
    byId.removeWhere((id, _) => activeIds.contains(id));
    _archivedMedications
      ..clear()
      ..addAll(byId.values);
  }

  /// Active or stopped medicine by id, for history only.
  Medication? _historyMedication(String id) {
    final active = medicationById(id);
    if (active != null) return active;
    for (final m in _archivedMedications) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// Household Pro from the server, set only by the RevenueCat webhook —
  /// shared with partners. Ignored until this phone is in a shared household.
  bool _isPro = false;

  /// When household Pro ends, from the server (null = no known end: a
  /// lifetime purchase, or an older server). Checked on every read so a
  /// phone that stays offline still drops Pro at the exact end.
  DateTime? _proUntil;

  /// Re-reads [isPro] (and tells the UI) at the next known Pro end.
  Timer? _proExpiryTimer;

  /// This phone's own App Store / Play subscription, straight from RevenueCat.
  /// Kept apart so a server refresh can never lock out a paying user while
  /// the purchase webhook is still in flight.
  bool _storePro = false;
  BillingPlan _plan = BillingPlan.yearly;
  Future<String?>? _connecting;
  DateTime? _lastSyncedAt;

  /// Last successful server snapshot, kept across launches so a cold open
  /// within [SyncPolicy.maxAge] uses local data instead of the network.
  static const _lastSyncKey = 'household_last_sync_v1';

  /// Consecutive offline/timeout sync failures (for [SyncPolicy.backoff]).
  int _offlineFailures = 0;
  DateTime? _lastFailureAt;

  void _markSynced() {
    _lastSyncedAt = now;
    _offlineFailures = 0;
    _lastFailureAt = null;
    final at = now.millisecondsSinceEpoch;
    unawaited(
      SharedPreferences.getInstance()
          .then((prefs) => prefs.setInt(_lastSyncKey, at))
          .catchError((Object error, StackTrace stack) {
            AppLog.error('store.last_sync_failed', error, stack);
            return false;
          }),
    );
  }
  static const _syncMinInterval = Duration(seconds: 45);

  DateTime get now => _clock();

  bool get hasApi => _api != null;

  /// This phone is linked to a shared household on the server.
  bool get isConnected => _api?.token != null;

  bool get canSync => isConnected;

  bool get hasHousehold => _members.isNotEmpty;

  String get inviteCode => _inviteCode;

  /// When [inviteCode] stops working (7 days after it was made). Null when
  /// unknown (older server, or not the owner).
  DateTime? get inviteExpiresAt => _inviteExpiresAt;

  /// Whole days left on the invite code (0 = expires today), or null.
  int? get inviteDaysLeft {
    final expires = _inviteExpiresAt;
    if (expires == null) return null;
    final left = expires.difference(now);
    if (left.isNegative) return 0;
    return (left.inMinutes / (24 * 60)).ceil().clamp(0, 7);
  }

  /// True once the code is past its 7 days: the owner should make a new one.
  bool get inviteExpired {
    final expires = _inviteExpiresAt;
    return expires != null && !expires.isAfter(now);
  }

  /// This member's role. A phone that isn't sharing owns its own data.
  /// Read from the household's member list, which every sync refreshes.
  MemberRole get myRole => isConnected ? you.role : MemberRole.owner;

  /// Owner: billing, invites, sitter links, archiving, member management.
  bool get isOwner => myRole == MemberRole.owner;

  /// Owner or caregiver: add/edit pets and medicines, refill, care events,
  /// photos. Sitters only view and log doses.
  bool get canEditCare => myRole != MemberRole.sitter;

  /// Owner only: stop (archive) a medicine.
  bool get canArchive => isOwner;

  /// Owner only: invite code, sitter links, roles and removals.
  bool get canManageHousehold => isOwner;

  static const ownerOnlyMessage = 'Only the household owner can do that.';
  static const sitterOnlyMessage =
      'Sitters can view and log doses only. Ask the owner for more access.';

  /// Refuses an action this member's role can't do, before touching the
  /// phone's data or the network. True = blocked ([lastError] set).
  bool _roleBlocks(String event, {required bool ownerOnly}) {
    final allowed = ownerOnly ? isOwner : canEditCare;
    if (allowed) return false;
    lastError = ownerOnly ? ownerOnlyMessage : sitterOnlyMessage;
    AppLog.event('$event.blocked', {'reason': 'role', 'role': myRole.name});
    notifyListeners();
    return true;
  }

  /// The server said this member's role can't do that — it changed on
  /// another phone. Explain, and pull the new role in the background.
  void _onRoleForbidden(String event, HouseholdException error) {
    lastError = error.message;
    AppLog.event('household.role_forbidden', {'event': event});
    unawaited(sync(force: true, source: 'role_changed'));
  }

  /// Store account id. Empty until shared, so RevenueCat keeps its own
  /// per-install id; never the bare member id (every owner is 'you').
  String get billingUserId =>
      isConnected && _householdId.isNotEmpty ? '$_householdId:$_memberId' : '';

  /// Pro only ever comes from RevenueCat: this phone's own subscription, or
  /// the household's (server copy of a partner's RevenueCat entitlement).
  bool get isPro => _storeProValid || _householdProValid;

  /// RevenueCat says Pro *and* its expiry (if any) hasn't passed by this
  /// phone's clock — the SDK's offline cache alone is never trusted past it.
  bool get _storeProValid {
    if (!_storePro) return false;
    final until = RevenueCatService.storeProExpiresAt;
    return until == null || now.isBefore(until);
  }

  /// Server household Pro, only while linked, before its end, and while the
  /// clock hasn't been wound back behind the last sync (offline only; the
  /// next sync puts the server's answer back either way).
  bool get _householdProValid {
    if (!isConnected || !_isPro) return false;
    final until = _proUntil;
    if (until != null && !now.isBefore(until)) return false;
    final synced = _lastSyncedAt;
    if (synced != null && now.isBefore(synced.subtract(_clockBackTolerance))) {
      return false;
    }
    return true;
  }

  /// Small clock corrections (NTP, zone) never cost a payer Pro.
  static const _clockBackTolerance = Duration(hours: 1);

  /// Arms a timer for the nearest Pro end so the app drops Pro at that
  /// moment even if nothing else changes. Logs once when it does.
  void _armProExpiry() {
    _proExpiryTimer?.cancel();
    final ends = [
      if (_storePro) ?RevenueCatService.storeProExpiresAt,
      if (isConnected && _isPro) ?_proUntil,
    ].where((t) => t.isAfter(now)).toList()
      ..sort();
    if (ends.isEmpty) return;
    // Re-armed in steps of at most a day (very long timers aren't reliable).
    var wait = ends.first.difference(now) + const Duration(seconds: 1);
    if (wait > const Duration(days: 1)) wait = const Duration(days: 1);
    final wasPro = isPro;
    _proExpiryTimer = Timer(wait, () {
      if (wasPro && !isPro) {
        AppLog.event('billing.pro.expired', {
          'source': _storePro ? 'store' : 'household',
        });
      }
      _armProExpiry();
      notifyListeners();
    });
  }

  @visibleForTesting
  set debugStorePro(bool value) => _storePro = value;

  BillingPlan get plan => _plan;

  /// Pro-only: invite caregivers to a shared household.
  bool get canInviteHousehold => isPro;

  /// Pro-only: export/share vet reports.
  bool get canShareVetReport => isPro;

  /// Pro-only: running-low supply alerts on Today and medication detail.
  bool get canShowLowSupplyAlerts => isPro;

  /// Free tier allows one pet; Pro allows up to [PetLimits.maxPetsPerHousehold].
  bool get canAddPet {
    if (_pets.length >= PetLimits.maxPetsPerHousehold) return false;
    return isPro || _pets.length < PetLimits.maxPetsFree;
  }

  String get memberId => _memberId;

  // Read-only views, not copies: these are read many times per build and
  // `logs` can hold thousands of entries. Don't keep one across an await.
  List<Member> get members => UnmodifiableListView(_members);
  List<Pet> get pets => UnmodifiableListView(_pets);
  List<Medication> get medications => UnmodifiableListView(_medications);
  List<DoseRecord> get logs => UnmodifiableListView(_logs);

  Member get you =>
      _members.firstWhere((member) => member.isYou, orElse: () => _youMember);

  /// Falls back to a neutral member so stale IDs never crash a screen. A log
  /// whose member is no longer in the household (they deleted their account)
  /// reads as "Former member" — never blank, "You" or "Someone".
  Member memberById(String id) => _members.firstWhere(
    (member) => member.id == id,
    orElse: () => Member(
      id: id,
      name: formerMemberName,
      initials: '?',
      role: MemberRole.caregiver,
      avatarTone: AvatarTone.neutral,
    ),
  );

  /// Falls back to a neutral pet so stale IDs never crash a screen.
  Pet petById(String id) =>
      tryPetById(id) ??
      Pet(
        id: id,
        name: 'Your pet',
        species: Species.other,
        ageYears: 0,
        breed: '',
        sex: '',
        conditions: const [],
        weightKg: 0,
        onTimePercent: 0,
        dailyMeds: 0,
      );

  Pet? tryPetById(String id) {
    for (final pet in _pets) {
      if (pet.id == id) return pet;
    }
    return null;
  }

  static const formerMemberName = 'Former member';

  Pet? get primaryPet => _pets.isEmpty ? null : _pets.first;

  Medication? medicationById(String id) {
    for (final medication in _medications) {
      if (medication.id == id) return medication;
    }
    return null;
  }

  List<Medication> medicationsFor(String petId) => [
    for (final item in _medications)
      if (item.petId == petId) item,
  ];

  static String doseIdFor(String medicationId, DayPart part) =>
      '$medicationId.${part.name}';

  /// The log for [doseId] (`<medicationId>.<part>`) on [day], if any —
  /// what the double-dose check looks at.
  DoseRecord? loggedDose(String doseId, String day) {
    final split = doseId.lastIndexOf('.');
    if (split < 0) return null;
    final part = DayPart.values
        .where((p) => p.name == doseId.substring(split + 1))
        .firstOrNull;
    if (part == null) return null;
    return _logFor(doseId.substring(0, split), part, day);
  }

  /// The local day changed while the app was open (midnight): Today and
  /// anything keyed on the date re-read [now].
  void dayChanged() => notifyListeners();

  DoseRecord? _logFor(String medicationId, DayPart part, String day) {
    for (final log in _logs) {
      if (log.medicationId == medicationId &&
          log.part == part &&
          log.day == day) {
        return log;
      }
    }
    return null;
  }

  String _who(String memberId) {
    final member = memberById(memberId);
    return member.isYou ? 'You' : member.name;
  }

  /// "are" for the current user, "is" for anyone else — keeps "not sure" grammatical.
  String _isOrAre(String memberId) => memberById(memberId).isYou ? 'are' : 'is';

  /// Today's doses, built from the schedules and what has been logged today.
  List<Dose> get doses {
    final time = now;
    final today = dayKey(time);
    // One pass over history instead of one scan per medicine × part.
    // [_logs] is newest first, so the first match wins (same as [_logFor]).
    final todays = <String, DoseRecord>{};
    for (final log in _logs) {
      if (log.day == today) {
        todays.putIfAbsent('${log.medicationId}.${log.part.name}', () => log);
      }
    }
    final result = <Dose>[];
    for (final part in DayPart.values) {
      for (final medication in _medications) {
        if (!medication.parts.contains(part)) continue;
        if (!medication.isActiveOn(today)) continue;
        final log = todays[doseIdFor(medication.id, part)];
        if (log?.outcome == LogOutcome.skipped) continue;
        final pet = petById(medication.petId);
        final uncertain = log?.outcome == LogOutcome.uncertain;
        final status = log?.outcome == LogOutcome.given
            ? DoseStatus.given
            : time.hour * 60 + time.minute >= medication.dueFromMinute(part)
            ? DoseStatus.due
            : DoseStatus.upcoming;
        result.add(
          Dose(
            id: doseIdFor(medication.id, part),
            petId: medication.petId,
            medicationId: medication.id,
            name: medication.name,
            amount: log?.amount.isNotEmpty == true
                ? log!.amount
                : medication.amount,
            part: part,
            status: status,
            subtitle: switch (status) {
              DoseStatus.given =>
                '${pet.name} · ${_who(log!.memberId)}, ${log.timeLabel}',
              DoseStatus.due when uncertain =>
                '${pet.name} · ${_who(log!.memberId)} ${_isOrAre(log.memberId)} not sure — check first',
              DoseStatus.due =>
                '${pet.name} · due ${medication.timeLabelFor(part)}',
              DoseStatus.upcoming =>
                '${pet.name} · ${medication.timeLabelFor(part)}',
            },
            givenById: log?.memberId,
            givenAt: log?.timeLabel ?? '',
            minute: medication.minuteFor(part),
          ),
        );
      }
    }
    return result;
  }

  Dose? doseById(String id) {
    for (final dose in doses) {
      if (dose.id == id) return dose;
    }
    return null;
  }

  int get givenCount =>
      doses.where((dose) => dose.status == DoseStatus.given).length;

  /// Total given doses in history — used for post-value upgrade nudge.
  int get givenDoseLogCount =>
      _logs.where((log) => log.outcome == LogOutcome.given).length;

  Dose? get nextDue {
    for (final dose in doses) {
      if (dose.status == DoseStatus.due) return dose;
    }
    return null;
  }

  Medication? get lowSupply {
    for (final medication in _medications) {
      if (medication.isLow) return medication;
    }
    return null;
  }

  String _dayLabel(String day) {
    final today = now;
    if (day == dayKey(today)) return 'Today';
    if (day == dayKey(today.subtract(const Duration(days: 1)))) {
      return 'Yesterday';
    }
    final parsed = DateTime.tryParse(day);
    if (parsed == null) return day;
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
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
    return '${weekdays[parsed.weekday - 1]}, ${months[parsed.month - 1]} ${parsed.day}';
  }

  /// Newest first: who gave or skipped what.
  List<ActivityItem> get activity {
    return [
      for (final log in _logs.take(40))
        () {
          final medication = _historyMedication(log.medicationId);
          final pet = medication == null ? null : tryPetById(medication.petId);
          final petName = pet?.name ?? 'your pet';
          final name = medication?.historyName ?? 'A medicine';
          final amount = log.amount.isNotEmpty
              ? log.amount
              : medication?.amount ?? '';
          final day = _dayLabel(log.day);
          return ActivityItem(
            memberId: log.memberId,
            actor: _who(log.memberId),
            action: switch (log.outcome) {
              LogOutcome.given => 'gave $petName',
              LogOutcome.skipped => 'skipped for $petName',
              LogOutcome.uncertain =>
                '${_isOrAre(log.memberId)} not sure about $petName',
            },
            emphasis: amount.isEmpty ? name : '$name · $amount',
            timeLabel: day == 'Today'
                ? log.timeLabel
                : '$day · ${log.timeLabel}',
            note: log.note,
          );
        }(),
    ];
  }

  List<DoseLog> historyFor(String medicationId) {
    return [
      for (final log in _logs)
        if (log.medicationId == medicationId && log.outcome == LogOutcome.given)
          DoseLog(
            when: '${_dayLabel(log.day)} · ${log.timeLabel}',
            who: _who(log.memberId),
          ),
    ];
  }

  /// Given / skipped / not sure / missed against the schedule for the last
  /// [days] days, from real logs only. Includes medicines removed since, so
  /// the vet sees the whole period.
  PetReport reportFor(String petId, int days) {
    final time = now;
    final today = DateTime(time.year, time.month, time.day);
    final from = today.subtract(Duration(days: days - 1));
    final fromKey = dayKey(from);
    final todayKey = dayKey(today);

    // One pass over history: in-range logs grouped by medicine.
    final inRange = <String, List<DoseRecord>>{};
    for (final log in _logs) {
      if (log.day.compareTo(fromKey) < 0 || log.day.compareTo(todayKey) > 0) {
        continue;
      }
      (inRange[log.medicationId] ??= []).add(log);
    }

    final meds = <(Medication, bool)>[
      for (final m in _medications)
        if (m.petId == petId) (m, false),
    ];
    final known = {for (final m in _medications) m.id};
    // Stopped medicines with logs in range keep their real name and pet:
    // the server sends them (`archivedMedications`) even to a phone that
    // joined after they were stopped.
    for (final m in _archivedMedications) {
      if (m.petId == petId && !known.contains(m.id) && inRange[m.id] != null) {
        meds.add((m, true));
        known.add(m.id);
      }
    }

    final lines = <ReportLine>[];
    final missedDoses = <MissedDose>[];
    final recent = <ReportEntry>[];
    var skipped = 0;
    var uncertain = 0;
    final notes = <String, int>{};
    for (final (medication, removed) in meds) {
      final logs = inRange[medication.id] ?? const <DoseRecord>[];
      final logged = {for (final log in logs) '${log.day}|${log.part.name}'};
      final start = DateTime.tryParse(medication.startDay) ?? today;
      var expected = 0;
      for (
        var day = start.isAfter(from) ? start : from;
        !day.isAfter(today);
        day = DateTime(day.year, day.month, day.day + 1)
      ) {
        final key = dayKey(day);
        if (!medication.isActiveOn(key)) continue;
        for (final part in medication.parts) {
          if (day == today &&
              time.hour * 60 + time.minute < medication.dueFromMinute(part)) {
            continue;
          }
          expected++;
          if (!logged.contains('$key|${part.name}')) {
            missedDoses.add(
              MissedDose(
                medicationName: medication.historyName,
                day: day,
                part: part,
                timeLabel: medication.timeLabelFor(part),
              ),
            );
          }
        }
      }
      var given = 0;
      var lineSkipped = 0;
      var lineUncertain = 0;
      for (final log in logs) {
        switch (log.outcome) {
          case LogOutcome.given:
            given++;
          case LogOutcome.skipped:
            lineSkipped++;
          case LogOutcome.uncertain:
            lineUncertain++;
        }
        final note = log.note;
        if (note != null && note.isNotEmpty) {
          notes[note] = (notes[note] ?? 0) + 1;
        }
        recent.add(
          ReportEntry(
            medicationId: medication.id,
            medicationName: medication.historyName,
            day: log.day,
            timeLabel: log.timeLabel,
            who: _who(log.memberId),
            outcome: log.outcome,
          ),
        );
      }
      skipped += lineSkipped;
      uncertain += lineUncertain;
      lines.add(
        ReportLine(
          medication: medication,
          given: given,
          skipped: lineSkipped,
          uncertain: lineUncertain,
          expected: max(expected, given + lineSkipped + lineUncertain),
          removed: removed,
        ),
      );
    }
    missedDoses.sort((a, b) {
      final byDay = b.day.compareTo(a.day);
      return byDay != 0 ? byDay : b.part.index.compareTo(a.part.index);
    });
    // _logs is newest first per medicine; merge by day, stable otherwise.
    recent.sort((a, b) => b.day.compareTo(a.day));
    return PetReport(
      from: from,
      to: today,
      lines: lines,
      skipped: skipped,
      uncertain: uncertain,
      notes: notes,
      missedDoses: missedDoses.take(PetReport.maxMissedListed).toList(),
      recent: recent.take(PetReport.maxRecent).toList(),
    );
  }

  /// Human day label ("Today", "Yesterday", "Mon, Oct 2") for report rows.
  String dayLabel(String day) => _dayLabel(day);

  // ---------------------------------------------------------------------------
  // Loading and syncing

  /// Reads what this phone saved last time. Call once at launch.
  List<CareEvent> get careEvents => UnmodifiableListView(_careEvents);

  /// Upcoming vet visits, vaccines, and refills within the next 60 days.
  List<CareEvent> upcomingCareEvents({int withinDays = 60}) {
    final today = dayKey(now);
    final limit = now.add(Duration(days: withinDays));
    final limitKey = dayKey(limit);
    final items = [
      for (final event in _careEvents)
        if (event.dueDay.compareTo(today) >= 0 &&
            event.dueDay.compareTo(limitKey) <= 0)
          event,
    ]..sort((a, b) => a.dueDay.compareTo(b.dueDay));
    return items;
  }

  Future<void> restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _storeProLastRun = prefs.getBool(_lastStoreProKey) ?? false;
      _accountDeletePending = prefs.getBool(_deletePendingKey) ?? false;
      final synced = prefs.getInt(_lastSyncKey);
      _lastSyncedAt = synced == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(synced);
    } on Object catch (error, stack) {
      AppLog.error('store.billing_state_failed', error, stack);
    }
    try {
      _careEvents
        ..clear()
        ..addAll(await _eventsStore.read());
    } on Object catch (error, stack) {
      AppLog.error('store.read_failed', error, stack, {'table': 'care_events'});
    }
    try {
      await _photos?.init();
    } on Object catch (error, stack) {
      AppLog.error('pet.photo_store_failed', error, stack);
    }
    final StoredHousehold? saved;
    // Before the first frame only the last [firstFrameDays] days: enough for
    // Today, activity and the 7-day summary. [loadRecentHistory] adds the
    // rest of the window right after.
    final firstDay = dayKey(now.subtract(const Duration(days: firstFrameDays)));
    try {
      saved = await _store?.read(sinceDay: firstDay);
    } on Object catch (error, stack) {
      // The data may still be on disk; saving over it from an empty memory
      // would lose it. This run works from memory only (logging still works).
      _storeUnreadable = true;
      AppLog.error('store.read_failed', error, stack, {'table': 'household'});
      return;
    }
    if (saved == null) return;
    _historyFrom = firstDay;
    _apply(
      householdId: saved.householdId,
      token: saved.token,
      memberId: saved.memberId,
      inviteCode: saved.inviteCode,
      inviteExpiresAt: saved.inviteExpiresAt,
      isPro: saved.isPro,
      proUntil: saved.proUntil,
      plan: saved.plan,
      members: saved.members,
      pets: saved.pets,
      medications: saved.medications,
      logs: saved.logs,
    );
    _archivedMedications
      ..clear()
      ..addAll(saved.archivedMedications);
    AppLog.event('data.restored', {
      'pets': _pets.length,
      'medications': _medications.length,
      'logs': _logs.length,
      'careEvents': _careEvents.length,
      'connected': isConnected,
    });
    notifyListeners();
  }

  /// Days of logs [restore] loads before the first frame.
  static const firstFrameDays = 14;

  /// First day of logs in memory while older days of the recent window are
  /// still on disk only; null once [loadRecentHistory] ran (or nothing to load).
  String? _historyFrom;
  Future<void>? _historyLoading;

  /// Loads the rest of the recent window ([HouseholdStore.recentDays]) after
  /// the first frame. Runs once; sync waits for it so a server snapshot never
  /// merges against a half-loaded history.
  Future<void> loadRecentHistory() =>
      _historyLoading ??= _loadRecentHistory();

  Future<void> _loadRecentHistory() async {
    final before = _historyFrom;
    final store = _store;
    if (before == null || store == null) return;
    final watch = Stopwatch()..start();
    try {
      final older = await store.readLogs(
        fromDay: dayKey(
          now.subtract(const Duration(days: HouseholdStore.recentDays)),
        ),
        beforeDay: before,
        remember: true,
      );
      // Older than everything loaded, so they go at the end. Skip any that
      // arrived meanwhile (a sync or a write) to keep one copy per id.
      final known = {for (final log in _logs) log.id};
      _logs.addAll(older.where((log) => !known.contains(log.id)));
      _historyFrom = null;
      AppLog.event('data.history_loaded', {
        'logs': older.length,
        'ms': watch.elapsedMilliseconds,
      });
      notifyListeners();
    } on Object catch (error, stack) {
      // Reports past [firstFrameDays] miss these until the next launch;
      // nothing on disk is touched.
      AppLog.error('store.read_failed', error, stack, {'table': 'dose_logs'});
    }
  }

  void _apply({
    String householdId = '',
    required String? token,
    required String memberId,
    required String inviteCode,
    DateTime? inviteExpiresAt,
    required bool isPro,
    DateTime? proUntil,
    required BillingPlan plan,
    required List<Member> members,
    required List<Pet> pets,
    required List<Medication> medications,
    required List<DoseRecord> logs,
  }) {
    _api?.token = token;
    _memberId = memberId.isEmpty ? 'you' : memberId;
    _inviteCode = inviteCode;
    _inviteExpiresAt = inviteCode.isEmpty ? null : inviteExpiresAt;
    _householdId = householdId;
    // Household Pro only means something while this phone is linked; a stale
    // saved copy on a solo phone must never read as Pro.
    _isPro = token != null && isPro;
    _proUntil = _isPro ? proUntil : null;
    _plan = plan;
    _armProExpiry();
    _members
      ..clear()
      ..addAll(members);
    _pets
      ..clear()
      ..addAll(pets);
    _medications
      ..clear()
      ..addAll(medications);
    _logs
      ..clear()
      ..addAll(logs);
    _resolvePhotoPaths();
  }

  /// [joined]: this phone switched to someone else's household, so nothing
  /// of its own history may stay (in memory or on disk). Creating a
  /// household keeps it: the server now holds the same logs.
  void _applySession(HouseholdSession session, {required bool joined}) {
    final house = session.snapshot;
    // A create/join answer is a fresh server snapshot, same as a sync.
    _markSynced();
    if (joined) {
      _replaceSavedLogs = true;
      _deletedLogIds.clear();
      _archivedMedications.clear();
    }
    _mergeArchived(house.archivedMedications, house.medications);
    _apply(
      householdId: house.householdId,
      token: session.token,
      memberId: house.memberId,
      inviteCode: house.inviteCode,
      inviteExpiresAt: house.inviteExpiresAt,
      isPro: house.isPro,
      proUntil: house.proUntil,
      plan: house.plan,
      members: house.members,
      pets: _mergePhotoState(house.pets),
      medications: house.medications,
      logs: joined ? house.logs : _mergeLogs(house.logs),
    );
    _mergeCareEvents(house.careEvents);
  }

  void _mergeSnapshot(HouseholdSnapshot house) {
    final pending = _syncEngine.outbox.pendingPayloadIds;
    // Added offline and still queued: the server hasn't seen it yet.
    final medications = _keepPending(
      house.medications,
      _medications,
      pending['addMedication'],
    );
    final pets = _keepPending(house.pets, _pets, pending['addPet']);
    final remoteMedIds = {for (final m in medications) m.id};
    _archive(_medications.where((m) => !remoteMedIds.contains(m.id)));
    _mergeArchived(house.archivedMedications, medications);
    final knownLogIds = {for (final log in _logs) log.id};
    _notifyPartnerLogs(house, knownLogIds);
    _apply(
      householdId: house.householdId.isEmpty ? _householdId : house.householdId,
      token: _api?.token,
      memberId: house.memberId,
      inviteCode: house.inviteCode,
      inviteExpiresAt: house.inviteExpiresAt,
      isPro: house.isPro,
      proUntil: house.proUntil,
      // This phone's own subscription is the truth for the plan; a stale
      // server copy must never overwrite it.
      plan: _storePro ? _plan : house.plan,
      members: house.members,
      pets: _mergePhotoState(pets),
      medications: medications,
      logs: _mergeLogs(house.logs, pending['logDose']),
    );
    _mergeCareEvents(house.careEvents);
  }

  /// [remote] plus local items whose create is still in the outbox.
  static List<T> _keepPending<T>(
    List<T> remote,
    List<T> local,
    Set<String>? pendingIds,
  ) {
    if (pendingIds == null || pendingIds.isEmpty) return remote;
    String id(T item) => switch (item) {
      Medication(:final id) => id,
      Pet(:final id) => id,
      _ => '',
    };
    final remoteIds = {for (final item in remote) id(item)};
    return [
      ...remote,
      for (final item in local)
        if (pendingIds.contains(id(item)) && !remoteIds.contains(id(item)))
          item,
    ];
  }

  /// Logs after a server snapshot. The server is the truth for the window
  /// it returns; a local log missing from it was removed there (e.g. a "not
  /// sure" resolved on another phone) and is deleted here too. Outside that
  /// window (older history, or past the server's cap) this phone's copy
  /// stays, and so does a dose still queued offline.
  List<DoseRecord> _mergeLogs(
    List<DoseRecord> remote, [
    Set<String>? pendingIds,
  ]) {
    final remoteIds = {for (final log in remote) log.id};
    final coveredFrom = _snapshotCoveredFrom(remote);
    final queued = <DoseRecord>[];
    final older = <DoseRecord>[];
    for (final log in _logs) {
      if (remoteIds.contains(log.id)) continue;
      if (pendingIds?.contains(log.id) ?? false) {
        queued.add(log);
      } else if (log.day.compareTo(coveredFrom) < 0) {
        older.add(log);
      } else {
        _deletedLogIds.add(log.id);
      }
    }
    return [...queued, ...remote, ...older];
  }

  /// First day a snapshot's logs are complete for. The server returns logs
  /// created in the last 100 days, capped at [_serverLogCap]: below the cap
  /// that is every day from 100 days ago (98 here, for clock and time-zone
  /// skew); at the cap only the days after the oldest one returned.
  String _snapshotCoveredFrom(List<DoseRecord> remote) {
    if (remote.length < _serverLogCap) {
      return dayKey(now.subtract(const Duration(days: 98)));
    }
    var oldest = remote.first.day;
    for (final log in remote) {
      if (log.day.compareTo(oldest) < 0) oldest = log.day;
    }
    final parsed = DateTime.tryParse(oldest);
    return parsed == null
        ? oldest
        : dayKey(DateTime(parsed.year, parsed.month, parsed.day + 1));
  }

  void _notifyPartnerLogs(HouseholdSnapshot house, Set<String> knownLogIds) {
    if (!isConnected || _memberId.isEmpty) return;
    for (final log in house.logs) {
      if (log.id.isEmpty || knownLogIds.contains(log.id)) continue;
      if (log.memberId.isEmpty || log.memberId == _memberId) continue;
      if (log.outcome != LogOutcome.given) continue;
      final medication = _findMedication(house.medications, log.medicationId);
      final pet = medication == null
          ? null
          : _findPet(house.pets, medication.petId);
      final member = _findMember(house.members, log.memberId);
      AppLog.event('push.partner_detected', {
        'logId': log.id,
        'memberId': log.memberId,
      });
      unawaited(
        PushService.notifyPartnerLogged(
          logId: log.id,
          who: member?.name ?? 'Someone',
          medicationName: medication?.name ?? 'a dose',
          petName: pet?.name ?? 'your pet',
        ).catchError((Object error, StackTrace stack) {
          AppLog.error('push.partner_failed', error, stack, {'logId': log.id});
        }),
      );
    }
  }

  static Medication? _findMedication(List<Medication> list, String id) {
    if (id.isEmpty) return null;
    for (final item in list) {
      if (item.id == id) return item;
    }
    return null;
  }

  static Pet? _findPet(List<Pet> list, String id) {
    if (id.isEmpty) return null;
    for (final item in list) {
      if (item.id == id) return item;
    }
    return null;
  }

  static Member? _findMember(List<Member> list, String id) {
    if (id.isEmpty) return null;
    for (final item in list) {
      if (item.id == id) return item;
    }
    return null;
  }

  /// Pre-Keychain builds cached the sitter token in preferences under
  /// `sitter_web_token_v1:<invite>`; migrated to [SecureTokens] on first use.
  static const _sitterTokenKey = SecureTokens.sitterKeyPrefix;

  /// Server limit for a sitter link's name.
  static const sitterLabelMax = 40;

  /// Default name offered in the "Who is this link for?" sheet,
  /// e.g. "Sitter · Oct 4".
  String defaultSitterLabel() {
    const months = [
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
    final t = now;
    return 'Sitter · ${months[t.month - 1]} ${t.day}';
  }

  /// Trimmed, never empty (falls back to [defaultSitterLabel]), at most
  /// [sitterLabelMax] characters.
  String normalizeSitterLabel(String? raw) {
    final trimmed = (raw ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
    final label = trimmed.isEmpty ? defaultSitterLabel() : trimmed;
    final chars = label.characters;
    return chars.length <= sitterLabelMax
        ? label
        : chars.take(sitterLabelMax).toString().trimRight();
  }

  SitterLink? _sitterLink;

  /// Owner: working sitter links from the server (see [loadSitterLinks]).
  final List<SitterLinkInfo> _sitterLinks = [];
  Future<String?>? _sitterLinksRunning;
  final Map<String, Future<String?>> _sitterRevokes = {};
  Future<String?>? _rotating;
  final Map<String, Future<String?>> _memberActions = {};

  /// The link shown on the invite screen, once loaded or created.
  SitterLink? get sitterLink => _sitterLink;

  /// Keyed by household, so rotating the invite code doesn't orphan the
  /// cached link. Older builds keyed it by invite code ([_legacySitterKey]).
  String get _sitterCacheKey => _householdId.isEmpty
      ? _legacySitterKey
      : '$_sitterTokenKey:h:$_householdId';

  String get _legacySitterKey => '$_sitterTokenKey:$_inviteCode';

  /// Cached link from secure storage. Older builds stored the bare token
  /// (Keychain or, before that, preferences); those load with no name.
  Future<SitterLink?> _cachedSitterLink(String cacheKey) async {
    try {
      var raw = await SecureTokens.read(cacheKey);
      if ((raw == null || raw.isEmpty) && cacheKey != _legacySitterKey) {
        // Saved under the invite code by an older build: move it over.
        final legacy = await SecureTokens.read(_legacySitterKey);
        if (legacy != null && legacy.isNotEmpty) {
          await SecureTokens.write(cacheKey, legacy);
          await SecureTokens.delete(_legacySitterKey);
          raw = legacy;
        }
      }
      if (raw == null || raw.isEmpty) {
        // Pre-Keychain builds kept it in preferences, under the invite code.
        final prefs = await SharedPreferences.getInstance();
        final prefsKey = prefs.containsKey(cacheKey)
            ? cacheKey
            : _legacySitterKey;
        final legacy = prefs.getString(prefsKey);
        if (legacy == null || legacy.isEmpty) return null;
        await SecureTokens.write(cacheKey, legacy);
        await prefs.remove(prefsKey);
        AppLog.event('sitter.token_migrated');
        raw = legacy;
      }
      final link = SitterLink.fromCache(raw);
      if (link.expiresAt != null && !link.expiresAt!.isAfter(now)) {
        await SecureTokens.delete(cacheKey);
        AppLog.event('sitter.link_expired');
        return null;
      }
      return link;
    } on Object catch (error, stack) {
      AppLog.error('sitter.token_read_failed', error, stack);
      return null;
    }
  }

  /// Loads the cached link only — never calls the server. Free or
  /// unconnected phones get null without a request.
  Future<SitterLink?> loadSitterLink() async {
    if (!canInviteHousehold || !isConnected || !isOwner) {
      return null;
    }
    final cached = await _cachedSitterLink(_sitterCacheKey);
    if (cached != null) {
      _sitterLink = cached;
      AppLog.event('sitter.link_cached', {'hasName': cached.label.isNotEmpty});
      notifyListeners();
    }
    return cached;
  }

  Future<String?>? _sitterLinkRunning;

  /// Returns a browser sitter link URL (Pro + connected), creating one named
  /// [label] when none is cached (or when [force]). The token is cached in
  /// secure storage; [sitterLink] holds name + expiry. Concurrent calls
  /// share one request.
  Future<String?> ensureSitterWebLink({bool force = false, String? label}) {
    return _sitterLinkRunning ??= _ensureSitterWebLink(
      force: force,
      label: label,
    ).whenComplete(() => _sitterLinkRunning = null);
  }

  Future<String?> _ensureSitterWebLink({
    required bool force,
    String? label,
  }) async {
    lastError = null;
    if (!canInviteHousehold) {
      AppLog.event('sitter.link_skipped', {'reason': 'free_tier'});
      return null;
    }
    if (!isOwner) {
      lastError = ownerOnlyMessage;
      AppLog.event('sitter.link_skipped', {'reason': 'role'});
      return null;
    }
    if (!isConnected) {
      AppLog.event('sitter.link_skipped', {'reason': 'not_connected'});
      return null;
    }
    final api = _api;
    if (api == null) {
      AppLog.event('sitter.link_skipped', {'reason': 'no_api'});
      return null;
    }
    if (_householdId.isEmpty && _inviteCode.isEmpty) {
      AppLog.event('sitter.link_skipped', {'reason': 'no_household_id'});
      return null;
    }
    final cacheKey = _sitterCacheKey;
    if (!force) {
      final cached = await _cachedSitterLink(cacheKey);
      if (cached != null) {
        _sitterLink = cached;
        AppLog.event('sitter.link_cached', {
          'hasName': cached.label.isNotEmpty,
        });
        notifyListeners();
        return cached.url;
      }
    }
    final name = normalizeSitterLabel(label);
    try {
      final link = await api.createSitterLink(label: name).catchError((
        Object error,
      ) async {
        // 403: the server doesn't see household Pro yet (RevenueCat webhook
        // or share step still in flight). Share this phone's Pro once, retry once.
        if (error is! HouseholdException ||
            error.status != 403 ||
            error.isRoleForbidden ||
            !_storePro) {
          throw error;
        }
        AppLog.event('sitter.link_retry', {'reason': 'household_not_pro'});
        await startTrial();
        return api.createSitterLink(label: name);
      });
      if (link.token.isEmpty) {
        AppLog.event('sitter.link_failed', {'reason': 'empty_token'});
        return null;
      }
      final created = SitterLink(
        token: link.token,
        label: name,
        expiresAt: link.expiresAt,
        id: link.id,
      );
      try {
        await SecureTokens.write(cacheKey, created.toCache());
      } on Object catch (error, stack) {
        // The link still works this time; it is just not cached.
        AppLog.error('sitter.token_write_failed', error, stack);
      }
      _sitterLink = created;
      // Show it in the owner's link list right away (no extra request).
      if (link.id.isNotEmpty) {
        _sitterLinks
          ..removeWhere((item) => item.id == link.id)
          ..insert(
            0,
            SitterLinkInfo(
              id: link.id,
              label: name,
              expiresAt: link.expiresAt,
              createdAt: now,
            ),
          );
      }
      AppLog.event('sitter.link_created', {
        'hasCustomName': name != defaultSitterLabel(),
        'expiresAt': link.expiresAt.toIso8601String(),
      });
      notifyListeners();
      return created.url;
    } on HouseholdException catch (error) {
      lastError = error.status == 403 && _storePro && !error.isRoleForbidden
          ? 'Your Pro is still being set up for the household. Try again in a minute.'
          : error.message;
      if (error.isRoleForbidden) _onRoleForbidden('sitter.link', error);
      AppLog.event('sitter.link_failed', {
        'kind': error.kind.name,
        if (error.status != null) 'status': error.status,
      });
      if (error.kind == HouseholdErrorKind.unauthorized) {
        await _dropSession('sitter_link_unauthorized', error);
      }
      return null;
    } catch (error, stack) {
      lastError = 'Could not create a browser link. Try again.';
      AppLog.error('sitter.link_failed', error, stack, {
        'error': error.runtimeType.toString(),
      });
      return null;
    }
  }

  void _mergeCareEvents(List<CareEvent> remote) {
    if (remote.isEmpty || !isConnected) return;
    _careEvents
      ..clear()
      ..addAll(remote);
    _persistEvents();
  }

  void _persistEvents() {
    unawaited(
      _eventsStore.write(List.of(_careEvents)).catchError((
        Object error,
        StackTrace stack,
      ) {
        AppLog.error('store.events_write_failed', error, stack);
      }),
    );
  }

  bool _persistQueued = false;
  Future<void>? _persistRunning;

  /// Saves the household. Every change in the same turn (and any change made
  /// while a save is still running) collapses into one write of the latest
  /// state, so a burst of updates never serializes the whole history twice.
  /// Set when launch couldn't read the saved household (see [restore]).
  bool _storeUnreadable = false;

  void _persist() {
    if (_store == null || _persistQueued || _storeUnreadable) return;
    _persistQueued = true;
    final previous = _persistRunning ?? Future<void>.value();
    _persistRunning = previous.then((_) => _writeStore());
  }

  Future<void> _writeStore() async {
    _persistQueued = false;
    final store = _store;
    if (store == null) return;
    final deleted = Set.of(_deletedLogIds);
    final replaceLogs = _replaceSavedLogs;
    _deletedLogIds.clear();
    _replaceSavedLogs = false;
    _historyFrom = null;
    _historyLoading = null;
    try {
      await store.write(
        StoredHousehold(
          householdId: _householdId,
          token: _api?.token,
          memberId: _memberId,
          inviteCode: _inviteCode,
          inviteExpiresAt: _inviteExpiresAt,
          // Server household Pro only. This phone's own subscription is read
          // from RevenueCat each launch (its SDK caches it for offline).
          isPro: _isPro,
          proUntil: _proUntil,
          plan: _plan,
          members: List.of(_members),
          pets: List.of(_pets),
          medications: List.of(_medications),
          archivedMedications: List.of(_archivedMedications),
          logs: List.of(_logs),
          deletedLogIds: deleted,
          replaceLogs: replaceLogs,
        ),
      );
    } catch (_) {
      // Logged by the store (`store.write_failed`). Memory still has every
      // change and the store's row cache didn't move, so the next save
      // (next change, or [flushPersist] on pause) writes the same rows.
      _deletedLogIds.addAll(deleted);
      _replaceSavedLogs |= replaceLogs;
    }
  }

  /// Waits for any queued save — call before the app is suspended.
  Future<void> flushPersist() async {
    while (_persistRunning != null) {
      final running = _persistRunning!;
      await running;
      if (identical(running, _persistRunning)) _persistRunning = null;
    }
  }

  void _changed() {
    notifyListeners();
    _persist();
  }

  /// For the photo/account extensions (notifyListeners is protected).
  void _notify() => notifyListeners();

  /// Puts this phone's household on the server so others can join.
  /// Returns a message when it could not.
  Future<String?> connect() {
    return _connecting ??= _connect().whenComplete(() => _connecting = null);
  }

  Future<String?> _connect() async {
    final api = _api;
    if (api == null) {
      AppLog.event('household.connect_skipped', {'reason': 'no_api'});
      return 'Sharing needs the online version of the app.';
    }
    if (isConnected) return null;
    if (!hasHousehold) {
      AppLog.event('household.connect_skipped', {'reason': 'no_household'});
      return 'Set up your pet first.';
    }
    try {
      final logs = await _logsForUpload();
      final session = await AppLog.trace(
        'household.create',
        () => api.createHousehold(
          owner: you,
          caregivers: [
            for (final m in _members)
              if (!m.isYou) m,
          ],
          pets: _pets,
          medications: _medications,
          logs: logs,
        ),
      );
      _applySession(session, joined: false);
      // The server checks RevenueCat for `household:member` — that customer
      // must exist (logIn) before we ask it to carry Pro, or it reads Free.
      await RevenueCatService.identifyMember(billingUserId);
      if (_storePro && !_isPro) await _carryProOnline(api);
      syncError = null;
      await _afterConnected();
      AppLog.event('household.connected');
      return null;
    } on HouseholdException catch (error) {
      AppLog.event('household.connect_failed', {'kind': error.kind.name});
      return error.message;
    }
  }

  /// The newest [_serverLogCap] logs, from disk as well as memory (memory
  /// holds only the recent window), for a household being put online.
  Future<List<DoseRecord>> _logsForUpload() async {
    final store = _store;
    if (store == null) return List.of(_logs);
    List<DoseRecord> saved;
    try {
      await flushPersist();
      saved = await store.readLogs(limit: _serverLogCap);
    } on Object catch (error, stack) {
      AppLog.error('store.read_failed', error, stack, {'table': 'dose_logs'});
      saved = const [];
    }
    // Memory first: it has anything a failed save didn't get to disk.
    final ids = {for (final log in _logs) log.id};
    return [
      ..._logs,
      for (final log in saved)
        if (!ids.contains(log.id)) log,
    ].take(_serverLogCap).toList();
  }

  /// Joins someone else's household with their invite code.
  Future<String?> join({required String code, required String name}) async {
    final api = _api;
    final cleanCode = code.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');
    if (cleanCode.length < 6) {
      AppLog.event('household.join_rejected', {'reason': 'short_code'});
      return 'Enter the 6-letter code you were sent.';
    }
    if (name.trim().isEmpty) {
      AppLog.event('household.join_rejected', {'reason': 'missing_name'});
      return 'Add your name so others know who gave it.';
    }
    if (api == null) {
      AppLog.event('household.join_skipped', {'reason': 'no_api'});
      return 'Joining needs the online version of the app.';
    }
    try {
      final session = await AppLog.trace(
        'household.join',
        () => api.join(code: cleanCode, name: name.trim()),
      );
      _applySession(session, joined: true);
      await RevenueCatService.identifyMember(billingUserId);
      // A subscriber joining a Free household brings Pro with them.
      if (_storePro && !_isPro) await _carryProOnline(api);
      syncError = null;
      await _afterConnected();
      AppLog.event('household.joined');
      return null;
    } on HouseholdException catch (error) {
      AppLog.event('household.join_failed', {'kind': error.kind.name});
      return error.message;
    }
  }

  /// The automatic sync (launch, resume): asks the server only when
  /// [SyncPolicy] says so — pending outbox changes, data older than
  /// 15 minutes, or never synced — and otherwise uses local data, logging
  /// `household.sync_skipped reason=fresh|no_network`. Pushes, pull to
  /// refresh and connect/join call [sync] with `force` directly.
  Future<void> syncIfStale({String source = 'auto'}) async {
    if (_api == null || !isConnected || syncing) {
      return sync(source: source); // logs no_api / not_connected / in_progress
    }
    var pending = false;
    try {
      pending = (await _syncEngine.outbox.read()).isNotEmpty;
    } on Object catch (error, stack) {
      // Unknown outbox: syncing is the safe side (it flushes first).
      AppLog.error('sync.outbox_read_failed', error, stack);
      pending = true;
    }
    final decision = SyncPolicy.decide(
      now: now,
      lastSuccess: _lastSyncedAt,
      hasPending: pending,
      offlineFailures: _offlineFailures,
      lastFailure: _lastFailureAt,
    );
    if (!decision.sync) {
      AppLog.event('household.sync_skipped', {
        'reason': decision.reasonName,
        'source': source,
        if (_lastSyncedAt != null)
          'secondsAgo': now.difference(_lastSyncedAt!).inSeconds,
      });
      return;
    }
    await sync(force: true, source: source, reason: decision.reasonName);
  }

  /// [force] bypasses the recent-sync window (e.g. pull-to-refresh).
  /// [source] (`auto`, `pull_refresh`, `retry`) goes on the one log line
  /// the sync ends with, so a tap doesn't need a line of its own.
  Future<void> sync({
    bool force = false,
    String source = 'auto',
    String? reason,
  }) async {
    final api = _api;
    if (api == null) {
      AppLog.event('household.sync_skipped', {'reason': 'no_api', 'source': source});
      return;
    }
    if (!isConnected) {
      AppLog.event('household.sync_skipped', {'reason': 'not_connected', 'source': source});
      return;
    }
    if (syncing) {
      AppLog.event('household.sync_skipped', {'reason': 'in_progress', 'source': source});
      return;
    }
    if (!force &&
        _lastSyncedAt != null &&
        now.difference(_lastSyncedAt!) < _syncMinInterval) {
      AppLog.event('household.sync_skipped', {
        'reason': 'recent',
        'source': source,
        'secondsAgo': now.difference(_lastSyncedAt!).inSeconds,
      });
      return;
    }
    syncing = true;
    syncError = null;
    notifyListeners();
    try {
      await loadRecentHistory();
      await _flushOutbox(silent: true);
      final house = await AppLog.trace('household.sync', api.fetchHousehold);
      _mergeSnapshot(house);
      _persist();
      _markSynced();
      AppLog.event('household.synced', {
        'doses': doses.length,
        'source': source,
        'reason': ?reason,
      });
      // Pending uploads/removals first, then fetch photos others set.
      await syncPetPhotos();
      await refreshPhotoCache();
      if (_storePro && !_isPro) {
        // Server confirmed the household is still Free: share this phone's Pro.
        await startTrial();
      }
    } on HouseholdException catch (error) {
      syncError = error.message;
      if (error.kind == HouseholdErrorKind.offline) {
        // Timeouts count as offline: nothing was merged, back off.
        _offlineFailures++;
        _lastFailureAt = now;
      }
      AppLog.event('household.sync_failed', {
        'kind': error.kind.name,
        'source': source,
      });
      if (error.kind == HouseholdErrorKind.unauthorized) {
        await _dropSession('sync_unauthorized', error);
      }
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Writes

  /// A subscription bought before sharing lives only in this phone's
  /// RevenueCat account; the new household starts as Free, so push it up.
  Future<void> _carryProOnline(HouseholdApi api) async {
    try {
      final billing = await api.startTrial();
      _isPro = billing.isPro;
      _proUntil = billing.isPro ? billing.proUntil : null;
      _armProExpiry();
      if (!_storePro) _plan = billing.plan;
      AppLog.event(
        billing.isPro
            ? 'billing.pro.carried_online'
            : 'billing.pro.carry_pending',
        {'plan': _plan.name, 'isPro': billing.isPro},
      );
    } on HouseholdException catch (error) {
      AppLog.event('billing.pro.carry_failed', {'kind': error.kind.name});
    }
  }

  /// Re-sends this phone's push token only if it (or the setting) changed
  /// since the last registration. Called at launch.
  Future<void> refreshPushRegistration() =>
      PushService.registerIfConnected(_api, force: false);

  Future<void> _afterConnected() async {
    _changed();
    await RevenueCatService.identifyMember(billingUserId);
    // Never blocks connect/join: the token may take seconds or never come
    // (simulator, notifications off). A late token registers itself.
    AppLog.unawaitedLogged(
      PushService.registerIfConnected(_api),
      'push.register_failed',
    );
    await _flushOutbox(silent: true);
    // Photos picked while solo (or on the old household) go up now.
    await syncPetPhotos();
    await refreshPhotoCache();
  }

  Future<void> _flushOutbox({bool silent = false}) async {
    final api = _api;
    if (api == null || !isConnected) return;
    try {
      final result = await AppLog.trace(
        'sync.batch',
        () => _syncEngine.flush(api),
      );
      if (result.applied == 0 && result.household == null) return;
      if (result.household != null) _mergeSnapshot(result.household!);
      if (result.roleMessage != null) {
        // A change made offline that this member's role no longer allows
        // (the owner changed it meanwhile). The snapshot above undid it.
        lastError = result.roleMessage;
        AppLog.event('sync.batch.role_rejected');
      }
      if (result.conflictMessage != null) {
        // An offline dose someone else had already logged: theirs wins.
        lastError = result.conflictMessage;
        AppLog.event('sync.batch.conflict', {
          'logId': result.conflictLog?.id ?? '',
        });
      }
      _changed();
    } on HouseholdException catch (error) {
      AppLog.event('sync.batch.failed', {'kind': error.kind.name});
      if (error.kind == HouseholdErrorKind.unauthorized) {
        await _dropSession('batch_unauthorized', error);
        return;
      }
      if (!silent) {
        lastError = error.message;
        notifyListeners();
      }
    }
  }

  /// Online first when shared. With no network the change is kept on the
  /// phone and, when [queue] is given, sent later in one batch (outbox).
  Future<bool> _write(
    String event,
    Future<void> Function(HouseholdApi api) online,
    bool Function() offline, {
    Map<String, Object?> fields = const {},
    SyncBatchOp Function()? queue,
  }) async {
    lastError = null;
    final api = _api;
    if (api != null && isConnected) {
      try {
        await AppLog.trace(event, () => online(api));
        _changed();
        AppLog.event('$event.completed', fields);
        return true;
      } on HouseholdException catch (error) {
        if (error.kind == HouseholdErrorKind.offline && queue != null) {
          final ok = offline();
          if (ok) {
            await _syncEngine.outbox.enqueue(queue());
            AppLog.event('$event.completed', {
              ...fields,
              'offline': true,
              'queued': true,
            });
            _changed();
          }
          return ok;
        }
        lastError = error.message;
        AppLog.event('$event.failed', {
          ...fields,
          'kind': error.kind.name,
          if (error.isRoleForbidden) 'reason': 'role',
        });
        if (error.isRoleForbidden) _onRoleForbidden(event, error);
        if (error.kind == HouseholdErrorKind.unauthorized) {
          await _dropSession('write_unauthorized', error);
        }
        notifyListeners();
        return false;
      }
    }
    final ok = offline();
    if (ok) {
      AppLog.event('$event.completed', {...fields, 'offline': true});
      _changed();
    }
    return ok;
  }

  /// The server no longer knows this phone's household link (member removed,
  /// owner signed out elsewhere). Keep every pet and dose on the phone so
  /// logging still works, and let the person join again with a code.
  ///
  /// For a caregiver or sitter a 401 means the owner removed them (code
  /// `member_removed`) or deleted the household ("This household no longer
  /// exists." / "Sign in again…"). For the owner it means the token moved to
  /// another phone.
  Future<void> _dropSession(String reason, [HouseholdException? error]) async {
    if (!isConnected) return;
    final removed = error?.isMemberRemoved ?? false;
    final deletedByOwner =
        !removed &&
        ((error?.message.contains('no longer exists') ?? false) ||
            you.role != MemberRole.owner);
    _api?.token = null;
    await _syncEngine.outbox.clear();
    await _keepPhotosAfterHouseholdGone();
    syncError = removed
        ? memberRemovedMessage
        : deletedByOwner
        ? householdDeletedMessage
        : 'This phone is no longer in the shared household. Your data is still here — join again with an invite code.';
    AppLog.event('household.session_expired', {'reason': reason});
    if (deletedByOwner) {
      AppLog.event('household.deleted_by_owner', {'reason': reason});
    }
    if (removed) AppLog.event('household.removed_by_owner', {'reason': reason});
    _changed();
  }

  static const memberRemovedMessage =
      'The owner removed you from this household. Your pets and doses are still on this phone.';

  static const householdDeletedMessage =
      'This household was deleted by its owner. Your pets and doses are still on this phone.';

  static SyncBatchOp _op(String type, Map<String, Object?> payload) =>
      SyncBatchOp(id: newId('op'), type: type, payload: payload);

  Future<bool> _record({
    required String doseId,
    required String memberId,
    required LogOutcome outcome,
    String amount = '',
    String? timeLabel,
    DoseOutcome? detail,
  }) {
    final split = doseId.lastIndexOf('.');
    final medicationId = split < 0 ? doseId : doseId.substring(0, split);
    final part = DayPart.values.firstWhere(
      (part) => part.name == doseId.substring(split + 1),
      orElse: () => DayPart.morning,
    );
    final medication = medicationById(medicationId);
    final today = dayKey(now);
    final event = switch (outcome) {
      LogOutcome.given => 'dose.log',
      LogOutcome.skipped => 'dose.skip',
      LogOutcome.uncertain => 'dose.uncertain',
    };
    final fields = {
      'doseId': doseId,
      'medicationId': medicationId,
      'part': part.name,
      'memberId': memberId,
      if (detail != null) 'detail': detail.name,
    };
    if (medication == null) {
      lastError = 'This medicine is no longer on the schedule.';
      AppLog.event('$event.rejected', {
        ...fields,
        'reason': 'missing_medication',
      });
      return Future.value(false);
    }
    final existing = _logFor(medicationId, part, today);
    // A "not sure" is replaced by the confirmed outcome — only once the new
    // log is actually kept, so a failed save leaves the warning in place.
    DoseRecord? replaces;
    if (existing != null) {
      if (existing.outcome == LogOutcome.uncertain &&
          outcome != LogOutcome.uncertain) {
        replaces = existing;
      } else {
        lastError =
            '${_who(existing.memberId)} already logged this at ${existing.timeLabel}.';
        AppLog.event('$event.rejected', {
          ...fields,
          'reason': 'already_logged',
          'existingMemberId': existing.memberId,
        });
        notifyListeners();
        return Future.value(false);
      }
    }
    final record = DoseRecord(
      id: newId('log'),
      medicationId: medicationId,
      part: part,
      day: today,
      memberId: memberId,
      outcome: outcome,
      amount: amount,
      timeLabel: timeLabel ?? _clockLabel(now),
      note: switch (detail) {
        DoseOutcome.vomited => 'Vomited a little after the dose',
        DoseOutcome.partial => 'Partial dose',
        DoseOutcome.lowAppetite => 'Low appetite',
        DoseOutcome.smooth || null => null,
      },
    );

    void keep(DoseRecord saved, Medication? updated) {
      if (replaces != null && _logs.remove(replaces)) {
        _deletedLogIds.add(replaces.id);
      }
      _logs.insert(0, saved);
      if (updated != null) _replaceMedication(updated);
    }

    return _write(
      event,
      (api) async {
        try {
          final saved = await api.logDose(record);
          keep(saved.log, saved.medication);
        } on HouseholdException catch (error) {
          final other = error.existing;
          if (error.kind == HouseholdErrorKind.conflict && other != null) {
            _logs.insert(0, other);
            _changed();
            throw HouseholdException(
              '${_who(other.memberId)} already logged this at ${other.timeLabel}.',
              kind: error.kind,
            );
          }
          rethrow;
        }
      },
      () {
        final left = outcome == LogOutcome.given && medication.tracksSupply
            ? max(medication.dosesLeft - 1, 0)
            : medication.dosesLeft;
        keep(record, medication.copyWith(dosesLeft: left));
        return true;
      },
      fields: fields,
      queue: () => _op('logDose', record.toJson()),
    );
  }

  Future<bool> logDose({
    required String doseId,
    required String memberId,
    required String amount,
    required String timeLabel,
    DoseOutcome? outcome,
  }) {
    return _record(
      doseId: doseId,
      memberId: memberId,
      outcome: LogOutcome.given,
      amount: amount,
      timeLabel: timeLabel,
      detail: outcome,
    );
  }

  Future<bool> skipDose(String doseId) {
    return _record(
      doseId: doseId,
      memberId: you.id,
      outcome: LogOutcome.skipped,
    );
  }

  /// Marks a dose as uncertain so the household checks before giving again.
  Future<bool> markDoseUncertain(String doseId) {
    return _record(
      doseId: doseId,
      memberId: you.id,
      outcome: LogOutcome.uncertain,
    );
  }

  Future<bool> addCareEvent({
    required String petId,
    required String title,
    required CareEventKind kind,
    required DateTime dueDate,
    String note = '',
  }) async {
    lastError = null;
    if (_roleBlocks('care_event.add', ownerOnly: false)) return false;
    if (tryPetById(petId) == null) {
      lastError = 'Pick which pet this is for.';
      AppLog.event('care_event.rejected', {
        'reason': 'missing_pet',
        'kind': kind.name,
      });
      return false;
    }
    if (title.trim().isEmpty) {
      lastError = 'Add a title for this appointment.';
      AppLog.event('care_event.rejected', {
        'reason': 'missing_title',
        'kind': kind.name,
      });
      return false;
    }
    _careEvents.add(
      CareEvent(
        id: newId('event'),
        petId: petId,
        title: title.trim(),
        kind: kind,
        dueDay: dayKey(dueDate),
        note: note.trim(),
      ),
    );
    _persistEvents();
    notifyListeners();
    AppLog.event('care_event.added', {'kind': kind.name, 'petId': petId});
    return true;
  }

  Future<void> removeCareEvent(String eventId) async {
    if (_roleBlocks('care_event.remove', ownerOnly: false)) return;
    CareEvent? removed;
    for (final event in _careEvents) {
      if (event.id == eventId) removed = event;
    }
    _careEvents.removeWhere((event) => event.id == eventId);
    _persistEvents();
    notifyListeners();
    AppLog.event('care_event.removed', {
      'eventId': eventId,
      'kind': ?removed?.kind.name,
    });
  }

  void _replaceMedication(Medication medication) {
    final index = _medications.indexWhere((item) => item.id == medication.id);
    if (index >= 0) {
      _medications[index] = medication;
    } else {
      _medications.add(medication);
    }
  }

  Future<bool> refill(String medicationId) {
    lastError = null;
    if (_roleBlocks('medication.refill', ownerOnly: false)) {
      return Future.value(false);
    }
    final medication = medicationById(medicationId);
    if (medication == null) {
      AppLog.event('medication.refill.rejected', {
        'medicationId': medicationId,
        'reason': 'missing_medication',
      });
      return Future.value(false);
    }
    return _write(
      'medication.refill',
      (api) async => _replaceMedication(await api.refill(medicationId)),
      () {
        _replaceMedication(
          medication.copyWith(dosesLeft: medication.supplyTotal),
        );
        return true;
      },
      fields: {'medicationId': medicationId},
      queue: () => _op('refill', {'id': medicationId}),
    );
  }

  /// Saves a repeating medicine. It shows up on Today right away.
  Future<bool> addMedication({
    required String petId,
    required String name,
    required String amount,
    required List<DayPart> parts,
    int supplyTotal = 0,
    String endDay = '',
    Map<DayPart, int> times = const {},
  }) {
    lastError = null;
    if (_roleBlocks('medication.add', ownerOnly: false)) {
      return Future.value(false);
    }
    if (name.trim().isEmpty) {
      lastError = 'Add the medicine name.';
      AppLog.event('medication.add_rejected', {'reason': 'missing_name'});
      return Future.value(false);
    }
    if (parts.isEmpty) {
      lastError = 'Pick at least one time of day.';
      AppLog.event('medication.add_rejected', {'reason': 'missing_parts'});
      return Future.value(false);
    }
    if (tryPetById(petId) == null) {
      lastError = 'Pick which pet this is for.';
      AppLog.event('medication.add_rejected', {
        'reason': 'missing_pet',
        'petId': petId,
      });
      return Future.value(false);
    }
    final medication = Medication(
      id: newId('med'),
      petId: petId,
      name: name.trim(),
      amount: amount.trim(),
      parts: [
        for (final part in DayPart.values)
          if (parts.contains(part)) part,
      ],
      supplyTotal: supplyTotal,
      dosesLeft: supplyTotal,
      startDay: dayKey(now),
      endDay: endDay,
      times: DoseTimes.normalize(times, parts),
    );
    return _write(
      'medication.add',
      (api) async => _replaceMedication(await api.addMedication(medication)),
      () {
        _replaceMedication(medication);
        return true;
      },
      fields: {
        'medicationId': medication.id,
        'petId': petId,
        'parts': parts.length,
        if (endDay.isNotEmpty) 'endDay': endDay,
        if (supplyTotal > 0) 'tracksSupply': true,
        if (medication.times.isNotEmpty) 'customTimes': medication.times.length,
      },
      queue: () => _op('addMedication', medication.toJson()),
    );
  }

  /// Sets a medicine's reminder times ([DoseTimes]; parts left out use the
  /// default). Offline it saves here and queues one `updateMedication` op
  /// that carries only the times, so a partner's other edits are never
  /// overwritten. Reminders re-plan through the repository listener.
  Future<bool> setMedicationTimes(
    String medicationId,
    Map<DayPart, int> times,
  ) {
    lastError = null;
    if (_roleBlocks('medication.times', ownerOnly: false)) {
      return Future.value(false);
    }
    final medication = medicationById(medicationId);
    if (medication == null) {
      lastError = 'That medicine was removed. Pull down to refresh.';
      AppLog.event('medication.times_rejected', {
        'medicationId': medicationId,
        'reason': 'missing_medication',
      });
      return Future.value(false);
    }
    final next = DoseTimes.normalize(times, medication.parts);
    if (DoseTimes.same(next, medication.times)) {
      AppLog.event('medication.times.noop', {'medicationId': medicationId});
      return Future.value(true);
    }
    final updated = medication.copyWith(times: next);
    return _write(
      'medication.times',
      (api) async => _replaceMedication(
        await api.updateMedicationTimes(medicationId, next),
      ),
      () {
        _replaceMedication(updated);
        return true;
      },
      fields: {'medicationId': medicationId, 'customTimes': next.length},
      queue: () => _op('updateMedication', {
        'id': medicationId,
        'times': DoseTimes.encode(next),
      }),
    );
  }

  Future<bool> removeMedication(String medicationId) {
    lastError = null;
    // Owner only — checked before the phone changes anything, so a
    // caregiver never sees a medicine vanish and come back.
    if (_roleBlocks('medication.remove', ownerOnly: true)) {
      return Future.value(false);
    }
    return _write(
      'medication.remove',
      (api) async {
        await api.removeMedication(medicationId);
        _archive(_medications.where((item) => item.id == medicationId));
        _medications.removeWhere((item) => item.id == medicationId);
      },
      () {
        _archive(_medications.where((item) => item.id == medicationId));
        _medications.removeWhere((item) => item.id == medicationId);
        return true;
      },
      fields: {'medicationId': medicationId},
      queue: () => _op('removeMedication', {'id': medicationId}),
    );
  }

  /// Adds a pet and returns its id, or null with [lastError] set.
  Future<String?> addPet({
    required String name,
    required Species species,
    int ageYears = 0,
    double weightKg = 0,
  }) async {
    lastError = null;
    if (_roleBlocks('pet.add', ownerOnly: false)) return null;
    if (name.trim().isEmpty) {
      lastError = "Add your pet's name.";
      AppLog.event('pet.add_rejected', {'reason': 'missing_name'});
      return null;
    }
    if (!canAddPet) {
      lastError = isPro
          ? 'A household can have up to ${PetLimits.maxPetsPerHousehold} pets.'
          : 'Free includes one pet. Upgrade to Pro for every pet in your household.';
      AppLog.event('pet.add.blocked', {
        'reason': isPro ? 'household_limit' : 'free_tier',
        'count': _pets.length,
      });
      return null;
    }
    if (_members.isEmpty) _members.add(_youMember);
    final pet = Pet(
      id: newId('pet'),
      name: name.trim(),
      species: species,
      ageYears: ageYears,
      breed: '',
      sex: '',
      conditions: const [],
      weightKg: weightKg,
      onTimePercent: 0,
      dailyMeds: 0,
    );
    final ok = await _write(
      'pet.add',
      (api) async => _pets.add(await api.addPet(pet)),
      () {
        _pets.add(pet);
        return true;
      },
      fields: {'petId': pet.id, 'species': species.name},
      queue: () => _op('addPet', pet.toJson()),
    );
    return ok ? pet.id : null;
  }

  /// Updates an existing pet. Returns false and sets [lastError] on failure.
  Future<bool> updatePet({
    required String petId,
    required String name,
    required Species species,
    int ageYears = 0,
    double weightKg = 0,
    List<String>? conditions,
  }) async {
    lastError = null;
    if (_roleBlocks('pet.update', ownerOnly: false)) return false;
    final existing = tryPetById(petId);
    if (existing == null) {
      lastError = 'This pet is no longer in your household.';
      AppLog.event('pet.update.missing', {'petId': petId});
      notifyListeners();
      return false;
    }

    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      lastError = "Add your pet's name.";
      AppLog.event('pet.update.rejected', {
        'petId': petId,
        'reason': 'missing_name',
      });
      notifyListeners();
      return false;
    }
    if (trimmed.length > PetLimits.maxNameLength) {
      lastError = 'Name is too long.';
      AppLog.event('pet.update.rejected', {
        'petId': petId,
        'reason': 'name_too_long',
      });
      notifyListeners();
      return false;
    }

    final nextConditions = conditions ?? existing.conditions;
    if (nextConditions.length > PetLimits.maxConditions) {
      lastError = 'Too many conditions selected.';
      AppLog.event('pet.update.rejected', {
        'petId': petId,
        'reason': 'too_many_conditions',
      });
      notifyListeners();
      return false;
    }

    final updated = existing.copyWith(
      name: trimmed,
      species: species,
      ageYears: PetLimits.clampAge(ageYears),
      weightKg: weightKg < 0 ? 0 : weightKg,
      conditions: List.unmodifiable(nextConditions),
    );

    final unchanged =
        updated.name == existing.name &&
        updated.species == existing.species &&
        updated.ageYears == existing.ageYears &&
        updated.weightKg == existing.weightKg &&
        _sameConditions(updated.conditions, existing.conditions);
    if (unchanged) {
      AppLog.event('pet.update.noop', {'petId': petId});
      return true;
    }

    final ok = await _write(
      'pet.update',
      (api) async {
        final saved = await api.updatePet(updated);
        final index = _pets.indexWhere((pet) => pet.id == petId);
        // The pet answer has no local photo state; keep this phone's.
        if (index >= 0) {
          _pets[index] = saved.withPhoto(
            photoKey: _pets[index].photoKey,
            photoUrl: _pets[index].photoUrl,
            photoVersion: _pets[index].photoVersion,
            photoSync: _pets[index].photoSync,
            photoPath: _pets[index].photoPath,
          );
        }
      },
      () {
        final index = _pets.indexWhere((pet) => pet.id == petId);
        if (index >= 0) _pets[index] = updated;
        return true;
      },
      fields: {'petId': petId, 'conditions': updated.conditions.length},
      queue: () => _op('updatePet', updated.toJson()),
    );

    if (ok && primaryPet?.id == petId) {
      unawaited(
        OnboardingProfile.syncFromPet(updated)
            .catchError((Object error, StackTrace stack) {
              AppLog.error('onboarding.profile_sync_failed', error, stack);
            }),
      );
    }
    return ok;
  }

  static bool _sameConditions(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    final left = {...a};
    final right = {...b};
    return left.length == right.length && left.containsAll(right);
  }

  Future<void> setPlan(BillingPlan value) async {
    if (_plan == value) return;
    _plan = value;
    notifyListeners();
    AppLog.event('billing.plan.changed', {'plan': value.name});
    if (!isConnected || !isOwner) {
      // Solo phone: the plan is a local paywall choice. Caregivers/sitters
      // can buy their own Pro but don't change the household's plan.
      _persist();
      AppLog.event('billing.plan.completed', {
        'plan': value.name,
        'local': true,
      });
      return;
    }
    await _write(
      'billing.plan',
      (api) async => _plan = await api.setPlan(value),
      () => true,
      fields: {'plan': value.name},
    );
  }

  /// Shares this phone's RevenueCat subscription with the household server
  /// so partners get Pro too. Never grants Pro on its own, and does nothing
  /// on a solo phone (Pro there *is* the RevenueCat entitlement). Kept under
  /// its old name; the endpoint is still `/v1/billing/trial`.
  Future<void> startTrial() async {
    if (!_storePro) {
      AppLog.event('billing.share_pro.skipped', {
        'reason': 'no_store_entitlement',
      });
      return;
    }
    final api = _api;
    if (api == null || !isConnected) return;
    try {
      final billing = await AppLog.trace('billing.share_pro', api.startTrial);
      _isPro = billing.isPro;
      _proUntil = billing.isPro ? billing.proUntil : null;
      _armProExpiry();
      if (!_storePro) _plan = billing.plan;
      _changed();
      AppLog.event('billing.share_pro.completed', {
        'plan': _plan.name,
        'householdPro': _isPro,
      });
    } on HouseholdException catch (error) {
      // Retried on the next launch / resume via [syncBillingFromStore].
      AppLog.event('billing.share_pro.failed', {'kind': error.kind.name});
      if (error.kind == HouseholdErrorKind.unauthorized) {
        await _dropSession('share_pro_unauthorized', error);
      }
    }
  }

  static const _lastStoreProKey = 'billing_store_pro_v1';

  /// This phone's RevenueCat Pro as of the last run, so RevenueCat loading an
  /// existing subscription at launch is not mistaken for a new unlock.
  bool _storeProLastRun = false;
  bool _proActiveLogged = false;

  /// One line per real change: `billing.pro.unlocked` on Free→Pro against
  /// the last saved state, otherwise `billing.pro.active` once per launch.
  void _onStoreProChanged(bool active, String via) {
    if (active) {
      if (_storeProLastRun) {
        if (!_proActiveLogged) {
          _proActiveLogged = true;
          AppLog.event('billing.pro.active', {'plan': _plan.name});
        }
      } else {
        _proActiveLogged = true;
        AppLog.event('billing.pro.unlocked', {
          'plan': _plan.name,
          'source': 'revenuecat',
          'via': via,
        });
      }
    }
    if (_storeProLastRun == active) return;
    _storeProLastRun = active;
    AppLog.unawaitedLogged(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_lastStoreProKey, active);
    }(), 'store.billing_state_failed');
  }

  /// Store plan wins while this phone's subscription is active; pushed to a
  /// connected household once when it differs.
  Future<void> _adoptStorePlan(BillingPlan? plan) async {
    if (plan == null || plan == _plan) return;
    await setPlan(plan);
  }

  /// Buys the selected plan through RevenueCat, then unlocks Pro locally.
  /// [package] is the exact one the paywall showed (placement offering).
  Future<PurchaseResult> purchasePlan({Package? package}) async {
    AppLog.event('billing.purchase.requested', {'plan': _plan.name});
    final result = await RevenueCatService.purchasePlan(
      _plan,
      package: package,
    );
    if (result.success) {
      // The store listener may already have applied this purchase.
      final wasPro = _storePro;
      _storePro = true;
    _armProExpiry();
      _armProExpiry();
      if (!wasPro) {
        _onStoreProChanged(true, 'purchase');
        _changed();
      }
      await startTrial();
      AppLog.event('billing.purchase.completed', {
        'plan': _plan.name,
        'isPro': isPro,
      });
    } else {
      lastError = result.message;
      AppLog.event('billing.purchase.failed', {
        'kind': result.kind?.name ?? 'unknown',
      });
      notifyListeners();
    }
    return result;
  }

  /// Restores an App Store / Play subscription and syncs Pro status.
  Future<bool> restoreBilling() async {
    AppLog.event('billing.restore.requested');
    lastError = null;
    if (!RevenueCatService.isReady) {
      lastError = 'Purchases aren’t available right now. Try again later.';
      AppLog.event('billing.restore.skipped', {'reason': 'not_configured'});
      notifyListeners();
      return false;
    }
    final restored = await RevenueCatService.restorePurchases();
    if (restored == null) {
      lastError =
          'Couldn’t reach the App Store. Check your connection and try again.';
      AppLog.event('billing.restore.failed');
      notifyListeners();
      return false;
    }
    if (!restored) {
      lastError = 'No subscription found for this Apple ID.';
      AppLog.event('billing.restore.empty');
      notifyListeners();
      return false;
    }
    // Restore already confirmed the entitlement; don't ask the store twice.
    final wasPro = _storePro;
    _storePro = true;
    _armProExpiry();
    if (!wasPro) _onStoreProChanged(true, 'restore');
    _changed();
    await startTrial();
    await _adoptStorePlan((await RevenueCatService.currentStatus()).plan);
    AppLog.event('billing.restore.completed', {'plan': _plan.name});
    return true;
  }

  /// Counts and flags for RevenueCat Audiences — never names or emails.
  Map<String, String> get billingAttributes => {
    'pet_count': '${_pets.length}',
    'medication_count': '${_medications.length}',
    'household_members': '${_members.length}',
    'has_household': '$hasHousehold',
    'is_pro': '$isPro',
  };

  /// Live store updates (late purchase, Ask to Buy approval, renewal,
  /// expiry, refund) from [RevenueCatService.onEntitlementChanged].
  void applyStoreEntitlement(bool active, BillingPlan? plan) {
    if (active && plan != null && plan != _plan) {
      AppLog.unawaitedLogged(_adoptStorePlan(plan), 'billing.plan.failed');
    }
    if (_storePro == active) return;
    _storePro = active;
    _armProExpiry();
    // Shared households keep whatever the server says (partner may pay).
    AppLog.event('billing.store.entitlement_changed', {
      'active': active,
      'plan': plan?.name ?? 'unknown',
      if (isConnected) 'householdPro': _isPro,
    });
    _onStoreProChanged(active, 'store_update');
    _changed();
    // Share with the household only once a sync this session has confirmed
    // it is still Free — at launch the saved flag may be stale, and the
    // first sync shares if needed (no extra call on a normal launch).
    if (active && !_isPro && isConnected && _lastSyncedAt != null) {
      AppLog.unawaitedLogged(startTrial(), 'billing.share_pro.failed');
    }
  }

  /// Pulls Pro status from RevenueCat on app start or resume.
  Future<void> syncBillingFromStore() async {
    if (!RevenueCatService.isReady) {
      AppLog.event('billing.sync.skipped', {'reason': 'not_configured'});
      return;
    }
    await RevenueCatService.identifyMember(billingUserId);
    AppLog.unawaitedLogged(
      RevenueCatService.syncAttributes(billingAttributes),
      'billing.rc.attributes_failed',
    );
    final status = await RevenueCatService.currentStatus();
    final storeChanged = _storePro != status.isPro;
    _storePro = status.isPro;
    _armProExpiry();
    if (storeChanged) _changed();
    if (status.isPro) {
      _onStoreProChanged(true, 'store_sync');
      await _adoptStorePlan(status.plan);
      // Share with the household only when a sync this session confirmed
      // it is Free; otherwise the next sync decides (see [sync]).
      if (!_isPro && _lastSyncedAt != null) await startTrial();
    } else if (storeChanged) {
      _onStoreProChanged(false, 'store_sync');
    }
    if (status.isPro && storeChanged) {
      AppLog.event('billing.sync.pro_unlocked', {'plan': _plan.name});
    } else if (!status.isPro && storeChanged) {
      // Shared households keep server Pro (a partner may pay); solo phones
      // drop to Free because isPro is RevenueCat-only.
      AppLog.event('billing.sync.pro_revoked', {'householdPro': isPro});
    } else {
      AppLog.event('billing.sync.unchanged', {
        'isPro': isPro,
        'storePro': _storePro,
        'plan': _plan.name,
      });
    }
  }

  /// Builds the household from onboarding answers, then shares it in the background.
  void applyOnboarding(OnboardingViewModel model) {
    if (!model.hasValidPetName) return;
    if (_pets.isNotEmpty) return;

    _members
      ..clear()
      ..add(_youMember);
    final used = <String>{'you'};
    for (final caregiver in model.caregivers) {
      if (caregiver == 'Just me') continue;
      final member = _memberFromCaregiver(caregiver, used.length);
      if (!used.add(member.id)) continue;
      _members.add(member);
    }

    final weight = double.tryParse(model.weight.trim().replaceAll(',', '.'));
    _pets.add(
      Pet(
        id: newId('pet'),
        name: model.petName.trim(),
        species: model.species,
        ageYears: model.ageYears,
        breed: '',
        sex: '',
        conditions: model.conditions.toList(),
        weightKg: weight ?? 0,
        onTimePercent: 0,
        dailyMeds: 0,
      ),
    );
    _medications.clear();
    _logs.clear();
    _changed();
    final photo = model.photoBytes;
    if (photo != null) {
      // Picked before the pet existed; saved now that it has an id.
      AppLog.unawaitedLogged(
        setPetPhoto(_pets.last.id, photo, source: 'onboarding'),
        'pet.photo_save_failed',
      );
    }
    AppLog.event('household.created_from_onboarding', {
      'reminders': model.remindersOn,
      'conditions': model.conditions.length,
      'caregivers': model.caregivers.length,
      'localOnly': _api != null && !isConnected,
    });
  }

  /// Leaves the shared household on the server, then clears this phone.
  /// Returns a message when it could not (nothing is cleared then).
  Future<String?> leaveHousehold() async {
    final api = _api;
    if (api != null && isConnected) {
      try {
        await AppLog.trace('household.leave', api.leaveHousehold);
      } on HouseholdException catch (error) {
        // 401: the server already dropped this phone — finish locally.
        if (error.kind != HouseholdErrorKind.unauthorized) {
          AppLog.event('household.leave_failed', {'kind': error.kind.name});
          return error.kind == HouseholdErrorKind.offline
              ? "Can't reach the household. Connect to the internet to leave, so others stop seeing you."
              : error.message;
        }
      }
    }
    AppLog.event('household.left', {'wasConnected': isConnected});
    await reset();
    return null;
  }

  /// Forgets this phone's household, for sign-out or a fresh start.
  Future<void> reset() async {
    _apply(
      token: null,
      memberId: 'you',
      inviteCode: '',
      isPro: false,
      plan: BillingPlan.yearly,
      members: const [],
      pets: const [],
      medications: const [],
      logs: const [],
    );
    await flushPersist();
    // Each clear is isolated: a failing database must not stop the reset
    // (account deletion then removes the file itself).
    Future<void> clearing(String table, Future<void>? Function() run) async {
      try {
        await run();
      } on Object catch (error, stack) {
        AppLog.error('store.clear_failed', error, stack, {'table': table});
      }
    }

    await clearing('household', () => _store?.clear());
    _storeUnreadable = false;
    try {
      await SecureTokens.deleteSitterTokens();
    } on Object catch (error, stack) {
      AppLog.error('sitter.token_clear_failed', error, stack);
    }
    await clearing('outbox', _syncEngine.outbox.clear);
    syncError = null;
    _careEvents.clear();
    await clearing('care_events', _eventsStore.clear);
    _storePro = false;
    _storeProLastRun = false;
    _proActiveLogged = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_lastStoreProKey);
    } on Object catch (error, stack) {
      AppLog.error('store.billing_state_failed', error, stack);
    }
    await RevenueCatService.logOut();
    await UpgradeNudgeState.clear();
    _lastSyncedAt = null;
    _offlineFailures = 0;
    _lastFailureAt = null;
    try {
      await (await SharedPreferences.getInstance()).remove(_lastSyncKey);
    } on Object catch (error, stack) {
      AppLog.error('store.last_sync_failed', error, stack);
    }
    _sitterLink = null;
    _sitterLinks.clear();
    _archivedMedications.clear();
    _deletedLogIds.clear();
    _replaceSavedLogs = false;
    await _clearPhotos();
    AppLog.event('household.reset');
    notifyListeners();
  }

  /// "8:02 AM" — how log times are written.
  static String clockLabel(DateTime time) => _clockLabel(time);

  static String _clockLabel(DateTime time) {
    final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${time.hour < 12 ? 'AM' : 'PM'}';
  }

  static const _youMember = Member(
    id: 'you',
    name: 'You',
    initials: 'You',
    role: MemberRole.owner,
    avatarTone: AvatarTone.brand,
    isYou: true,
  );

  static Member _memberFromCaregiver(String label, int index) {
    final slug = label
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final id = slug.isEmpty
        ? 'member-$index'
        : slug.substring(0, min(slug.length, 40));
    final trimmed = label.trim();
    return Member(
      id: id == 'you' ? 'member-$index' : id,
      name: trimmed.isEmpty ? 'Helper' : trimmed,
      initials: trimmed.isEmpty ? '?' : trimmed.characters.first.toUpperCase(),
      role: label.toLowerCase().contains('sitter')
          ? MemberRole.sitter
          : MemberRole.caregiver,
      avatarTone: AvatarTone.soft,
      status: 'Not joined yet',
      joined: false,
    );
  }

  /// Demo household used by widget tests.
  @visibleForTesting
  void loadSampleData() {
    final today = dayKey(now);
    _apply(
      token: null,
      memberId: 'you',
      inviteCode: '',
      isPro: false,
      plan: BillingPlan.yearly,
      members: const [
        _youMember,
        Member(
          id: 'sara',
          name: 'Sara',
          initials: 'S',
          role: MemberRole.caregiver,
          avatarTone: AvatarTone.soft,
          status: 'Active now',
          active: true,
        ),
        Member(
          id: 'dan',
          name: 'Dan',
          initials: 'D',
          role: MemberRole.caregiver,
          avatarTone: AvatarTone.neutral,
        ),
      ],
      pets: const [
        Pet(
          id: 'miso',
          name: 'Miso',
          species: Species.cat,
          ageYears: 12,
          breed: 'Domestic shorthair',
          sex: 'female',
          conditions: ['Diabetes', 'Kidney disease'],
          weightKg: 4.6,
          onTimePercent: 0,
          dailyMeds: 0,
        ),
        Pet(
          id: 'juniper',
          name: 'Juniper',
          species: Species.dog,
          ageYears: 8,
          breed: 'Mixed breed',
          sex: 'female',
          conditions: ['Arthritis'],
          weightKg: 18.2,
          onTimePercent: 0,
          dailyMeds: 0,
        ),
      ],
      medications: [
        Medication(
          id: 'insulin',
          petId: 'miso',
          name: 'Insulin',
          amount: '2 units',
          parts: const [DayPart.morning, DayPart.evening],
          supplyTotal: 0,
          dosesLeft: 0,
          startDay: today,
        ),
        Medication(
          id: 'benazepril',
          petId: 'miso',
          name: 'Benazepril',
          amount: '2.5 mg',
          parts: const [DayPart.morning],
          supplyTotal: 30,
          dosesLeft: 4,
          startDay: today,
        ),
        Medication(
          id: 'joint',
          petId: 'juniper',
          name: 'Joint supplement',
          amount: '',
          parts: const [DayPart.morning],
          supplyTotal: 0,
          dosesLeft: 0,
          startDay: today,
        ),
        Medication(
          id: 'fluids',
          petId: 'miso',
          name: 'Fluids',
          amount: '100 ml',
          parts: const [DayPart.afternoon],
          supplyTotal: 0,
          dosesLeft: 0,
          startDay: today,
        ),
      ],
      logs: [
        DoseRecord(
          id: 'log-joint',
          medicationId: 'joint',
          part: DayPart.morning,
          day: today,
          memberId: 'dan',
          outcome: LogOutcome.given,
          amount: '',
          timeLabel: '8:30 AM',
        ),
        DoseRecord(
          id: 'log-benazepril',
          medicationId: 'benazepril',
          part: DayPart.morning,
          day: today,
          memberId: 'sara',
          outcome: LogOutcome.given,
          amount: '2.5 mg',
          timeLabel: '8:04 AM',
        ),
        DoseRecord(
          id: 'log-insulin',
          medicationId: 'insulin',
          part: DayPart.morning,
          day: today,
          memberId: 'sara',
          outcome: LogOutcome.given,
          amount: '2 units',
          timeLabel: '8:02 AM',
        ),
      ],
    );
    notifyListeners();
  }
}
