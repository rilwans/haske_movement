import 'package:flutter_test/flutter_test.dart';
import 'package:haske_movement/data/models.dart';

/// A state coordinator as my_app_profile() sends them.
AppProfile profile() => AppProfile.fromJson({
      'role': 'state_coordinator',
      'person_id': 'p',
      'first_name': 'Ada',
      'last_name': 'Bello',
      'phone': '+2348031234567',
      'state_name': 'Kwara',
      'lga_name': null,
      'ward_name': null,
      'polling_units': <dynamic>[],
      'lgas': [
        {'id': 'b', 'name': 'Baruten', 'wards': 10, 'polling_units': 200},
        {'id': 'm', 'name': 'Moro', 'wards': 12, 'polling_units': 240},
      ],
    });

const unit = PollingUnit(id: '1', code: '23-02-01-001', name: 'Boriya School', wardId: 'w', wardName: 'Boriya/Shiya');

void main() {
  test('starts on the whole state, with no polling units', () {
    final p = profile();
    expect(p.isCoordinator, isTrue);
    expect(p.isLgaCoordinator, isFalse);
    expect(p.coversWards, isTrue);
    expect(p.roleLabel, 'State coordinator');
    expect(p.areaLabel, 'Kwara State');
    expect(p.selectedLgaId, isNull);
    expect(p.lga(null), isNull);
    expect(p.lgas.map((l) => l.name), ['Baruten', 'Moro']);
  });

  test('takes on the chosen LGA and its polling units, and can go back', () {
    final p = profile();
    final inBaruten = p.forLga(p.lga('b'), const [unit]);
    expect(inBaruten.lgaName, 'Baruten');
    expect(inBaruten.selectedLgaId, 'b');
    expect(inBaruten.pollingUnit('1')?.name, 'Boriya School');
    expect(inBaruten.wards.map((w) => w.name), ['Boriya/Shiya']);
    expect(inBaruten.areaLabel, 'Kwara State');
    expect(inBaruten.lgas.length, 2);

    final back = inBaruten.forLga(null, const []);
    expect(back.lgaName, isNull);
    expect(back.selectedLgaId, isNull);
    expect(back.pollingUnits, isEmpty);
  });

  test('keeps the chosen LGA when stored on the phone', () {
    final p = profile();
    final stored = AppProfile.fromJson(p.forLga(p.lga('m'), const [unit]).toJson());
    expect(stored.selectedLgaId, 'm');
    expect(stored.lgaName, 'Moro');
    expect(stored.pollingUnits.single.wardId, 'w');
    expect(stored.lga('b')?.pollingUnits, 200);
  });

  test("reads an LGA coordinator's profile, stored before LGAs were sent", () {
    final p = AppProfile.fromJson({
      'role': 'lga_coordinator',
      'person_id': 'p',
      'first_name': 'Ada',
      'last_name': 'Bello',
      'phone': '+2348031234567',
      'state_name': 'Kwara',
      'lga_name': 'Baruten',
      'ward_name': null,
      'polling_units': [unit.toJson()],
    });
    expect(p.coversWards, isTrue);
    expect(p.isStateCoordinator, isFalse);
    expect(p.areaLabel, 'Baruten LGA');
    expect(p.lgas, isEmpty);
  });

  test('sends an LGA coordinator to the server by their LGA', () {
    final c = NewLgaCoordinator(
      id: 'c',
      firstName: 'Musa',
      lastName: 'Ali',
      phone: '+2348030000000',
      lgaId: 'b',
      lgaName: 'Baruten',
      createdAt: DateTime.utc(2026, 11, 8),
    );
    expect(c.toSyncJson()['lga_id'], 'b');
    expect(c.toSyncJson().containsKey('lga_name'), isFalse);
    final stored = NewLgaCoordinator.fromRow(c.toRow());
    expect(stored.fullName, 'Musa Ali');
    expect(stored.pending, isTrue);
    expect(stored.lgaName, 'Baruten');
  });
}
