import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'models.dart';

/// The signed-in person's data on the device: the voters of the polling
/// units they've downloaded, the voters they added, the visits they recorded
/// and (coordinators) the canvassers they onboarded, so all of it works with
/// no internet. Each login gets its own file, deleted when they sign out.
class LocalDb {
  LocalDb._(this._db, this._path);

  final Database _db;
  final String _path;

  static Future<LocalDb> open(String userId) async {
    final path = p.join(await getDatabasesPath(), 'canvass_$userId.db');
    final db = await openDatabase(
      path,
      version: 2,
      onCreate: (db, _) async {
        await db.execute('create table meta (key text primary key, value text not null)');
        await db.execute('''
          create table voters (
            id text primary key,
            name text not null,
            polling_unit_id text,
            vin text,
            phone text,
            whatsapp_number text,
            email text,
            added_locally integer not null default 0,
            pending integer not null default 0,
            sync_error text
          )''');
        await db.execute('''
          create table visits (
            id text primary key,
            voter_id text not null,
            visited_at text not null,
            support text,
            pvc_status text,
            plans_to_vote text,
            issues text not null,
            notes text,
            reported_phone text,
            reported_whatsapp text,
            reported_vin text,
            latitude real,
            longitude real,
            synced integer not null default 0,
            sync_error text
          )''');
        await db.execute('create index visits_voter_id on visits (voter_id)');
        await db.execute('create index visits_synced on visits (synced)');
        await _createV2(db);
      },
      onUpgrade: (db, from, _) async {
        if (from < 2) {
          await db.execute('alter table voters add column polling_unit_id text');
          // Who's signed in is now a profile, fetched again at onboarding.
          await db.delete('meta', where: 'key = ?', whereArgs: ['canvasser']);
          await _createV2(db);
        }
      },
    );
    return LocalDb._(db, path);
  }

  /// Version 2: polling units per voter, and the canvassers coordinators onboard.
  static Future<void> _createV2(Database db) async {
    await db.execute('create index voters_polling_unit_id on voters (polling_unit_id)');
    // Polling units whose voters are on the device.
    await db.execute('create table downloaded_polling_units (id text primary key, downloaded_at text not null)');
    await db.execute('''
      create table canvassers (
        id text primary key,
        first_name text not null,
        last_name text not null,
        phone text not null,
        whatsapp_number text,
        email text,
        polling_unit_id text not null,
        created_at text not null,
        pending integer not null default 1,
        sync_error text,
        login text
      )''');
  }

  /// Closes and deletes this login's data, at sign-out.
  Future<void> destroy() async {
    await _db.close();
    await deleteDatabase(_path);
  }

  // --- Who's signed in, and sync state ------------------------------------

  Future<String?> _meta(String key) async {
    final rows = await _db.query('meta', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> _setMeta(String key, String value) => _db.insert(
        'meta',
        {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<AppProfile?> profile() async {
    final json = await _meta('profile');
    return json == null ? null : AppProfile.fromJson(jsonDecode(json));
  }

  Future<void> saveProfile(AppProfile p) => _setMeta('profile', jsonEncode(p.toJson()));

  Future<DateTime?> lastSyncedAt() async {
    final v = await _meta('last_synced_at');
    return v == null ? null : DateTime.parse(v);
  }

  Future<void> setLastSyncedAt(DateTime at) => _setMeta('last_synced_at', at.toUtc().toIso8601String());

  // --- Voters -------------------------------------------------------------

  /// Voters at [pollingUnitId] matching [search] (name, phone or VIN), with
  /// how often they've been visited from this device.
  Future<List<Voter>> voters(String pollingUnitId, {String search = '', bool? visited}) async {
    final where = <String>['v.polling_unit_id = ?'];
    final args = <Object?>[pollingUnitId];
    final q = search.trim();
    if (q.isNotEmpty) {
      final like = '%${q.replaceAll(RegExp(r'[%_]'), '')}%';
      // Phones are stored +234..., so 0803... searches by what follows the 0.
      final digits = q.replaceAll(RegExp(r'\D'), '');
      final phoneLike = digits.length >= 4 ? '%${digits.replaceFirst(RegExp(r'^0'), '')}%' : like;
      where.add('(v.name like ? or v.vin like ? or v.phone like ? or v.whatsapp_number like ?)');
      args.addAll([like, like.toUpperCase(), phoneLike, phoneLike]);
    }
    if (visited != null) {
      where.add(visited ? 'visit_count > 0' : 'visit_count = 0');
    }
    final rows = await _db.rawQuery('''
      select * from (
        select v.*, (select count(*) from visits s where s.voter_id = v.id) as visit_count
        from voters v
      ) v
      where ${where.join(' and ')}
      order by v.name collate nocase
    ''', args);
    return rows.map(Voter.fromRow).toList();
  }

  Future<Voter?> voter(String id) async {
    final rows = await _db.rawQuery('''
      select v.*, (select count(*) from visits s where s.voter_id = v.id) as visit_count
      from voters v where v.id = ?
    ''', [id]);
    return rows.isEmpty ? null : Voter.fromRow(rows.first);
  }

  /// A voter met who isn't on the list.
  Future<void> addVoter(Voter v) => _db.insert('voters', {
        'id': v.id,
        'name': v.name,
        'polling_unit_id': v.pollingUnitId,
        'vin': v.vin,
        'phone': v.phone,
        'whatsapp_number': v.whatsappNumber,
        'email': v.email,
        'added_locally': 1,
        'pending': 1,
      });

  /// Swaps in a polling unit's voters from the server, keeping the ones
  /// added here that haven't been sent yet.
  Future<void> replaceVoters(String pollingUnitId, List<Map<String, dynamic>> rows) => _db.transaction((tx) async {
        // Voters stored before polling units were kept belong to the first download.
        await tx.delete(
          'voters',
          where: 'pending = 0 and (polling_unit_id = ? or polling_unit_id is null)',
          whereArgs: [pollingUnitId],
        );
        await tx.update('voters', {'polling_unit_id': pollingUnitId}, where: 'polling_unit_id is null');
        final batch = tx.batch();
        for (final r in rows) {
          batch.insert(
            'voters',
            {
              'id': r['id'],
              'name': r['name'],
              'polling_unit_id': pollingUnitId,
              'vin': r['vin'],
              'phone': r['phone'],
              'whatsapp_number': r['whatsapp_number'],
              'email': r['email'],
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
        await batch.commit(noResult: true);
        await tx.insert(
          'downloaded_polling_units',
          {'id': pollingUnitId, 'downloaded_at': DateTime.now().toUtc().toIso8601String()},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      });

  /// Polling units whose voters are on this phone.
  Future<Set<String>> downloadedPollingUnits() async =>
      (await _db.query('downloaded_polling_units')).map((r) => r['id'] as String).toSet();

  /// Drops a polling unit that's no longer the person's, keeping anything unsent.
  Future<void> forgetPollingUnit(String id) => _db.transaction((tx) async {
        await tx.delete('voters', where: 'pending = 0 and polling_unit_id = ?', whereArgs: [id]);
        await tx.delete('downloaded_polling_units', where: 'id = ?', whereArgs: [id]);
      });

  // --- Visits -------------------------------------------------------------

  Future<void> addVisit(Visit v) => _db.insert('visits', v.toRow());

  Future<List<Visit>> visitsFor(String voterId) async {
    final rows = await _db.query('visits', where: 'voter_id = ?', whereArgs: [voterId], orderBy: 'visited_at desc');
    return rows.map(Visit.fromRow).toList();
  }

  /// Visits recorded since [since], at [pollingUnitId] or anywhere.
  Future<int> visitCountSince(DateTime since, {String? pollingUnitId}) async {
    final r = await _db.rawQuery(
      'select count(*) as n from visits s '
      '${pollingUnitId == null ? '' : 'join voters v on v.id = s.voter_id and v.polling_unit_id = ? '}'
      'where s.visited_at >= ?',
      [?pollingUnitId, since.toUtc().toIso8601String()],
    );
    return r.first['n'] as int;
  }

  // --- Canvassers a coordinator onboarded ---------------------------------

  Future<void> addCanvasser(NewCanvasser c) => _db.insert('canvassers', c.toRow());

  Future<List<NewCanvasser>> canvassers() async =>
      (await _db.query('canvassers', orderBy: 'created_at desc')).map(NewCanvasser.fromRow).toList();

  Future<List<NewCanvasser>> pendingCanvassers() async =>
      (await _db.query('canvassers', where: 'pending = 1', orderBy: 'created_at')).map(NewCanvasser.fromRow).toList();

  /// Whether this phone already onboarded someone with [phone].
  Future<bool> hasCanvasserPhone(String phone) async =>
      (await _db.query('canvassers', where: 'phone = ?', whereArgs: [phone])).isNotEmpty;

  // --- What's waiting to sync ---------------------------------------------

  Future<List<Voter>> pendingVoters() async =>
      (await _db.query('voters', where: 'pending = 1')).map(Voter.fromRow).toList();

  Future<List<Visit>> unsyncedVisits() async =>
      (await _db.query('visits', where: 'synced = 0', orderBy: 'visited_at')).map(Visit.fromRow).toList();

  Future<int> pendingCount() async {
    final r = await _db.rawQuery('''
      select (select count(*) from voters where pending = 1)
           + (select count(*) from visits where synced = 0)
           + (select count(*) from canvassers where pending = 1) as n
    ''');
    return r.first['n'] as int;
  }

  Future<int> failedCount() async {
    final r = await _db.rawQuery('''
      select (select count(*) from voters where pending = 1 and sync_error is not null)
           + (select count(*) from visits where synced = 0 and sync_error is not null)
           + (select count(*) from canvassers where sync_error is not null) as n
    ''');
    return r.first['n'] as int;
  }

  /// Applies canvass_sync()'s answer for the canvassers it was sent.
  Future<void> markCanvassersSynced(List<Map<String, dynamic>> results) => _db.transaction((tx) async {
        for (final r in results) {
          final ok = r['status'] == 'ok';
          await tx.update(
            'canvassers',
            ok ? {'pending': 0, 'sync_error': null, 'login': r['login'] ?? 'pending'} : {'sync_error': r['error'] ?? 'Not accepted'},
            where: 'id = ?',
            whereArgs: [r['id']],
          );
        }
      });

  /// Sent canvassers whose login hasn't been made yet.
  Future<List<String>> canvassersAwaitingLogin() async =>
      (await _db.query('canvassers', columns: ['id'], where: "pending = 0 and coalesce(login, '') <> 'made'"))
          .map((r) => r['id'] as String)
          .toList();

  /// Applies the canvasser-logins function's answer: a login made, or why not.
  Future<void> markLogins(List<Map<String, dynamic>> results) => _db.transaction((tx) async {
        for (final r in results) {
          await tx.update(
            'canvassers',
            {'login': r['login'] ?? 'pending', 'sync_error': r['error']},
            where: 'id = ?',
            whereArgs: [r['id']],
          );
        }
      });

  /// Applies canvass_sync()'s answer for the voters it was sent.
  Future<void> markVotersSynced(List<Map<String, dynamic>> results) => _db.transaction((tx) async {
        for (final r in results) {
          final id = r['id'] as String;
          switch (r['status']) {
            case 'ok':
              await tx.update('voters', {'pending': 0, 'sync_error': null}, where: 'id = ?', whereArgs: [id]);
            case 'merged':
              // The server already had this voter: their visits go to that one,
              // which comes down with the next voter list.
              final into = r['voter_id'] as String;
              await tx.update('visits', {'voter_id': into}, where: 'voter_id = ?', whereArgs: [id]);
              await tx.delete('voters', where: 'id = ?', whereArgs: [id]);
            default:
              await tx.update('voters', {'sync_error': r['error'] ?? 'Not accepted'}, where: 'id = ?', whereArgs: [id]);
          }
        }
      });

  /// Applies canvass_sync()'s answer for the visits it was sent.
  Future<void> markVisitsSynced(List<Map<String, dynamic>> results) => _db.transaction((tx) async {
        for (final r in results) {
          final ok = r['status'] == 'ok' || r['status'] == 'duplicate';
          await tx.update(
            'visits',
            ok ? {'synced': 1, 'sync_error': null} : {'sync_error': r['error'] ?? 'Not accepted'},
            where: 'id = ?',
            whereArgs: [r['id']],
          );
        }
      });
}
