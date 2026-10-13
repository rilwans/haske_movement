import 'dart:convert';

/// A polling unit the signed-in person can canvass.
class PollingUnit {
  const PollingUnit({required this.id, required this.code, required this.name, required this.wardName});

  final String id;
  final String code;
  final String name;
  final String wardName;

  factory PollingUnit.fromJson(Map<String, dynamic> j) => PollingUnit(
        id: j['id'] as String,
        code: j['code'] as String,
        name: j['name'] as String,
        wardName: j['ward_name'] as String,
      );

  Map<String, dynamic> toJson() => {'id': id, 'code': code, 'name': name, 'ward_name': wardName};
}

/// Who is signed in, from my_app_profile(): a canvasser at one polling
/// unit, or a ward or LGA coordinator with every polling unit in their area.
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
  });

  /// 'canvasser', 'ward_coordinator' or 'lga_coordinator'.
  final String role;
  final String personId;
  final String firstName;
  final String lastName;
  final String phone;
  final String stateName;
  final String lgaName;

  /// Null for an LGA coordinator.
  final String? wardName;
  final List<PollingUnit> pollingUnits;

  bool get isCoordinator => role != 'canvasser';
  String get fullName => '$firstName $lastName';

  String get roleLabel => switch (role) {
        'ward_coordinator' => 'Ward coordinator',
        'lga_coordinator' => 'LGA coordinator',
        _ => 'Canvasser',
      };

  /// "Boriya/Shiya ward, Baruten" or "Baruten LGA".
  String get areaLabel => wardName != null ? '$wardName ward, $lgaName' : '$lgaName LGA';

  PollingUnit? pollingUnit(String id) {
    for (final p in pollingUnits) {
      if (p.id == id) return p;
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
        lgaName: j['lga_name'] as String,
        wardName: j['ward_name'] as String?,
        pollingUnits: [
          for (final p in (j['polling_units'] as List)) PollingUnit.fromJson(p as Map<String, dynamic>),
        ],
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

class Voter {
  const Voter({
    required this.id,
    required this.name,
    this.pollingUnitId,
    this.vin,
    this.phone,
    this.whatsappNumber,
    this.email,
    this.addedLocally = false,
    this.pending = false,
    this.syncError,
    this.visitCount = 0,
  });

  final String id;
  final String name;

  /// Where they vote; null only for voters stored before this was kept.
  final String? pollingUnitId;
  final String? vin;
  final String? phone;
  final String? whatsappNumber;
  final String? email;

  /// Added by this canvasser on the device.
  final bool addedLocally;

  /// Not yet sent to the server.
  final bool pending;
  final String? syncError;
  final int visitCount;

  factory Voter.fromRow(Map<String, Object?> r) => Voter(
        id: r['id'] as String,
        name: r['name'] as String,
        pollingUnitId: r['polling_unit_id'] as String?,
        vin: r['vin'] as String?,
        phone: r['phone'] as String?,
        whatsappNumber: r['whatsapp_number'] as String?,
        email: r['email'] as String?,
        addedLocally: r['added_locally'] == 1,
        pending: r['pending'] == 1,
        syncError: r['sync_error'] as String?,
        visitCount: (r['visit_count'] as int?) ?? 0,
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
        'latitude': latitude,
        'longitude': longitude,
      };
}

/// The answers a canvasser can pick, as stored and as shown. The stored
/// values match the checks on erims's canvass_visits table.
class Options {
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
