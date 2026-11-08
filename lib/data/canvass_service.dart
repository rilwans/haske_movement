import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'local_db.dart';
import 'models.dart';

/// Everything the canvasser or coordinator does goes to the device first and is sent to
/// erims whenever there's internet: when the connection comes back, when the
/// app is reopened, every few minutes, and right after each save.
class CanvassService extends ChangeNotifier with WidgetsBindingObserver {
  CanvassService._(this.db, this._client);

  final LocalDb db;
  final SupabaseClient _client;

  static const _syncEvery = Duration(minutes: 3);

  /// Visits per canvass_sync() call, so a slow connection finishes each one.
  static const _batchSize = 200;

  AppProfile? profile;

  /// Polling units whose voters are on this phone.
  Set<String> downloaded = {};
  DateTime? lastSyncedAt;
  int pending = 0;
  int failed = 0;
  bool syncing = false;

  /// Whether the last attempt to reach the server worked.
  bool online = true;
  String? lastError;

  /// Bumped on every local change, for lists to reload.
  int revision = 0;

  StreamSubscription<List<ConnectivityResult>>? _connectivity;
  Timer? _timer;
  Future<void>? _running;

  static Future<CanvassService> start(String userId) async {
    final service = CanvassService._(await LocalDb.open(userId), Supabase.instance.client);
    service.profile = await service.db.profile();
    service.downloaded = await service.db.downloadedPollingUnits();
    service.lastSyncedAt = await service.db.lastSyncedAt();
    await service._refreshCounts();
    WidgetsBinding.instance.addObserver(service);
    service._connectivity = Connectivity().onConnectivityChanged.listen((results) {
      if (!results.contains(ConnectivityResult.none)) service.sync();
    });
    service._timer = Timer.periodic(_syncEvery, (_) => service.sync());
    return service;
  }

  bool get onboarded => profile != null;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivity?.cancel();
    _timer?.cancel();
    super.dispose();
  }

  /// First sign-in on this device: who they are and, for a canvasser, their
  /// polling unit's voters. Coordinators download polling units as they
  /// choose them. Needs internet; throws a message to show otherwise.
  Future<void> onboard() async {
    await _ensureSession();
    final p = await _fetchProfile();
    await db.saveProfile(p);
    if (!p.isCoordinator) await _pullVoters(p.pollingUnits.first.id);
    profile = p;
    downloaded = await db.downloadedPollingUnits();
    lastSyncedAt = DateTime.now();
    await db.setLastSyncedAt(lastSyncedAt!);
    online = true;
    revision++;
    notifyListeners();
  }

  /// Fetches a polling unit's voters for canvassing it offline. Needs internet.
  Future<void> downloadPollingUnit(String id) async {
    await _ensureSession();
    await _pullVoters(id);
    downloaded = await db.downloadedPollingUnits();
    revision++;
    notifyListeners();
  }

  /// A canvasser a coordinator onboarded, sent with the next sync.
  Future<void> addCanvasser(NewCanvasser c) async {
    await db.addCanvasser(c);
    await _changed();
  }

  /// A ward coordinator an LGA or state coordinator added, sent with the next sync.
  Future<void> addWardCoordinator(NewWardCoordinator c) async {
    await db.addWardCoordinator(c);
    await _changed();
  }

  /// An LGA coordinator a state coordinator added, sent with the next sync.
  Future<void> addLgaCoordinator(NewLgaCoordinator c) async {
    await db.addLgaCoordinator(c);
    await _changed();
  }

  /// A state coordinator moves to [lga], or to the whole state when null.
  /// An LGA not opened before needs internet; throws otherwise.
  Future<void> chooseLga(Lga? lga) async {
    final units = lga == null ? const <PollingUnit>[] : await _lgaPollingUnits(lga.id);
    final p = profile!.forLga(lga, units);
    profile = p;
    await db.saveProfile(p);
    revision++;
    notifyListeners();
  }

  Future<void> addVoter(Voter v) async {
    await db.addVoter(v);
    await _changed();
  }

  Future<void> recordVisit(Visit v) async {
    await db.addVisit(v);
    await _changed();
  }

  Future<void> _changed() async {
    revision++;
    await _refreshCounts();
    notifyListeners();
    unawaited(sync());
  }

  /// Sends what's waiting, then fetches the latest voter list. Safe to call
  /// any time; a call during a sync waits for that one.
  Future<void> sync() => _running ??= _sync().whenComplete(() => _running = null);

  Future<void> _sync() async {
    if (!onboarded) return;
    syncing = true;
    notifyListeners();
    try {
      await _ensureSession();
      await _push();
      await _makeLogins();
      // They may have been moved, or their area changed.
      final p = await _latestProfile();
      final previous = profile;
      profile = p;
      await db.saveProfile(p);
      // A state coordinator's profile only lists the chosen LGA's polling
      // units; what they downloaded elsewhere is theirs while their state is.
      final gone = p.isStateCoordinator
          ? (previous?.stateName == p.stateName ? <String>{} : downloaded)
          : downloaded.difference(p.pollingUnits.map((u) => u.id).toSet());
      for (final id in gone) {
        await db.forgetPollingUnit(id);
      }
      // A canvasser always has their polling unit; a coordinator what they downloaded.
      final toPull = p.isCoordinator ? downloaded.difference(gone) : {p.pollingUnits.first.id};
      for (final id in toPull) {
        await _pullVoters(id);
      }
      lastSyncedAt = DateTime.now();
      await db.setLastSyncedAt(lastSyncedAt!);
      online = true;
      lastError = null;
    } catch (e) {
      online = !_isNetworkError(e);
      lastError = online ? describeError(e) : null;
    } finally {
      downloaded = await db.downloadedPollingUnits();
      syncing = false;
      revision++;
      await _refreshCounts();
      notifyListeners();
    }
  }

  Future<void> _push() async {
    final wardCoordinators = await db.pendingWardCoordinators();
    if (wardCoordinators.isNotEmpty) {
      final res = await _client.rpc('onboard_ward_coordinators', params: {
        'items': wardCoordinators.map((c) => c.toSyncJson()).toList(),
      });
      await db.markOnboardedSynced('ward_coordinators', _results(res));
    }
    final lgaCoordinators = await db.pendingLgaCoordinators();
    if (lgaCoordinators.isNotEmpty) {
      final res = await _client.rpc('onboard_lga_coordinators', params: {
        'items': lgaCoordinators.map((c) => c.toSyncJson()).toList(),
      });
      await db.markOnboardedSynced('lga_coordinators', _results(res));
    }
    final canvassers = await db.pendingCanvassers();
    final voters = await db.pendingVoters();
    final visits = await db.unsyncedVisits();
    // Canvassers and voters first, in the first call, so visits can follow.
    var first = true;
    for (var i = 0; first || i < visits.length; i += _batchSize) {
      final chunk = visits.skip(i).take(_batchSize).toList();
      final sendCanvassers = first ? canvassers : const <NewCanvasser>[];
      final sendVoters = first ? voters : const <Voter>[];
      first = false;
      if (sendCanvassers.isEmpty && sendVoters.isEmpty && chunk.isEmpty) return;
      final res = await _client.rpc('canvass_sync', params: {
        'payload': {
          if (sendCanvassers.isNotEmpty) 'canvassers': sendCanvassers.map((c) => c.toSyncJson()).toList(),
          'voters': sendVoters.map((v) => v.toSyncJson()).toList(),
          'visits': chunk.map((v) => v.toSyncJson()).toList(),
        },
      }) as Map<String, dynamic>;
      await db.markOnboardedSynced('canvassers', _results(res['canvassers']));
      await db.markVotersSynced(_results(res['voters']));
      await db.markVisitsSynced(_results(res['visits']));
    }
  }

  /// Logins for the canvassers and coordinators a coordinator onboarded:
  /// canvass_sync() or onboard_ward_coordinators() or
  /// onboard_lga_coordinators() makes the person, and erims's
  /// canvasser-logins function their login.
  Future<void> _makeLogins() async {
    if (profile?.isCoordinator != true) return;
    for (final team in ['canvassers', 'ward_coordinators', if (profile!.isStateCoordinator) 'lga_coordinators']) {
      final ids = await db.awaitingLogin(team);
      for (var i = 0; i < ids.length; i += 100) {
        final res = await _client.functions.invoke(
          'canvasser-logins',
          body: {'action': 'onboard', 'team': team, 'ids': ids.skip(i).take(100).toList()},
        );
        await db.markLogins(team, _results((res.data as Map<String, dynamic>)[team]));
      }
    }
  }

  /// The voter figures for the coordinator's area, or [wardId] or
  /// [pollingUnitId] in it, kept on the phone for when there's no internet.
  /// Needs internet; throws a message to show otherwise.
  Future<VoterStats> fetchStats({String? wardId, String? pollingUnitId}) async {
    await _ensureSession();
    final lgaId = profile?.selectedLgaId;
    final json = await _client.rpc('app_voter_stats', params: {
      'p_ward_id': wardId,
      'p_polling_unit_id': pollingUnitId,
      ..._lgaParam,
    }) as Map<String, dynamic>;
    json['fetched_at'] = DateTime.now().toUtc().toIso8601String();
    await db.saveStats(wardId, pollingUnitId, json, lgaId: lgaId);
    return VoterStats.fromJson(json);
  }

  /// The coordinator's team, or one ward's, with what each did since
  /// [since] (ever, when null). Needs internet; throws a message otherwise.
  Future<TeamActivity> fetchTeamActivity({String? wardId, DateTime? since}) async {
    await _ensureSession();
    final lgaId = profile?.selectedLgaId;
    final json = await _client.rpc('app_team_activity', params: {
      'p_ward_id': wardId,
      'p_since': since?.toUtc().toIso8601String(),
      ..._lgaParam,
    }) as Map<String, dynamic>;
    json['fetched_at'] = DateTime.now().toUtc().toIso8601String();
    await db.saveCached(teamActivityKey(wardId, since, lgaId), json);
    return TeamActivity.fromJson(json);
  }

  /// Where [fetchTeamActivity] keeps its answer; periods are kept by day.
  static String teamActivityKey(String? wardId, DateTime? since, String? lgaId) =>
      'team:${lgaId == null ? '' : '$lgaId:'}${wardId ?? ''}:${since == null ? '' : '${since.year}-${since.month}-${since.day}'}';

  /// Someone on the coordinator's team's latest visits. Needs internet.
  Future<List<TeamVisit>> fetchPersonVisits(TeamMember m) async {
    await _ensureSession();
    final rows = await _client.rpc('app_person_visits', params: {'p_kind': m.kind, 'p_id': m.id}) as List;
    return [for (final r in rows) TeamVisit.fromJson(r as Map<String, dynamic>)];
  }

  /// The wards in the coordinator's area and their targets. Needs internet.
  Future<WardTargets> fetchTargets() async {
    await _ensureSession();
    final lgaId = profile?.selectedLgaId;
    final json = await _client.rpc('app_ward_targets', params: _lgaParam) as Map<String, dynamic>;
    json['fetched_at'] = DateTime.now().toUtc().toIso8601String();
    await db.saveCached(targetsKey(lgaId), json);
    return WardTargets.fromJson(json);
  }

  /// Where [fetchTargets] keeps its answer.
  static String targetsKey(String? lgaId) => lgaId == null ? 'targets' : 'targets:$lgaId';

  /// An LGA or state coordinator sets a ward's target from today, or with no
  /// [percent] removes it. Needs internet.
  Future<void> setWardTarget(String wardId, {int? percent, DateTime? dueOn}) async {
    await _ensureSession();
    await _client.rpc('set_ward_target', params: {
      'p_ward_id': wardId,
      'p_percent': percent,
      'p_due_on': dueOn == null
          ? null
          : '${dueOn.year}-${dueOn.month.toString().padLeft(2, '0')}-${dueOn.day.toString().padLeft(2, '0')}',
    });
  }

  static List<Map<String, dynamic>> _results(Object? list) =>
      ((list as List?) ?? const []).cast<Map<String, dynamic>>();

  /// A state coordinator's chosen LGA for the server; erims knows anyone
  /// else's area, and older deployments don't take the argument.
  Map<String, dynamic> get _lgaParam =>
      profile?.isStateCoordinator == true ? {'p_lga_id': profile!.selectedLgaId} : const {};

  /// An LGA's polling units, from the server or, offline, as last fetched.
  Future<List<PollingUnit>> _lgaPollingUnits(String lgaId) async {
    List<PollingUnit> parse(List rows) => [for (final r in rows) PollingUnit.fromJson(r as Map<String, dynamic>)];
    final key = 'lga_units:$lgaId';
    try {
      await _ensureSession();
      final rows = await _client.rpc('app_lga_polling_units', params: {'p_lga_id': lgaId}) as List;
      await db.saveCached(key, {'units': rows});
      return parse(rows);
    } catch (e) {
      final cached = await db.cached(key);
      if (cached == null || !_isNetworkError(e)) rethrow;
      return parse(cached['units'] as List);
    }
  }

  /// The profile from the server, keeping a state coordinator on their LGA.
  Future<AppProfile> _latestProfile() async {
    final fresh = await _fetchProfile();
    if (!fresh.isStateCoordinator) return fresh;
    final chosen = fresh.lga(profile?.selectedLgaId);
    final kept = chosen == null ? fresh : fresh.forLga(chosen, await _lgaPollingUnits(chosen.id));
    // They may have moved to another LGA while that loaded.
    final now = profile!;
    return now.selectedLgaId == kept.selectedLgaId ? kept : kept.forLga(fresh.lga(now.selectedLgaId), now.pollingUnits);
  }

  Future<AppProfile> _fetchProfile() async {
    final json = await _client.rpc('my_app_profile');
    if (json == null) {
      throw const CanvassException(
        "Your login isn't linked to a canvasser or coordinator. Ask your coordinator.",
      );
    }
    return AppProfile.fromJson(json as Map<String, dynamic>);
  }

  Future<void> _pullVoters(String pollingUnitId) async {
    final rows = await _client.rpc('canvass_voters', params: {'p_polling_unit_id': pollingUnitId}) as List;
    await db.replaceVoters(pollingUnitId, rows.cast<Map<String, dynamic>>());
  }

  /// The access token lasts an hour; after a day offline it needs refreshing.
  Future<void> _ensureSession() async {
    final session = _client.auth.currentSession;
    if (session == null) throw const CanvassException('Sign in again to sync.');
    if (session.isExpired) await _client.auth.refreshSession();
  }

  Future<void> _refreshCounts() async {
    pending = await db.pendingCount();
    failed = await db.failedCount();
  }

  /// Signs out and removes this login's data from the device. Refused while
  /// anything is unsent, so no canvassing is lost.
  Future<void> signOut() async {
    await _refreshCounts();
    if (pending > 0) {
      throw CanvassException(
        '$pending ${pending == 1 ? 'record hasn\'t' : 'records haven\'t'} been sent yet. '
        'Connect to the internet and sync before signing out.',
      );
    }
    _timer?.cancel();
    await _connectivity?.cancel();
    await _running;
    await db.destroy();
    try {
      await _client.auth.signOut();
    } catch (_) {
      // Offline: forget the session on this device anyway.
      await _client.auth.signOut(scope: SignOutScope.local);
    }
  }

  static bool _isNetworkError(Object e) =>
      e is SocketException ||
      e is TimeoutException ||
      e is HandshakeException ||
      e is AuthRetryableFetchException ||
      e.toString().contains('ClientException');

  static String describeError(Object e) => switch (e) {
        CanvassException(:final message) => message,
        _ when _isNetworkError(e) => "Can't reach the server. Check your internet connection.",
        PostgrestException(:final message) => message,
        AuthException(:final message) => message,
        _ => 'Something went wrong: $e',
      };
}

class CanvassException implements Exception {
  const CanvassException(this.message);
  final String message;

  @override
  String toString() => message;
}
