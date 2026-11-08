import 'dart:convert';

/// A polling unit the signed-in person can canvass.
class PollingUnit {
  const PollingUnit({required this.id, required this.code, required this.name, this.wardId, required this.wardName});

  final String id;
  final String code;
  final String name;

  /// Null in a profile stored before erims sent it, until the next sync.
  final String? wardId;
  final String wardName;

  factory PollingUnit.fromJson(Map<String, dynamic> j) => PollingUnit(
        id: j['id'] as String,
        code: j['code'] as String,
        name: j['name'] as String,
        wardId: j['ward_id'] as String?,
        wardName: j['ward_name'] as String,
      );

  Map<String, dynamic> toJson() => {'id': id, 'code': code, 'name': name, 'ward_id': wardId, 'ward_name': wardName};
}

/// A ward in a coordinator's area, from their polling units.
class Ward {
  const Ward({required this.id, required this.name, required this.pollingUnits});

  final String id;
  final String name;
  final int pollingUnits;
}

/// An LGA in a state coordinator's state, with how much is in it.
class Lga {
  const Lga({required this.id, required this.name, required this.wards, required this.pollingUnits});

  final String id;
  final String name;
  final int wards;
  final int pollingUnits;

  factory Lga.fromJson(Map<String, dynamic> j) => Lga(
        id: j['id'] as String,
        name: j['name'] as String,
        wards: j['wards'] as int,
        pollingUnits: j['polling_units'] as int,
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'wards': wards, 'polling_units': pollingUnits};
}

/// Who is signed in, from my_app_profile(): a canvasser at one polling
/// unit, a ward or LGA coordinator with every polling unit in their area, or
/// a state coordinator with the polling units of the LGA they've chosen.
class AppProfile {
  const AppProfile({
    required this.role,
    required this.personId,
    required this.firstName,
    required this.lastName,
    required this.phone,
    required this.stateName,
    required this.lgaName,
    required this.wardName,
    required this.pollingUnits,
    this.lgas = const [],
    this.selectedLgaId,
  });

  /// 'canvasser', 'ward_coordinator', 'lga_coordinator' or 'state_coordinator'.
  final String role;
  final String personId;
  final String firstName;
  final String lastName;
  final String phone;
  final String stateName;

  /// A state coordinator's chosen LGA; null while they're on the whole state.
  final String? lgaName;

  /// Null for an LGA or state coordinator.
  final String? wardName;
  final List<PollingUnit> pollingUnits;

  /// A state coordinator's LGAs; empty for anyone else.
  final List<Lga> lgas;

  /// The LGA a state coordinator is working in, kept on the phone.
  final String? selectedLgaId;

  bool get isCoordinator => role != 'canvasser';
  bool get isLgaCoordinator => role == 'lga_coordinator';
  bool get isStateCoordinator => role == 'state_coordinator';

  /// Whether they work across wards, so choose among them and add coordinators.
  bool get coversWards => isLgaCoordinator || isStateCoordinator;
  String get fullName => '$firstName $lastName';

  String get roleLabel => switch (role) {
        'ward_coordinator' => 'Ward coordinator',
        'lga_coordinator' => 'LGA coordinator',
        'state_coordinator' => 'State coordinator',
        _ => 'Canvasser',
      };

  /// "Boriya/Shiya ward, Baruten", "Baruten LGA" or "Kwara State".
  String get areaLabel => isStateCoordinator
      ? '$stateName State'
      : wardName != null
          ? '$wardName ward, $lgaName'
          : '$lgaName LGA';

  Lga? lga(String? id) {
    for (final l in lgas) {
      if (l.id == id) return l;
    }
    return null;
  }

  /// This state coordinator working in [lga], with its [units], or across
  /// the state when null.
  AppProfile forLga(Lga? lga, List<PollingUnit> units) => AppProfile(
        role: role,
        personId: personId,
        firstName: firstName,
        lastName: lastName,
        phone: phone,
        stateName: stateName,
        lgaName: lga?.name,
        wardName: wardName,
        pollingUnits: units,
        lgas: lgas,
        selectedLgaId: lga?.id,
      );

  PollingUnit? pollingUnit(String id) {
    for (final p in pollingUnits) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// The wards of [pollingUnits], by name. Empty until the profile has ward ids.
  List<Ward> get wards {
    final names = <String, String>{};
    final counts = <String, int>{};
    for (final p in pollingUnits) {
      final id = p.wardId;
      if (id == null) continue;
      names[id] = p.wardName;
      counts.update(id, (n) => n + 1, ifAbsent: () => 1);
    }
    return [
      for (final id in names.keys) Ward(id: id, name: names[id]!, pollingUnits: counts[id]!),
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  Ward? ward(String id) {
    for (final w in wards) {
      if (w.id == id) return w;
    }
    return null;
  }

  factory AppProfile.fromJson(Map<String, dynamic> j) => AppProfile(
        role: j['role'] as String,
        personId: j['person_id'] as String,
        firstName: j['first_name'] as String,
        lastName: j['last_name'] as String,
        phone: j['phone'] as String,
        stateName: j['state_name'] as String,
        lgaName: j['lga_name'] as String?,
        wardName: j['ward_name'] as String?,
        pollingUnits: [
          for (final p in (j['polling_units'] as List)) PollingUnit.fromJson(p as Map<String, dynamic>),
        ],
        lgas: [
          for (final l in (j['lgas'] as List? ?? const [])) Lga.fromJson(l as Map<String, dynamic>),
        ],
        selectedLgaId: j['selected_lga_id'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'role': role,
        'person_id': personId,
        'first_name': firstName,
        'last_name': lastName,
        'phone': phone,
        'state_name': stateName,
        'lga_name': lgaName,
        'ward_name': wardName,
        'polling_units': pollingUnits.map((p) => p.toJson()).toList(),
        'lgas': lgas.map((l) => l.toJson()).toList(),
        'selected_lga_id': selectedLgaId,
      };
}

/// A canvasser a coordinator onboarded on this phone. Their login is made
/// when it reaches the server.
class NewCanvasser {
  const NewCanvasser({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.phone,
    required this.pollingUnitId,
    required this.createdAt,
    this.pollingUnitName,
    this.whatsappNumber,
    this.email,
    this.pending = true,
    this.syncError,
    this.login,
  });

  final String id;
  final String firstName;
  final String lastName;
  final String phone;
  final String? whatsappNumber;
  final String? email;
  final String pollingUnitId;

  /// Null for one saved before the name was kept.
  final String? pollingUnitName;
  final DateTime createdAt;
  final bool pending;
  final String? syncError;

  /// 'made' once they can sign in, from the server.
  final String? login;

  String get fullName => '$firstName $lastName';

  factory NewCanvasser.fromRow(Map<String, Object?> r) => NewCanvasser(
        id: r['id'] as String,
        firstName: r['first_name'] as String,
        lastName: r['last_name'] as String,
        phone: r['phone'] as String,
        whatsappNumber: r['whatsapp_number'] as String?,
        email: r['email'] as String?,
        pollingUnitId: r['polling_unit_id'] as String,
        pollingUnitName: r['polling_unit_name'] as String?,
        createdAt: DateTime.parse(r['created_at'] as String),
        pending: r['pending'] == 1,
        syncError: r['sync_error'] as String?,
        login: r['login'] as String?,
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'first_name': firstName,
        'last_name': lastName,
        'phone': phone,
        'whatsapp_number': whatsappNumber,
        'email': email,
        'polling_unit_id': pollingUnitId,
        'polling_unit_name': pollingUnitName,
        'created_at': createdAt.toUtc().toIso8601String(),
        'pending': pending ? 1 : 0,
        'sync_error': syncError,
        'login': login,
      };

  /// What canvass_sync() takes for a canvasser.
  Map<String, dynamic> toSyncJson() => {
        'id': id,
        'first_name': firstName,
        'last_name': lastName,
        'phone': phone,
        'whatsapp_number': whatsappNumber,
        'email': email,
        'polling_unit_id': pollingUnitId,
      };
}

/// An LGA coordinator a state coordinator added on this phone. Their login
/// is made when it reaches the server.
class NewLgaCoordinator {
  const NewLgaCoordinator({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.phone,
    required this.lgaId,
    required this.lgaName,
    required this.createdAt,
    this.whatsappNumber,
    this.email,
    this.pending = true,
    this.syncError,
    this.login,
  });

  final String id;
  final String firstName;
  final String lastName;
  final String phone;
  final String? whatsappNumber;
  final String? email;
  final String lgaId;
  final String lgaName;
  final DateTime createdAt;
  final bool pending;
  final String? syncError;

  /// 'made' once they can sign in, from the server.
  final String? login;

  String get fullName => '$firstName $lastName';

  factory NewLgaCoordinator.fromRow(Map<String, Object?> r) => NewLgaCoordinator(
        id: r['id'] as String,
        firstName: r['first_name'] as String,
        lastName: r['last_name'] as String,
        phone: r['phone'] as String,
        whatsappNumber: r['whatsapp_number'] as String?,
        email: r['email'] as String?,
        lgaId: r['lga_id'] as String,
        lgaName: r['lga_name'] as String,
        createdAt: DateTime.parse(r['created_at'] as String),
        pending: r['pending'] == 1,
        syncError: r['sync_error'] as String?,
        login: r['login'] as String?,
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'first_name': firstName,
        'last_name': lastName,
        'phone': phone,
        'whatsapp_number': whatsappNumber,
        'email': email,
        'lga_id': lgaId,
        'lga_name': lgaName,
        'created_at': createdAt.toUtc().toIso8601String(),
        'pending': pending ? 1 : 0,
        'sync_error': syncError,
        'login': login,
      };

  /// What onboard_lga_coordinators() takes.
  Map<String, dynamic> toSyncJson() => {
        'id': id,
        'first_name': firstName,
        'last_name': lastName,
        'phone': phone,
        'whatsapp_number': whatsappNumber,
        'email': email,
        'lga_id': lgaId,
      };
}

/// A ward coordinator an LGA or state coordinator added on this phone. Their
/// login is made when it reaches the server.
class NewWardCoordinator {
  const NewWardCoordinator({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.phone,
    required this.wardId,
    required this.wardName,
    required this.createdAt,
    this.whatsappNumber,
    this.email,
    this.pending = true,
    this.syncError,
    this.login,
  });

  final String id;
  final String firstName;
  final String lastName;
  final String phone;
  final String? whatsappNumber;
  final String? email;
  final String wardId;
  final String wardName;
  final DateTime createdAt;
  final bool pending;
  final String? syncError;

  /// 'made' once they can sign in, from the server.
  final String? login;

  String get fullName => '$firstName $lastName';

  factory NewWardCoordinator.fromRow(Map<String, Object?> r) => NewWardCoordinator(
        id: r['id'] as String,
        firstName: r['first_name'] as String,
        lastName: r['last_name'] as String,
        phone: r['phone'] as String,
        whatsappNumber: r['whatsapp_number'] as String?,
        email: r['email'] as String?,
        wardId: r['ward_id'] as String,
        wardName: r['ward_name'] as String,
        createdAt: DateTime.parse(r['created_at'] as String),
        pending: r['pending'] == 1,
        syncError: r['sync_error'] as String?,
        login: r['login'] as String?,
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'first_name': firstName,
        'last_name': lastName,
        'phone': phone,
        'whatsapp_number': whatsappNumber,
        'email': email,
        'ward_id': wardId,
        'ward_name': wardName,
        'created_at': createdAt.toUtc().toIso8601String(),
        'pending': pending ? 1 : 0,
        'sync_error': syncError,
        'login': login,
      };

  /// What onboard_ward_coordinators() takes.
  Map<String, dynamic> toSyncJson() => {
        'id': id,
        'first_name': firstName,
        'last_name': lastName,
        'phone': phone,
        'whatsapp_number': whatsappNumber,
        'email': email,
        'ward_id': wardId,
      };
}

/// The voter figures for a coordinator's area, or a ward or polling unit in
/// it, from app_voter_stats(). As erims's voter dashboard counts them.
class VoterStats {
  const VoterStats({
    required this.level,
    required this.units,
    required this.registered,
    required this.voters,
    required this.reachable,
    required this.canvassed,
    required this.counts,
    required this.areas,
    required this.canvassers,
    required this.wardCoordinators,
    required this.fetchedAt,
  });

  /// What [areas] are: 'lga', 'ward' or 'polling_unit'.
  final String level;
  final int units;

  /// INEC's registered voters.
  final int registered;

  /// Voters on the list.
  final int voters;

  /// With a phone or WhatsApp number.
  final int reachable;

  /// Visited at least once.
  final int canvassed;

  /// 'gender:M', 'age:25_34', 'age:25_34:F', 'support:undecided',
  /// 'pvc:has_pvc', 'plans:yes' and so on; support, PVC and plans count each
  /// canvassed voter once, by their latest visit.
  final Map<String, int> counts;
  final List<AreaStats> areas;
  final int canvassers;
  final int wardCoordinators;
  final DateTime fetchedAt;

  int count(String key) => counts[key] ?? 0;

  factory VoterStats.fromJson(Map<String, dynamic> j) {
    final team = (j['team'] as Map?) ?? const {};
    return VoterStats(
      level: j['level'] as String,
      units: _int(j['units']),
      registered: _int(j['registered']),
      voters: _int(j['voters']),
      reachable: _int(j['reachable']),
      canvassed: _int(j['canvassed']),
      counts: {for (final e in (j['counts'] as Map).entries) e.key as String: _int(e.value)},
      areas: [for (final a in (j['areas'] as List)) AreaStats.fromJson(a as Map<String, dynamic>)],
      canvassers: _int(team['canvassers']),
      wardCoordinators: _int(team['ward_coordinators']),
      fetchedAt: j['fetched_at'] == null ? DateTime.now() : DateTime.parse(j['fetched_at'] as String),
    );
  }
}

/// One ward or polling unit's line in [VoterStats.areas].
class AreaStats {
  const AreaStats({
    required this.id,
    required this.name,
    required this.units,
    required this.registered,
    required this.voters,
    required this.male,
    required this.female,
    required this.reachable,
    required this.canvassed,
    required this.supporters,
    required this.persuadable,
  });

  final String id;

  /// A ward's name, or a polling unit's code and name.
  final String name;
  final int units;
  final int registered;
  final int voters;
  final int male;
  final int female;
  final int reachable;
  final int canvassed;

  /// Strong or leaning support, by their latest visit.
  final int supporters;

  /// Undecided or leaning against.
  final int persuadable;

  factory AreaStats.fromJson(Map<String, dynamic> j) => AreaStats(
        id: j['id'] as String,
        name: j['name'] as String,
        units: _int(j['units']),
        registered: _int(j['registered']),
        voters: _int(j['voters']),
        male: _int(j['male']),
        female: _int(j['female']),
        reachable: _int(j['reachable']),
        canvassed: _int(j['canvassed']),
        supporters: _int(j['supporters']),
        persuadable: _int(j['persuadable']),
      );
}

/// Counts come as JSON numbers, which may be decoded as doubles.
int _int(Object? v) => (v as num?)?.toInt() ?? 0;

class Voter {
  const Voter({
    required this.id,
    required this.name,
    this.pollingUnitId,
    this.vin,
    this.phone,
    this.whatsappNumber,
    this.email,
    this.gender,
    this.birthYear,
    this.addedLocally = false,
    this.pending = false,
    this.syncError,
    this.visitCount = 0,
    this.latestVisitedAt,
    this.latestSupport,
    this.latestPvcStatus,
    this.latestPlansToVote,
  });

  final String id;
  final String name;

  /// Where they vote; null only for voters stored before this was kept.
  final String? pollingUnitId;
  final String? vin;
  final String? phone;
  final String? whatsappNumber;
  final String? email;

  /// 'M' or 'F'.
  final String? gender;
  final int? birthYear;

  /// Added by this canvasser on the device.
  final bool addedLocally;

  /// Not yet sent to the server.
  final bool pending;
  final String? syncError;

  /// Visits recorded on this phone.
  final int visitCount;

  /// Their latest visit by anyone, as the server last said or recorded here
  /// since, and their answers then. Null if nobody has visited them.
  final DateTime? latestVisitedAt;
  final String? latestSupport;
  final String? latestPvcStatus;
  final String? latestPlansToVote;

  factory Voter.fromRow(Map<String, Object?> r) => Voter(
        id: r['id'] as String,
        name: r['name'] as String,
        pollingUnitId: r['polling_unit_id'] as String?,
        vin: r['vin'] as String?,
        phone: r['phone'] as String?,
        whatsappNumber: r['whatsapp_number'] as String?,
        email: r['email'] as String?,
        gender: r['gender'] as String?,
        birthYear: r['birth_year'] as int?,
        addedLocally: r['added_locally'] == 1,
        pending: r['pending'] == 1,
        syncError: r['sync_error'] as String?,
        visitCount: (r['visit_count'] as int?) ?? 0,
        latestVisitedAt: r['latest_visited_at'] == null ? null : DateTime.parse(r['latest_visited_at'] as String),
        latestSupport: r['latest_support'] as String?,
        latestPvcStatus: r['latest_pvc_status'] as String?,
        latestPlansToVote: r['latest_plans_to_vote'] as String?,
      );

  /// What canvass_sync() takes for a voter added offline.
  Map<String, dynamic> toSyncJson() => {
        'id': id,
        'name': name,
        'polling_unit_id': pollingUnitId,
        'vin': vin,
        'phone': phone,
        'whatsapp_number': whatsappNumber,
        'email': email,
        'gender': gender,
        'birth_year': birthYear,
      };
}

class Visit {
  const Visit({
    required this.id,
    required this.voterId,
    required this.visitedAt,
    this.support,
    this.pvcStatus,
    this.plansToVote,
    this.issues = const [],
    this.notes,
    this.reportedPhone,
    this.reportedWhatsapp,
    this.reportedVin,
    this.reportedGender,
    this.reportedBirthYear,
    this.latitude,
    this.longitude,
    this.synced = false,
    this.syncError,
  });

  final String id;
  final String voterId;
  final DateTime visitedAt;
  final String? support;
  final String? pvcStatus;
  final String? plansToVote;
  final List<String> issues;
  final String? notes;
  final String? reportedPhone;
  final String? reportedWhatsapp;
  final String? reportedVin;
  final String? reportedGender;
  final int? reportedBirthYear;
  final double? latitude;
  final double? longitude;
  final bool synced;
  final String? syncError;

  factory Visit.fromRow(Map<String, Object?> r) => Visit(
        id: r['id'] as String,
        voterId: r['voter_id'] as String,
        visitedAt: DateTime.parse(r['visited_at'] as String),
        support: r['support'] as String?,
        pvcStatus: r['pvc_status'] as String?,
        plansToVote: r['plans_to_vote'] as String?,
        issues: (jsonDecode(r['issues'] as String) as List).cast<String>(),
        notes: r['notes'] as String?,
        reportedPhone: r['reported_phone'] as String?,
        reportedWhatsapp: r['reported_whatsapp'] as String?,
        reportedVin: r['reported_vin'] as String?,
        reportedGender: r['reported_gender'] as String?,
        reportedBirthYear: r['reported_birth_year'] as int?,
        latitude: (r['latitude'] as num?)?.toDouble(),
        longitude: (r['longitude'] as num?)?.toDouble(),
        synced: r['synced'] == 1,
        syncError: r['sync_error'] as String?,
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'voter_id': voterId,
        'visited_at': visitedAt.toUtc().toIso8601String(),
        'support': support,
        'pvc_status': pvcStatus,
        'plans_to_vote': plansToVote,
        'issues': jsonEncode(issues),
        'notes': notes,
        'reported_phone': reportedPhone,
        'reported_whatsapp': reportedWhatsapp,
        'reported_vin': reportedVin,
        'reported_gender': reportedGender,
        'reported_birth_year': reportedBirthYear,
        'latitude': latitude,
        'longitude': longitude,
        'synced': synced ? 1 : 0,
        'sync_error': syncError,
      };

  /// What canvass_sync() takes for a visit.
  Map<String, dynamic> toSyncJson() => {
        'id': id,
        'voter_id': voterId,
        'visited_at': visitedAt.toUtc().toIso8601String(),
        'support': support,
        'pvc_status': pvcStatus,
        'plans_to_vote': plansToVote,
        'issues': issues,
        'notes': notes,
        'reported_phone': reportedPhone,
        'reported_whatsapp': reportedWhatsapp,
        'reported_vin': reportedVin,
        'reported_gender': reportedGender,
        'reported_birth_year': reportedBirthYear,
        'latitude': latitude,
        'longitude': longitude,
      };
}

/// Who to visit next at a polling unit, by each voter's latest visit: erims's
/// lead lists, plus everyone visited.
enum Lead {
  all('All', 'Everyone on the list.'),
  notReached('Not yet canvassed', 'Nobody has visited them yet.'),
  persuadable('Persuadable', 'Undecided or leaning against at their latest visit: worth another conversation.'),
  turnout('Turn out', 'Supporters with a PVC: remind them to vote on the day.'),
  pvc('Need a PVC', "Supporters who haven't collected a PVC or aren't registered: help them get one."),
  wavering('Unsure of voting', "Supporters who said they're unsure or won't vote."),
  visited('Visited', 'Everyone visited at least once, by you or your team.');

  const Lead(this.label, this.hint);

  final String label;
  final String hint;
}

/// The answers a canvasser can pick, as stored and as shown. The stored
/// values match the checks on erims's canvass_visits table.
class Options {
  static const gender = {
    'M': 'Male',
    'F': 'Female',
  };

  static const support = {
    'strong_support': 'Strong support',
    'leaning_support': 'Leaning support',
    'undecided': 'Undecided',
    'leaning_against': 'Leaning against',
    'opposed': 'Opposed',
  };

  static const pvcStatus = {
    'has_pvc': 'Has PVC',
    'registered_no_pvc': 'Registered, no PVC yet',
    'not_registered': 'Not registered',
    'unknown': "Don't know",
  };

  static const plansToVote = {
    'yes': 'Yes',
    'unsure': 'Not sure',
    'no': 'No',
  };

  static const issues = {
    'security': 'Security',
    'roads': 'Roads',
    'jobs': 'Jobs',
    'education': 'Education',
    'health': 'Health',
    'water': 'Water',
    'electricity': 'Electricity',
    'agriculture': 'Agriculture',
    'cost_of_living': 'Cost of living',
    'other': 'Other',
  };
}

/// Someone a coordinator answers for, with what they've done in a period,
/// from app_team_activity().
class TeamMember {
  const TeamMember({
    required this.kind,
    required this.id,
    required this.name,
    required this.phone,
    required this.area,
    required this.wardId,
    required this.hasLogin,
    required this.isMe,
    required this.visits,
    required this.voters,
    required this.units,
    required this.far,
    required this.unlocated,
    required this.rushed,
    required this.lastVisitAt,
  });

  /// 'canvasser', 'ward_coordinator', 'lga_coordinator' or 'state_coordinator'.
  final String kind;
  final String id;
  final String name;
  final String phone;

  /// Their polling unit, ward or LGA.
  final String area;
  final String? wardId;
  final bool hasLogin;
  final bool isMe;
  final int visits;
  final int voters;
  final int units;

  /// Visits far from the polling unit, recorded without the phone's
  /// location, or within a minute of their previous one.
  final int far;
  final int unlocated;
  final int rushed;

  /// Their latest visit ever, whatever the period.
  final DateTime? lastVisitAt;

  int get flagged => far + unlocated + rushed;

  String get kindLabel => switch (kind) {
        'ward_coordinator' => 'Ward coordinator',
        'lga_coordinator' => 'LGA coordinator',
        'state_coordinator' => 'State coordinator',
        _ => 'Canvasser',
      };

  factory TeamMember.fromJson(Map<String, dynamic> j) => TeamMember(
        kind: j['kind'] as String,
        id: j['id'] as String,
        name: j['name'] as String,
        phone: j['phone'] as String,
        area: j['area'] as String,
        wardId: j['ward_id'] as String?,
        hasLogin: j['has_login'] == true,
        isMe: j['is_me'] == true,
        visits: _int(j['visits']),
        voters: _int(j['voters']),
        units: _int(j['units']),
        far: _int(j['far']),
        unlocated: _int(j['unlocated']),
        rushed: _int(j['rushed']),
        lastVisitAt: j['last_visit_at'] == null ? null : DateTime.parse(j['last_visit_at'] as String),
      );
}

class TeamActivity {
  const TeamActivity({required this.farKm, required this.people, required this.fetchedAt});

  /// How far from the polling unit a visit counts as far.
  final int farKm;
  final List<TeamMember> people;
  final DateTime fetchedAt;

  factory TeamActivity.fromJson(Map<String, dynamic> j) => TeamActivity(
        farKm: _int(j['far_km']),
        people: [for (final p in (j['people'] as List)) TeamMember.fromJson(p as Map<String, dynamic>)],
        fetchedAt: j['fetched_at'] == null ? DateTime.now() : DateTime.parse(j['fetched_at'] as String),
      );
}

/// One of a team member's visits, with erims's checks, from app_person_visits().
class TeamVisit {
  const TeamVisit({
    required this.visitedAt,
    required this.voterName,
    required this.pollingUnit,
    this.support,
    this.pvcStatus,
    this.plansToVote,
    required this.located,
    this.distanceKm,
    required this.rushed,
  });

  final DateTime visitedAt;
  final String voterName;
  final String pollingUnit;
  final String? support;
  final String? pvcStatus;
  final String? plansToVote;
  final bool located;

  /// From the polling unit, when both are known.
  final double? distanceKm;
  final bool rushed;

  factory TeamVisit.fromJson(Map<String, dynamic> j) => TeamVisit(
        visitedAt: DateTime.parse(j['visited_at'] as String),
        voterName: j['voter_name'] as String,
        pollingUnit: j['polling_unit'] as String,
        support: j['support'] as String?,
        pvcStatus: j['pvc_status'] as String?,
        plansToVote: j['plans_to_vote'] as String?,
        located: j['located'] == true,
        distanceKm: (j['distance_km'] as num?)?.toDouble(),
        rushed: j['rushed'] == true,
      );
}

/// The wards in a coordinator's area and their targets, from app_ward_targets().
class WardTargets {
  const WardTargets({required this.canSet, required this.recentDays, required this.wards, required this.fetchedAt});

  /// LGA coordinators set their wards' targets.
  final bool canSet;

  /// The days [WardProgress.recent] counts.
  final int recentDays;
  final List<WardProgress> wards;
  final DateTime fetchedAt;

  factory WardTargets.fromJson(Map<String, dynamic> j) {
    final days = _int(j['recent_days']);
    return WardTargets(
      canSet: j['can_set'] == true,
      recentDays: days,
      wards: [for (final w in (j['wards'] as List)) WardProgress.fromJson(w as Map<String, dynamic>, days)],
      fetchedAt: j['fetched_at'] == null ? DateTime.now() : DateTime.parse(j['fetched_at'] as String),
    );
  }
}

enum TargetStatus { none, done, onPace, behind, missed }

/// A ward's canvassing against its target, if it has one.
class WardProgress {
  const WardProgress({
    required this.id,
    required this.name,
    required this.voters,
    required this.canvassed,
    required this.recent,
    required this.recentDays,
    this.target,
  });

  final String id;
  final String name;
  final int voters;

  /// Voters canvassed by anyone, ever.
  final int canvassed;

  /// Voters canvassed for the first time in the last [recentDays] days.
  final int recent;
  final int recentDays;
  final WardTarget? target;

  /// Voters to canvass to reach the target.
  int? get targetCount => target == null ? null : (voters * target!.percent / 100).ceil();

  /// Voters there'd be canvassed by [today] going evenly from when the
  /// target was set to its date.
  int? expectedBy(DateTime today) {
    final t = target, goal = targetCount;
    if (t == null || goal == null) return null;
    final total = t.dueOn.difference(t.startsOn).inDays;
    if (total <= 0 || goal <= t.startCanvassed) return goal;
    final elapsed = _day(today).difference(t.startsOn).inDays.clamp(0, total);
    return (t.startCanvassed + (goal - t.startCanvassed) * elapsed / total).round();
  }

  TargetStatus statusOn(DateTime today) {
    final t = target, goal = targetCount;
    if (t == null || goal == null) return TargetStatus.none;
    if (canvassed >= goal) return TargetStatus.done;
    if (_day(today).isAfter(t.dueOn)) return TargetStatus.missed;
    return canvassed >= expectedBy(today)! ? TargetStatus.onPace : TargetStatus.behind;
  }

  /// When the target would be reached at the last [recentDays] days' rate;
  /// null when it's reached or nobody new has been canvassed lately.
  DateTime? projectedOn(DateTime today) {
    final goal = targetCount;
    if (goal == null || canvassed >= goal || recent == 0) return null;
    final perDay = recent / recentDays;
    return _day(today).add(Duration(days: ((goal - canvassed) / perDay).ceil()));
  }

  factory WardProgress.fromJson(Map<String, dynamic> j, int recentDays) => WardProgress(
        id: j['id'] as String,
        name: j['name'] as String,
        voters: _int(j['voters']),
        canvassed: _int(j['canvassed']),
        recent: _int(j['recent']),
        recentDays: recentDays,
        target: j['target'] == null ? null : WardTarget.fromJson(j['target'] as Map<String, dynamic>),
      );
}

class WardTarget {
  const WardTarget({required this.percent, required this.dueOn, required this.startsOn, required this.startCanvassed});

  /// Of the ward's voters on the list.
  final int percent;
  final DateTime dueOn;

  /// When it was set, and how many were canvassed then.
  final DateTime startsOn;
  final int startCanvassed;

  factory WardTarget.fromJson(Map<String, dynamic> j) => WardTarget(
        percent: _int(j['percent']),
        dueOn: DateTime.parse(j['due_on'] as String),
        startsOn: DateTime.parse(j['starts_on'] as String),
        startCanvassed: _int(j['start_canvassed']),
      );
}

/// Midnight starting [at]'s day, for counting whole days.
DateTime _day(DateTime at) => DateTime(at.year, at.month, at.day);
