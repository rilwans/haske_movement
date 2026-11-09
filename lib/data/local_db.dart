import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'models.dart';

/// The signed-in person's data on the device: the voters of the polling
/// units they've downloaded, the voters they added, the visits they recorded
/// and (coordinators) the canvassers and coordinators they onboarded,
/// so all of it works with no internet. Each login gets its own file, deleted when they sign out.
class LocalDb {
  LocalDb._(this._db, this._path);

  final Database _db;
  final String _path;

  static Future<LocalDb> open(String userId) async {
    final path = p.join(await getDatabasesPath(), 'canvass_$userId.db');
    final db = await openDatabase(
      path,
      version: 7,
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
        await _createV3(db);
        await _createV4(db);
        await _createV5(db);
        await _createV6(db);
        await _createV7(db);
      },
      onUpgrade: (db, from, _) async {
        if (from < 2) {
          await db.execute('alter table voters add column polling_unit_id text');
          // Who's signed in is now a profile, fetched again at onboarding.
          await db.delete('meta', where: 'key = ?', whereArgs: ['canvasser']);
          await _createV2(db);
        }
        if (from < 3) await _createV3(db);
        if (from < 4) await _createV4(db);
        if (from < 5) await _createV5(db);
        if (from < 6) await _createV6(db);
        if (from < 7) await _createV7(db);
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

  /// Version 3: voters' gender and year of birth, and what a visit was told of them.
  static Future<void> _createV3(Database db) async {
    await db.execute('alter table voters add column gender text');
    await db.execute('alter table voters add column birth_year integer');
    await db.execute('alter table visits add column reported_gender text');
    await db.execute('alter table visits add column reported_birth_year integer');
  }

  /// Version 4: the ward coordinators LGA coordinators add.
  static Future<void> _createV4(Database db) async {
    await db.execute('''
      create table ward_coordinators (
        id text primary key,
        first_name text not null,
        last_name text not null,
        phone text not null,
        whatsapp_number text,
        email text,
        ward_id text not null,
        ward_name text not null,
        created_at text not null,
        pending integer not null default 1,
        sync_error text,
        login text
      )''');
  }

  /// Version 5: each voter's latest visit by anyone, from the server, for
  /// the lists of who to visit next.
  static Future<void> _createV5(Database db) async {
    await db.execute('alter table voters add column last_visited_at text');
    await db.execute('alter table voters add column last_support text');
    await db.execute('alter table voters add column last_pvc_status text');
    await db.execute('alter table voters add column last_plans_to_vote text');
  }

  /// Version 6: the LGA coordinators state coordinators add, and where a
  /// canvasser was onboarded, since a state coordinator's polling units
  /// change with the LGA they've chosen.
  static Future<void> _createV6(Database db) async {
    await db.execute('''
      create table lga_coordinators (
        id text primary key,
        first_name text not null,
        last_name text not null,
        phone text not null,
        whatsapp_number text,
        email text,
        lga_id text not null,
        lga_name text not null,
        created_at text not null,
        pending integer not null default 1,
        sync_error text,
        login text
      )''');
    await db.execute('alter table canvassers add column polling_unit_name text');
  }

  /// Version 7: announcements, kept for reading offline. read_sent is 0 while
  /// the server hasn't been told this one was opened.
  static Future<void> _createV7(Database db) async {
    await db.execute('''
      create table announcements (
        id text primary key,
        body text not null,
        author_name text not null,
        author_role text not null,
        area_name text not null,
        created_at text not null,
        mine integer not null default 0,
        audience integer,
        read_count integer,
        read integer not null default 0,
        read_sent integer not null default 1
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

  // --- Voter figures, kept for showing offline ----------------------------

  static String _statsKey(String? lgaId, String? wardId, String? pollingUnitId) =>
      'stats:${lgaId == null ? '' : '$lgaId:'}${wardId ?? ''}:${pollingUnitId ?? ''}';

  /// The figures last fetched for an area, with when. [lgaId] is a state
  /// coordinator's chosen LGA.
  Future<VoterStats?> stats(String? wardId, String? pollingUnitId, {String? lgaId}) async {
    final json = await _meta(_statsKey(lgaId, wardId, pollingUnitId));
    return json == null ? null : VoterStats.fromJson(jsonDecode(json));
  }

  Future<void> saveStats(String? wardId, String? pollingUnitId, Map<String, dynamic> json, {String? lgaId}) =>
      _setMeta(_statsKey(lgaId, wardId, pollingUnitId), jsonEncode(json));

  /// Something else fetched from the server, kept under [key] for offline.
  Future<Map<String, dynamic>?> cached(String key) async {
    final json = await _meta('cache:$key');
    return json == null ? null : jsonDecode(json) as Map<String, dynamic>;
  }

  Future<void> saveCached(String key, Map<String, dynamic> json) => _setMeta('cache:$key', jsonEncode(json));

  // --- Voters -------------------------------------------------------------

  /// Voters with how often they've been visited from this device, and their
  /// latest visit by anyone: the server's, or one recorded here since.
  static const _votersWithLatest = '''
    select v.*,
      (select count(*) from visits s where s.voter_id = v.id) as visit_count,
      case when l.visited_at > coalesce(v.last_visited_at, '') then l.visited_at else v.last_visited_at end
        as latest_visited_at,
      case when l.visited_at > coalesce(v.last_visited_at, '') then l.support else v.last_support end
        as latest_support,
      case when l.visited_at > coalesce(v.last_visited_at, '') then l.pvc_status else v.last_pvc_status end
        as latest_pvc_status,
      case when l.visited_at > coalesce(v.last_visited_at, '') then l.plans_to_vote else v.last_plans_to_vote end
        as latest_plans_to_vote
    from voters v
    left join visits l on l.id = (
      select s.id from visits s where s.voter_id = v.id order by s.visited_at desc, s.id desc limit 1
    )
  ''';

  static const _supporters = "('strong_support', 'leaning_support')";

  /// Who's in each [Lead], over [_votersWithLatest], as erims's lead lists.
  static const _leadWhere = {
    Lead.all: '1 = 1',
    Lead.notReached: 'v.latest_visited_at is null',
    Lead.persuadable: "v.latest_support in ('undecided', 'leaning_against')",
    Lead.turnout: "v.latest_support in $_supporters and v.latest_pvc_status = 'has_pvc'",
    Lead.pvc: "v.latest_support in $_supporters and v.latest_pvc_status in ('registered_no_pvc', 'not_registered')",
    Lead.wavering: "v.latest_support in $_supporters and v.latest_plans_to_vote in ('unsure', 'no')",
    Lead.visited: 'v.latest_visited_at is not null',
  };

  /// Voters at [pollingUnitId] in [lead] matching [search] (name, phone or VIN).
  Future<List<Voter>> voters(String pollingUnitId, {String search = '', Lead lead = Lead.all}) async {
    final where = <String>['v.polling_unit_id = ?', _leadWhere[lead]!];
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
    final rows = await _db.rawQuery('''
      select * from ($_votersWithLatest) v
      where ${where.join(' and ')}
      order by v.name collate nocase
    ''', args);
    return rows.map(Voter.fromRow).toList();
  }

  /// How many voters at [pollingUnitId] are in each [Lead].
  Future<Map<Lead, int>> leadCounts(String pollingUnitId) async {
    final sums = [for (final l in Lead.values) 'sum(case when ${_leadWhere[l]} then 1 else 0 end) as lead_${l.name}'];
    final rows = await _db.rawQuery(
      'select ${sums.join(', ')} from ($_votersWithLatest) v where v.polling_unit_id = ?',
      [pollingUnitId],
    );
    return {for (final l in Lead.values) l: (rows.first['lead_${l.name}'] as int?) ?? 0};
  }

  Future<Voter?> voter(String id) async {
    final rows = await _db.rawQuery('select * from ($_votersWithLatest) v where v.id = ?', [id]);
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
        'gender': v.gender,
        'birth_year': v.birthYear,
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
              'gender': r['gender'],
              'birth_year': r['birth_year'],
              // As the phone stores its own visits' times, so the two compare.
              'last_visited_at': r['last_visited_at'] == null
                  ? null
                  : DateTime.parse(r['last_visited_at'] as String).toUtc().toIso8601String(),
              'last_support': r['last_support'],
              'last_pvc_status': r['last_pvc_status'],
              'last_plans_to_vote': r['last_plans_to_vote'],
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

  /// Whether this phone already onboarded someone, of either kind, with [phone].
  Future<bool> hasOnboardedPhone(String phone) async =>
      (await _db.query('canvassers', where: 'phone = ?', whereArgs: [phone])).isNotEmpty ||
      (await _db.query('ward_coordinators', where: 'phone = ?', whereArgs: [phone])).isNotEmpty ||
      (await _db.query('lga_coordinators', where: 'phone = ?', whereArgs: [phone])).isNotEmpty;

  // --- LGA coordinators a state coordinator added -------------------------

  Future<void> addLgaCoordinator(NewLgaCoordinator c) => _db.insert('lga_coordinators', c.toRow());

  Future<List<NewLgaCoordinator>> lgaCoordinators() async =>
      (await _db.query('lga_coordinators', orderBy: 'created_at desc')).map(NewLgaCoordinator.fromRow).toList();

  Future<List<NewLgaCoordinator>> pendingLgaCoordinators() async =>
      (await _db.query('lga_coordinators', where: 'pending = 1', orderBy: 'created_at'))
          .map(NewLgaCoordinator.fromRow)
          .toList();

  // --- Ward coordinators an LGA or state coordinator added ----------------

  Future<void> addWardCoordinator(NewWardCoordinator c) => _db.insert('ward_coordinators', c.toRow());

  Future<List<NewWardCoordinator>> wardCoordinators() async =>
      (await _db.query('ward_coordinators', orderBy: 'created_at desc')).map(NewWardCoordinator.fromRow).toList();

  Future<List<NewWardCoordinator>> pendingWardCoordinators() async =>
      (await _db.query('ward_coordinators', where: 'pending = 1', orderBy: 'created_at'))
          .map(NewWardCoordinator.fromRow)
          .toList();

  // --- Announcements ------------------------------------------------------

  static Map<String, Object?> _announcementRow(Map<String, dynamic> r, {bool read = false, bool readSent = true}) => {
        'id': r['id'],
        'body': r['body'],
        'author_name': r['author_name'],
        'author_role': r['author_role'],
        'area_name': r['area_name'],
        // As the phone stores its own times, so they sort.
        'created_at': DateTime.parse(r['created_at'] as String).toUtc().toIso8601String(),
        'mine': r['mine'] == true ? 1 : 0,
        'audience': r['audience'],
        'read_count': r['read_count'],
        'read': read || r['read'] == true ? 1 : 0,
        'read_sent': readSent ? 1 : 0,
      };

  /// Everything the person can see, the latest first.
  Future<List<Announcement>> announcements() async =>
      (await _db.query('announcements', orderBy: 'created_at desc')).map(Announcement.fromRow).toList();

  /// What others sent that hasn't been opened yet, the latest first.
  Future<List<Announcement>> unreadAnnouncements() async =>
      (await _db.query('announcements', where: 'mine = 0 and read = 0', orderBy: 'created_at desc'))
          .map(Announcement.fromRow)
          .toList();

  /// Swaps in the server's list, keeping what was opened here and not yet sent.
  Future<void> replaceAnnouncements(List<Map<String, dynamic>> rows) => _db.transaction((tx) async {
        final unsent = (await tx.query('announcements', columns: ['id'], where: 'read_sent = 0'))
            .map((r) => r['id'] as String)
            .toSet();
        await tx.delete('announcements');
        final batch = tx.batch();
        for (final r in rows) {
          final waiting = unsent.contains(r['id']);
          batch.insert('announcements', _announcementRow(r, read: waiting, readSent: !waiting));
        }
        await batch.commit(noResult: true);
      });

  /// One this phone just sent, ahead of the next sync.
  Future<void> addAnnouncement(Map<String, dynamic> json) =>
      _db.insert('announcements', _announcementRow(json), conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> deleteAnnouncement(String id) => _db.delete('announcements', where: 'id = ?', whereArgs: [id]);

  /// They've opened their announcements; the server's told at the next sync.
  Future<void> markAnnouncementsRead() =>
      _db.update('announcements', {'read': 1, 'read_sent': 0}, where: 'mine = 0 and read = 0');

  Future<List<String>> unsentAnnouncementReads() async =>
      (await _db.query('announcements', columns: ['id'], where: 'read_sent = 0')).map((r) => r['id'] as String).toList();

  Future<void> markAnnouncementReadsSent(List<String> ids) => _db.update(
        'announcements',
        {'read_sent': 1},
        where: 'id in (${List.filled(ids.length, '?').join(', ')})',
        whereArgs: ids,
      );

  // --- What's waiting to sync ---------------------------------------------

  Future<List<Voter>> pendingVoters() async =>
      (await _db.query('voters', where: 'pending = 1')).map(Voter.fromRow).toList();

  Future<List<Visit>> unsyncedVisits() async =>
      (await _db.query('visits', where: 'synced = 0', orderBy: 'visited_at')).map(Visit.fromRow).toList();

  Future<int> pendingCount() async {
    final r = await _db.rawQuery('''
      select (select count(*) from voters where pending = 1)
           + (select count(*) from visits where synced = 0)
           + (select count(*) from canvassers where pending = 1)
           + (select count(*) from ward_coordinators where pending = 1)
           + (select count(*) from lga_coordinators where pending = 1) as n
    ''');
    return r.first['n'] as int;
  }

  Future<int> failedCount() async {
    final r = await _db.rawQuery('''
      select (select count(*) from voters where pending = 1 and sync_error is not null)
           + (select count(*) from visits where synced = 0 and sync_error is not null)
           + (select count(*) from canvassers where sync_error is not null)
           + (select count(*) from ward_coordinators where sync_error is not null)
           + (select count(*) from lga_coordinators where sync_error is not null) as n
    ''');
    return r.first['n'] as int;
  }

  /// Applies the server's answer for the people of [table] ('canvassers',
  /// 'ward_coordinators' or 'lga_coordinators') it was sent.
  Future<void> markOnboardedSynced(String table, List<Map<String, dynamic>> results) => _db.transaction((tx) async {
        for (final r in results) {
          final ok = r['status'] == 'ok';
          await tx.update(
            table,
            ok ? {'pending': 0, 'sync_error': null, 'login': r['login'] ?? 'pending'} : {'sync_error': r['error'] ?? 'Not accepted'},
            where: 'id = ?',
            whereArgs: [r['id']],
          );
        }
      });

  /// The people of [table] sent whose login hasn't been made yet.
  Future<List<String>> awaitingLogin(String table) async =>
      (await _db.query(table, columns: ['id'], where: "pending = 0 and coalesce(login, '') <> 'made'"))
          .map((r) => r['id'] as String)
          .toList();

  /// Applies the canvasser-logins function's answer: a login made, or why not.
  Future<void> markLogins(String table, List<Map<String, dynamic>> results) => _db.transaction((tx) async {
        for (final r in results) {
          await tx.update(
            table,
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
