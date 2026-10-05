part of 'care_repository.dart';

/// Owner-only household management: the invite code, browser sitter links,
/// and members' roles. All online-only (they change who can reach the
/// household, so they must never be queued and replayed later).
///
/// Every call: dedupes repeat taps (same future), refuses non-owners before
/// any request, and never changes the phone on a timeout — the server may or
/// may not have acted, so the next sync shows the truth.
extension CareHousehold on CareRepository {
  /// Working sitter links (owner), newest first. Empty until [loadSitterLinks].
  List<SitterLinkInfo> get sitterLinks => UnmodifiableListView(_sitterLinks);

  static const _unconfirmed =
      "Couldn’t confirm that — your connection is slow. Check again in a moment.";

  /// Runs an owner-only call; returns a message for the person, or null.
  Future<String?> _ownerCall(
    String event,
    Future<void> Function(HouseholdApi api) run, {
    Map<String, Object?> fields = const {},
  }) async {
    if (!isOwner) {
      AppLog.event('$event.blocked', {'reason': 'role', 'role': myRole.name});
      return CareRepository.ownerOnlyMessage;
    }
    final api = _api;
    if (api == null || !isConnected) {
      AppLog.event('$event.skipped', {'reason': 'not_connected'});
      return 'Share your household first.';
    }
    try {
      await AppLog.trace(event, () => run(api));
      AppLog.event('$event.completed', fields);
      return null;
    } on HouseholdException catch (error) {
      AppLog.event('$event.failed', {
        ...fields,
        'kind': error.kind.name,
        if (error.timedOut) 'timedOut': true,
        if (error.code != null) 'code': error.code,
      });
      if (error.kind == HouseholdErrorKind.offline) {
        return error.timedOut ? _unconfirmed : error.message;
      }
      if (error.kind == HouseholdErrorKind.unauthorized) {
        await _dropSession('${event}_unauthorized', error);
      } else if (error.isRoleForbidden) {
        _onRoleForbidden(event, error);
      }
      return error.message;
    }
  }

  /// Owner: a new invite code (the old one stops working at once). Returns
  /// a message when it could not; the code on screen is unchanged then.
  Future<String?> rotateInvite() =>
      _rotating ??= _ownerCall('invite.rotate', (api) async {
        final rotated = await api.rotateInvite();
        _inviteCode = rotated.inviteCode;
        _inviteExpiresAt = rotated.expiresAt;
        _changed();
      }).whenComplete(() => _rotating = null);

  /// Owner: refreshes [sitterLinks] from the server. Drops this phone’s
  /// cached link when it no longer appears (revoked elsewhere or expired).
  Future<String?> loadSitterLinks() =>
      _sitterLinksRunning ??= _ownerCall('sitter.links_load', (api) async {
        final links = await api.listSitterLinks();
        _sitterLinks
          ..clear()
          ..addAll(links);
        final cached = _sitterLink;
        if (cached != null &&
            cached.id.isNotEmpty &&
            !links.any((link) => link.id == cached.id)) {
          await _forgetCachedSitterLink('gone_on_server');
        }
        _notify();
      }).whenComplete(() => _sitterLinksRunning = null);

  /// Owner: revokes a sitter link; its token stops working at once. Already
  /// revoked (another phone, a double tap) also counts as done.
  Future<String?> revokeSitterLink(String linkId) => _sitterRevokes[linkId] ??=
      _ownerCall('sitter.link_revoke', (api) async {
        await api.revokeSitterLink(linkId);
        _sitterLinks.removeWhere((link) => link.id == linkId);
        if (_sitterLink?.id == linkId) {
          await _forgetCachedSitterLink('revoked');
        }
        _notify();
      }, fields: {'linkId': linkId}).whenComplete(() {
        _sitterRevokes.remove(linkId);
      });

  Future<void> _forgetCachedSitterLink(String reason) async {
    _sitterLink = null;
    try {
      await SecureTokens.delete(_sitterCacheKey);
    } on Object catch (error, stack) {
      AppLog.error('sitter.token_clear_failed', error, stack);
    }
    AppLog.event('sitter.link_forgotten', {'reason': reason});
  }

  /// Owner: makes [memberId] a caregiver or sitter.
  Future<String?> changeMemberRole(String memberId, MemberRole role) {
    if (role == MemberRole.owner) {
      return Future.value("There’s always exactly one owner.");
    }
    return _memberActions[memberId] ??=
        _ownerCall('member.role_change', (api) async {
          try {
            final updated = await api.setMemberRole(memberId, role);
            final index = _members.indexWhere((m) => m.id == memberId);
            if (index >= 0) _members[index] = updated;
            _changed();
          } on HouseholdException catch (error) {
            if (error.code == 'member_gone') _dropMemberLocally(memberId);
            rethrow;
          }
        }, fields: {'memberId': memberId, 'role': role.name}).whenComplete(() {
          _memberActions.remove(memberId);
        });
  }

  /// Owner: removes [memberId] from the household. Their past doses stay
  /// and read as "Former member". Already gone counts as done.
  Future<String?> removeMember(String memberId) {
    return _memberActions[memberId] ??=
        _ownerCall('member.remove', (api) async {
          try {
            await api.removeMember(memberId);
          } on HouseholdException catch (error) {
            if (error.code != 'member_gone') rethrow;
          }
          _dropMemberLocally(memberId);
        }, fields: {'memberId': memberId}).whenComplete(() {
          _memberActions.remove(memberId);
        });
  }

  void _dropMemberLocally(String memberId) {
    _members.removeWhere((m) => m.id == memberId && !m.isYou);
    _changed();
  }
}
