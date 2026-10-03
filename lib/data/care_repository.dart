import 'dart:async';
import 'dart:math';

import 'package:characters/characters.dart';
import 'package:flutter/foundation.dart';
import 'package:pawsitive_sync/core/constants/pet_limits.dart';
import 'package:pawsitive_sync/core/legal/app_links.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/data/care_events_store.dart';
import 'package:pawsitive_sync/data/household_api.dart';
import 'package:pawsitive_sync/data/household_store.dart';
import 'package:pawsitive_sync/data/push_service.dart';
import 'package:pawsitive_sync/data/sync_engine.dart';
import 'package:pawsitive_sync/data/onboarding_profile.dart';
import 'package:pawsitive_sync/data/upgrade_nudge_state.dart';
import 'package:pawsitive_sync/data/revenue_cat_service.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_view_model.dart';
import 'package:purchases_flutter/purchases_flutter.dart' show Package;
import 'package:shared_preferences/shared_preferences.dart';

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
  });

  final Medication medication;
  final int given;
  final int expected;

  double get fraction => expected == 0 ? 0 : (given / expected).clamp(0, 1);
}

class PetReport {
  const PetReport({
    required this.from,
    required this.to,
    required this.lines,
    required this.skipped,
    required this.notes,
  });

  final DateTime from;
  final DateTime to;
  final List<ReportLine> lines;
  final int skipped;

  /// Note text and how many times it was logged.
  final Map<String, int> notes;

  bool get isEmpty => lines.every((line) => line.given == 0) && skipped == 0;
}

/// The household: pets, people, medicine schedules, and every logged dose.
///
/// Works on the phone first and saves locally. When the API is set, the
/// household is created on the server and shared with everyone who joins.
class CareRepository extends ChangeNotifier {
  CareRepository({
    HouseholdApi? api,
    HouseholdStore? store,
    CareEventsStore? eventsStore,
    SyncEngine? syncEngine,
    DateTime Function()? clock,
    bool sample = false,
  }) : _api = api,
       _store = store,
       _eventsStore = eventsStore ?? CareEventsStore(),
       _syncEngine = syncEngine ?? SyncEngine(),
       _clock = clock ?? DateTime.now {
    if (sample) loadSampleData();
  }

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

  bool syncing = false;
  String? syncError;

  /// The last write problem, worded for the person.
  String? lastError;

  String _memberId = 'you';
  String _inviteCode = '';
  String _householdId = '';
  final List<Member> _members = [];
  final List<Pet> _pets = [];
  final List<Medication> _medications = [];
  final List<DoseRecord> _logs = [];
  final List<CareEvent> _careEvents = [];

  /// Household Pro from the server (webhook or trial) — shared with partners.
  bool _isPro = false;

  /// This phone's own App Store / Play subscription, straight from RevenueCat.
  /// Kept apart so a server refresh can never lock out a paying user while
  /// the purchase webhook is still in flight.
  bool _storePro = false;
  BillingPlan _plan = BillingPlan.yearly;
  Future<String?>? _connecting;
  DateTime? _lastSyncedAt;
  static const _syncMinInterval = Duration(seconds: 45);

  DateTime get now => _clock();

  bool get hasApi => _api != null;

  /// This phone is linked to a shared household on the server.
  bool get isConnected => _api?.token != null;

  bool get canSync => isConnected;

  bool get hasHousehold => _members.isNotEmpty;

  String get inviteCode => _inviteCode;

  /// Store account id. Empty until shared, so RevenueCat keeps its own
  /// per-install id; never the bare member id (every owner is 'you').
  String get billingUserId =>
      isConnected && _householdId.isNotEmpty ? '$_householdId:$_memberId' : '';

  bool get isPro => _isPro || _storePro;

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

  List<Member> get members => List.unmodifiable(_members);
  List<Pet> get pets => List.unmodifiable(_pets);
  List<Medication> get medications => List.unmodifiable(_medications);
  List<DoseRecord> get logs => List.unmodifiable(_logs);

  Member get you =>
      _members.firstWhere((member) => member.isYou, orElse: () => _youMember);

  /// Falls back to a neutral member so stale IDs never crash a screen.
  Member memberById(String id) => _members.firstWhere(
    (member) => member.id == id,
    orElse: () => Member(
      id: id,
      name: 'Someone',
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
    final result = <Dose>[];
    for (final part in DayPart.values) {
      for (final medication in _medications) {
        if (!medication.parts.contains(part)) continue;
        if (!medication.isActiveOn(today)) continue;
        final log = _logFor(medication.id, part, today);
        if (log?.outcome == LogOutcome.skipped) continue;
        final pet = petById(medication.petId);
        final uncertain = log?.outcome == LogOutcome.uncertain;
        final status = log?.outcome == LogOutcome.given
            ? DoseStatus.given
            : time.hour >= part.opensAt
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
              DoseStatus.due => '${pet.name} · due ${part.timeLabel}',
              DoseStatus.upcoming => '${pet.name} · ${part.timeLabel}',
            },
            givenById: log?.memberId,
            givenAt: log?.timeLabel ?? '',
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
          final medication = medicationById(log.medicationId);
          final pet = medication == null ? null : tryPetById(medication.petId);
          final petName = pet?.name ?? 'your pet';
          final name = medication?.name ?? 'A medicine';
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

  /// Given vs. expected doses for the last [days] days, from real logs only.
  PetReport reportFor(String petId, int days) {
    final time = now;
    final today = DateTime(time.year, time.month, time.day);
    final from = today.subtract(Duration(days: days - 1));
    final fromKey = dayKey(from);
    final lines = <ReportLine>[];
    var skipped = 0;
    final notes = <String, int>{};
    for (final medication in medicationsFor(petId)) {
      final start = DateTime.tryParse(medication.startDay) ?? today;
      var expected = 0;
      for (
        var day = start.isAfter(from) ? start : from;
        !day.isAfter(today);
        day = DateTime(day.year, day.month, day.day + 1)
      ) {
        if (!medication.isActiveOn(dayKey(day))) continue;
        for (final part in medication.parts) {
          if (day == today && time.hour < part.opensAt) continue;
          expected++;
        }
      }
      var given = 0;
      for (final log in _logs) {
        if (log.medicationId != medication.id) continue;
        if (log.day.compareTo(fromKey) < 0) continue;
        if (log.outcome == LogOutcome.given) {
          given++;
        } else {
          skipped++;
        }
        final note = log.note;
        if (note != null && note.isNotEmpty) {
          notes[note] = (notes[note] ?? 0) + 1;
        }
      }
      lines.add(
        ReportLine(
          medication: medication,
          given: given,
          expected: max(expected, given),
        ),
      );
    }
    return PetReport(
      from: from,
      to: today,
      lines: lines,
      skipped: skipped,
      notes: notes,
    );
  }

  // ---------------------------------------------------------------------------
  // Loading and syncing

  /// Reads what this phone saved last time. Call once at launch.
  List<CareEvent> get careEvents => List.unmodifiable(_careEvents);

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
    _careEvents
      ..clear()
      ..addAll(await _eventsStore.read());
    final saved = await _store?.read();
    if (saved == null) return;
    _apply(
      householdId: saved.householdId,
      token: saved.token,
      memberId: saved.memberId,
      inviteCode: saved.inviteCode,
      isPro: saved.isPro,
      plan: saved.plan,
      members: saved.members,
      pets: saved.pets,
      medications: saved.medications,
      logs: saved.logs,
    );
    AppLog.event('data.restored', {
      'pets': _pets.length,
      'medications': _medications.length,
      'logs': _logs.length,
      'careEvents': _careEvents.length,
      'connected': isConnected,
    });
    notifyListeners();
  }

  void _apply({
    String householdId = '',
    required String? token,
    required String memberId,
    required String inviteCode,
    required bool isPro,
    required BillingPlan plan,
    required List<Member> members,
    required List<Pet> pets,
    required List<Medication> medications,
    required List<DoseRecord> logs,
  }) {
    _api?.token = token;
    _memberId = memberId.isEmpty ? 'you' : memberId;
    _inviteCode = inviteCode;
    _householdId = householdId;
    _isPro = isPro;
    _plan = plan;
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
  }

  void _applySession(HouseholdSession session) {
    final house = session.snapshot;
    _apply(
      householdId: house.householdId,
      token: session.token,
      memberId: house.memberId,
      inviteCode: house.inviteCode,
      isPro: house.isPro,
      plan: house.plan,
      members: house.members,
      pets: house.pets,
      medications: house.medications,
      logs: house.logs,
    );
    _mergeCareEvents(house.careEvents);
  }

  void _mergeSnapshot(HouseholdSnapshot house) {
    final knownLogIds = {for (final log in _logs) log.id};
    _notifyPartnerLogs(house, knownLogIds);
    _apply(
      householdId: house.householdId.isEmpty ? _householdId : house.householdId,
      token: _api?.token,
      memberId: house.memberId,
      inviteCode: house.inviteCode,
      isPro: house.isPro,
      plan: house.plan,
      members: house.members,
      pets: house.pets,
      medications: house.medications,
      logs: house.logs,
    );
    _mergeCareEvents(house.careEvents);
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
        'who': member?.name ?? 'Someone',
      });
      unawaited(
        PushService.notifyPartnerLogged(
          logId: log.id,
          who: member?.name ?? 'Someone',
          medicationName: medication?.name ?? 'a dose',
          petName: pet?.name ?? 'your pet',
        ),
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

  static const _sitterTokenKey = 'sitter_web_token_v1';

  /// Returns a browser sitter link (Pro + connected). Caches the token locally.
  Future<String?> ensureSitterWebLink({bool force = false}) async {
    if (!canInviteHousehold) {
      AppLog.event('sitter.link_skipped', {'reason': 'free_tier'});
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
    if (_inviteCode.isEmpty) {
      AppLog.event('sitter.link_skipped', {'reason': 'no_invite_code'});
      return null;
    }
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = '$_sitterTokenKey:$_inviteCode';
    if (!force) {
      final cached = prefs.getString(cacheKey);
      if (cached != null && cached.isNotEmpty) {
        AppLog.event('sitter.link_cached');
        return AppLinks.sitterWebLink(cached);
      }
    }
    try {
      final link = await api.createSitterLink();
      if (link.token.isEmpty) {
        AppLog.event('sitter.link_failed', {'reason': 'empty_token'});
        return null;
      }
      await prefs.setString(cacheKey, link.token);
      AppLog.event('sitter.link_ready', {
        'expiresAt': link.expiresAt.toIso8601String(),
      });
      return AppLinks.sitterWebLink(link.token);
    } on HouseholdException catch (error) {
      AppLog.event('sitter.link_failed', {'kind': error.kind.name});
      return null;
    } catch (_) {
      AppLog.event('sitter.link_failed');
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
    unawaited(_eventsStore.write(_careEvents));
  }

  void _persist() {
    final store = _store;
    if (store == null) return;
    unawaited(
      store.write(
        StoredHousehold(
          householdId: _householdId,
          token: _api?.token,
          memberId: _memberId,
          inviteCode: _inviteCode,
          isPro: _isPro,
          plan: _plan,
          members: _members,
          pets: _pets,
          medications: _medications,
          logs: _logs,
        ),
      ),
    );
  }

  void _changed() {
    notifyListeners();
    _persist();
  }

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
      final wasPro = _isPro;
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
          logs: _logs,
        ),
      );
      _applySession(session);
      if (wasPro && !_isPro) await _carryProOnline(api);
      syncError = null;
      await _afterConnected();
      AppLog.event('household.connected');
      return null;
    } on HouseholdException catch (error) {
      AppLog.event('household.connect_failed', {'kind': error.kind.name});
      return error.message;
    }
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
      _applySession(session);
      syncError = null;
      await _afterConnected();
      AppLog.event('household.joined');
      return null;
    } on HouseholdException catch (error) {
      AppLog.event('household.join_failed', {'kind': error.kind.name});
      return error.message;
    }
  }

  /// Pulls server state when already connected. Skips if synced recently.
  Future<void> syncIfStale() => sync();

  /// [force] bypasses the recent-sync window (e.g. pull-to-refresh).
  Future<void> sync({bool force = false}) async {
    final api = _api;
    if (api == null) {
      AppLog.event('household.sync_skipped', {'reason': 'no_api'});
      return;
    }
    if (!isConnected) {
      AppLog.event('household.sync_skipped', {'reason': 'not_connected'});
      return;
    }
    if (syncing) {
      AppLog.event('household.sync_skipped', {'reason': 'in_progress'});
      return;
    }
    if (!force &&
        _lastSyncedAt != null &&
        now.difference(_lastSyncedAt!) < _syncMinInterval) {
      AppLog.event('household.sync_skipped', {
        'reason': 'recent',
        'secondsAgo': now.difference(_lastSyncedAt!).inSeconds,
      });
      return;
    }
    syncing = true;
    syncError = null;
    notifyListeners();
    try {
      await _flushOutbox(silent: true);
      final house = await AppLog.trace('household.sync', api.fetchHousehold);
      _mergeSnapshot(house);
      _persist();
      _lastSyncedAt = now;
      AppLog.event('household.synced', {'doses': doses.length});
    } on HouseholdException catch (error) {
      syncError = error.message;
      AppLog.event('household.sync_failed', {'kind': error.kind.name});
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Writes

  /// A trial or purchase started before sharing lives only on this phone; the
  /// new household starts as Free, so push Pro up instead of losing it.
  Future<void> _carryProOnline(HouseholdApi api) async {
    try {
      final billing = await api.startTrial();
      _isPro = billing.isPro;
      _plan = billing.plan;
      AppLog.event('billing.pro.carried_online', {'plan': _plan.name});
    } on HouseholdException catch (error) {
      _isPro = true;
      AppLog.event('billing.pro.carry_failed', {'kind': error.kind.name});
    }
  }

  Future<void> _afterConnected() async {
    _changed();
    await RevenueCatService.identifyMember(billingUserId);
    await PushService.registerIfConnected(_api);
    await _flushOutbox(silent: true);
  }

  Future<void> _flushOutbox({bool silent = false}) async {
    final api = _api;
    if (api == null || !isConnected) return;
    try {
      final result = await AppLog.trace(
        'sync.batch',
        () => _syncEngine.flush(api),
      );
      if (result.household != null) _mergeSnapshot(result.household!);
      if (!silent && result.conflictMessage != null) {
        lastError = result.conflictMessage;
      }
      _changed();
    } on HouseholdException catch (error) {
      if (!silent) {
        lastError = error.message;
        notifyListeners();
      }
    }
  }

  Future<bool> _write(
    String event,
    Future<void> Function(HouseholdApi api) online,
    bool Function() offline, {
    Map<String, Object?> fields = const {},
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
        lastError = error.message;
        AppLog.event('$event.failed', {...fields, 'kind': error.kind.name});
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
    if (existing != null) {
      if (existing.outcome == LogOutcome.uncertain &&
          outcome != LogOutcome.uncertain) {
        _logs.remove(existing);
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
    _careEvents.removeWhere((event) => event.id == eventId);
    _persistEvents();
    notifyListeners();
    AppLog.event('care_event.removed', {'eventId': eventId});
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
    final medication = medicationById(medicationId);
    if (medication == null) return Future.value(false);
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
  }) {
    lastError = null;
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
      },
    );
  }

  Future<bool> removeMedication(String medicationId) {
    return _write(
      'medication.remove',
      (api) async {
        await api.removeMedication(medicationId);
        _medications.removeWhere((item) => item.id == medicationId);
      },
      () {
        _medications.removeWhere((item) => item.id == medicationId);
        return true;
      },
      fields: {'medicationId': medicationId},
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
      notifyListeners();
      return false;
    }
    if (trimmed.length > PetLimits.maxNameLength) {
      lastError = 'Name is too long.';
      notifyListeners();
      return false;
    }

    final nextConditions = conditions ?? existing.conditions;
    if (nextConditions.length > PetLimits.maxConditions) {
      lastError = 'Too many conditions selected.';
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
        if (index >= 0) _pets[index] = saved;
      },
      () {
        final index = _pets.indexWhere((pet) => pet.id == petId);
        if (index >= 0) _pets[index] = updated;
        return true;
      },
      fields: {'petId': petId, 'conditions': updated.conditions.length},
    );

    if (ok) {
      if (primaryPet?.id == petId) {
        unawaited(OnboardingProfile.syncFromPet(updated));
      }
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
    await _write(
      'billing.plan',
      (api) async => _plan = await api.setPlan(value),
      () => true,
    );
  }

  Future<void> startTrial() async {
    await _write(
      'billing.trial',
      (api) async {
        final billing = await api.startTrial();
        _isPro = billing.isPro;
        _plan = billing.plan;
      },
      () {
        _isPro = true;
        return true;
      },
    );
    AppLog.event('billing.pro.unlocked', {
      'plan': _plan.name,
      'source': 'trial',
    });
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
      _storePro = true;
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
      lastError = 'Purchases are not set up on this build yet.';
      AppLog.event('billing.restore.skipped', {'reason': 'not_configured'});
      notifyListeners();
      return false;
    }
    final restored = await RevenueCatService.restorePurchases();
    if (!restored) {
      lastError = 'No active subscription found for this account.';
      AppLog.event('billing.restore.empty');
      notifyListeners();
      return false;
    }
    final status = await RevenueCatService.currentStatus();
    if (status.isPro) {
      _storePro = true;
      await startTrial();
      final storePlan = status.plan;
      if (storePlan != null && storePlan != _plan) {
        await setPlan(storePlan);
      }
      AppLog.event('billing.restore.completed', {'plan': _plan.name});
      return true;
    }
    lastError = 'No active subscription found for this account.';
    AppLog.event('billing.restore.inactive');
    notifyListeners();
    return false;
  }

  /// Counts and flags for RevenueCat Audiences — never names or emails.
  Map<String, String> get billingAttributes => {
    'pet_count': '${_pets.length}',
    'medication_count': '${_medications.length}',
    'household_members': '${_members.length}',
    'has_household': '$hasHousehold',
    'is_pro': '$isPro',
  };

  /// Pulls Pro status from RevenueCat on app start or resume.
  Future<void> syncBillingFromStore() async {
    if (!RevenueCatService.isReady) {
      AppLog.event('billing.sync.skipped', {'reason': 'not_configured'});
      return;
    }
    await RevenueCatService.identifyMember(billingUserId);
    unawaited(RevenueCatService.syncAttributes(billingAttributes));
    final status = await RevenueCatService.currentStatus();
    final storeChanged = _storePro != status.isPro;
    _storePro = status.isPro;
    if (status.isPro && !_isPro) {
      // Push the subscription to the household so partners get Pro too.
      await startTrial();
      if (status.plan != null && status.plan != _plan) {
        await setPlan(status.plan!);
      }
      AppLog.event('billing.sync.pro_unlocked', {'plan': _plan.name});
    } else if (!status.isPro && _isPro && !isConnected) {
      // Shared households get Pro from the server (purchase webhook or trial);
      // a partner without their own subscription must not switch it off.
      _isPro = false;
      _changed();
      AppLog.event('billing.sync.pro_revoked');
    } else {
      if (storeChanged) _changed();
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
    AppLog.event('household.created_from_onboarding', {
      'conditions': model.conditions.length,
      'caregivers': model.caregivers.length,
      'localOnly': _api != null && !isConnected,
    });
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
    await _store?.clear();
    _careEvents.clear();
    await _eventsStore.clear();
    _storePro = false;
    await RevenueCatService.logOut();
    await UpgradeNudgeState.clear();
    _lastSyncedAt = null;
    AppLog.event('household.reset');
    notifyListeners();
  }

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
