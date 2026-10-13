import 'package:flutter_test/flutter_test.dart';
import 'package:haske_movement/auth/phone.dart';
import 'package:haske_movement/canvass/ward_filter.dart';
import 'package:haske_movement/data/models.dart';

void main() {
  test('phone numbers become E.164', () {
    expect(toE164('0803 123 4567'), '+2348031234567');
    expect(toE164('803-123-4567'), '+2348031234567');
    expect(toE164('2348031234567'), '+2348031234567');
    expect(toE164('+234 803 123 4567'), '+2348031234567');
    expect(toE164('12345'), isNull);
    expect(toE164(''), isNull);
  });

  test('polling units filter by ward and search', () {
    const units = [
      PollingUnit(id: '1', code: '23-02-01-001', name: 'Boriya School', wardName: 'Boriya/Shiya'),
      PollingUnit(id: '2', code: '23-02-01-002', name: 'Shiya Market', wardName: 'Boriya/Shiya'),
      PollingUnit(id: '3', code: '23-02-05-001', name: 'Gwanara Square', wardName: 'Gwanara'),
    ];
    expect(filterPollingUnits(units).length, 3);
    expect(filterPollingUnits(units, ward: 'Gwanara').map((u) => u.id), ['3']);
    expect(filterPollingUnits(units, ward: 'Boriya/Shiya', search: 'market').map((u) => u.id), ['2']);
    expect(filterPollingUnits(units, search: '05-001').map((u) => u.id), ['3']);
  });
}
