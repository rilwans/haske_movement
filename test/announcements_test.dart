import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haske_movement/canvass/announcements.dart';
import 'package:haske_movement/data/models.dart';
import 'package:haske_movement/theme.dart';

AppProfile profile(String role, {String? lga, String? ward, List<Map<String, dynamic>> units = const [], List<Map<String, dynamic>> lgas = const []}) =>
    AppProfile.fromJson({
      'role': role,
      'person_id': 'p',
      'first_name': 'Ada',
      'last_name': 'Bello',
      'phone': '+2348031234567',
      'state_name': 'Kwara',
      'lga_name': lga,
      'ward_name': ward,
      'polling_units': units,
      'lgas': lgas,
    });

Map<String, dynamic> unit(String id, String wardId, String wardName) =>
    {'id': id, 'code': id, 'name': 'Unit $id', 'ward_id': wardId, 'ward_name': wardName};

Announcement announcement({String body = 'Meet at the ward office at 8', bool mine = false, int? audience, int? readCount}) =>
    Announcement.fromRow({
      'id': 'a',
      'body': body,
      'author_name': 'Musa Abubakar Mohammed Ibrahim',
      'author_role': 'lga_coordinator',
      'area_name': 'Boriya/Shiya ward',
      'created_at': '2026-11-09T08:00:00.000Z',
      'mine': mine ? 1 : 0,
      'audience': audience,
      'read_count': readCount,
      'read': 0,
    });

Future<void> pumpAtPhoneWidth(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(320, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: Scaffold(body: child)));
}

void main() {
  group('who someone can announce to', () {
    test('a state coordinator: their state, then each LGA', () {
      final p = profile('state_coordinator', lgas: [
        {'id': 'b', 'name': 'Baruten', 'wards': 10, 'polling_units': 200},
        {'id': 'e', 'name': 'Edu', 'wards': 10, 'polling_units': 100},
      ]);
      expect(p.canAnnounce, isTrue);
      final options = p.announcementAudiences;
      expect(options.map((o) => o.label), ['Kwara State', 'Baruten LGA', 'Edu LGA']);
      expect((options[0].lgaId, options[0].wardId), (null, null));
      expect((options[1].lgaId, options[1].wardId), ('b', null));
    });

    test('an LGA coordinator: their LGA, then each ward', () {
      final p = profile('lga_coordinator', lga: 'Baruten', units: [unit('1', 'w1', 'Okuta'), unit('2', 'w2', 'Yashikira')]);
      final options = p.announcementAudiences;
      expect(options.map((o) => o.label), ['Baruten LGA', 'Okuta ward', 'Yashikira ward']);
      expect((options[0].lgaId, options[0].wardId), (null, null));
      expect((options[1].lgaId, options[1].wardId), (null, 'w1'));
    });

    test('a ward coordinator: only their ward', () {
      final p = profile('ward_coordinator', lga: 'Baruten', ward: 'Okuta', units: [unit('1', 'w1', 'Okuta')]);
      final options = p.announcementAudiences;
      expect(options.map((o) => o.label), ['Okuta ward']);
      expect((options[0].lgaId, options[0].wardId), (null, null));
    });

    test("canvassers and candidates can't send", () {
      expect(profile('canvasser', lga: 'Baruten', ward: 'Okuta').canAnnounce, isFalse);
      expect(profile('candidate').canAnnounce, isFalse);
    });
  });

  group('an announcement', () {
    test('is unread until opened, unless the person sent it', () {
      expect(announcement().unread, isTrue);
      expect(announcement(mine: true).unread, isFalse);
    });

    test('says who has read it', () {
      expect(announcement(mine: true, audience: 30, readCount: 12).readLabel, 'Read by 12 of 30');
      expect(announcement(mine: true, audience: 0, readCount: 0).readLabel, 'Nobody there has a login yet');
    });

    test('names the author\'s role', () {
      expect(announcement().authorRoleLabel, 'LGA coordinator');
    });
  });

  group('on a phone', () {
    testWidgets('the banner shows the latest and how many more, without overflowing', (tester) async {
      var tapped = false;
      await pumpAtPhoneWidth(
        tester,
        UnreadAnnouncementCard(
          unread: [announcement(body: 'Long message ' * 30), announcement(), announcement()],
          onTap: () => tapped = true,
        ),
      );
      expect(find.textContaining('and 2 more'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byType(UnreadAnnouncementCard));
      expect(tapped, isTrue);
    });

    testWidgets("someone else's announcement has no read count or withdraw", (tester) async {
      await pumpAtPhoneWidth(tester, AnnouncementCard(announcement: announcement(), isNew: true, onWithdraw: () {}));
      expect(find.text('New'), findsOneWidget);
      expect(find.text('Withdraw'), findsNothing);
      expect(find.textContaining('Read by'), findsNothing);
      expect(find.textContaining('LGA coordinator'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('their own shows the read count and can be withdrawn', (tester) async {
      var withdrawn = false;
      await pumpAtPhoneWidth(
        tester,
        AnnouncementCard(
          announcement: announcement(mine: true, audience: 30, readCount: 12),
          isNew: false,
          onWithdraw: () => withdrawn = true,
        ),
      );
      expect(find.text('Read by 12 of 30'), findsOneWidget);
      expect(find.textContaining('You · to Boriya/Shiya ward'), findsOneWidget);
      await tester.tap(find.text('Withdraw'));
      expect(withdrawn, isTrue);
      expect(tester.takeException(), isNull);
    });
  });
}
