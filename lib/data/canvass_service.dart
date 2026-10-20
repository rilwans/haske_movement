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

  /// A ward coordinator an LGA coordinator added, sent with the next sync.
  Future<void> addWardCoordinator(NewWardCoordinator c) async {
    await db.addWardCoordinator(c);
    await _changed();
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
      final p = await _fetchProfile();
      await db.saveProfile(p);
      profile = p;
      final inScope = p.pollingUnits.map((u) => u.id).toSet();
      for (final id in downloaded.difference(inScope)) {
        await db.forgetPollingUnit(id);
      }
      // A canvasser always has their polling unit; a coordinator what they downloaded.
      final toPull = p.isCoordinator ? downloaded.intersection(inScope) : {p.pollingUnits.first.id};
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

  /// Logins for the canvassers and ward coordinators a coordinator onboarded:
  /// canvass_sync() or onboard_ward_coordinators() makes the person, and
  /// erims's canvasser-logins function their login.
  Future<void> _makeLogins() async {
    if (profile?.isCoordinator != true) return;
    for (final team in ['canvassers', 'ward_coordinators']) {
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
    final json = await _client.rpc('app_voter_stats', params: {
      'p_ward_id': wardId,
      'p_polling_unit_id': pollingUnitId,
    }) as Map<String, dynamic>;
    json['fetched_at'] = DateTime.now().toUtc().toIso8601String();
    await db.saveStats(wardId, pollingUnitId, json);
    return VoterStats.fromJson(json);
  }

  static List<Map<String, dynamic>> _results(Object? list) =>
      ((list as List?) ?? const []).cast<Map<String, dynamic>>();

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
