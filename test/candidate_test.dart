import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haske_movement/canvass/lga_brief_screen.dart';
import 'package:haske_movement/canvass/state_overview_tab.dart';
import 'package:haske_movement/data/models.dart';
import 'package:haske_movement/theme.dart';

/// A candidate as my_app_profile() sends them.
AppProfile profile() => AppProfile.fromJson({
      'role': 'candidate',
      'person_id': 'c',
      'first_name': 'Ada',
      'last_name': 'Bello',
      'phone': '+2348031234567',
      'state_name': 'Kwara',
      'area_name': 'Kwara North',
      'lga_name': null,
      'ward_name': null,
      'polling_units': <dynamic>[],
      'lgas': [
        {'id': 'b', 'name': 'Baruten', 'wards': 10, 'polling_units': 200},
      ],
    });

Map<String, dynamic> lgaJson(String name, [Map<String, dynamic> changes = const {}]) => {
      'id': name,
      'name': name,
      'voters': 1234567,
      'canvassed': 1000,
      'supporters': 400,
      'persuadable': 200,
      'ready': 300,
      'need_pvc': 50,
      'visits_7d': 50,
      'visits_prev_7d': 50,
      'active_7d': 12,
      'canvassers': 40,
      'ward_coordinators': 9,
      'lga_coordinators': 1,
      'wards': 11,
      'wards_no_coordinator': 2,
      'units': 231,
      'units_no_canvasser': 120,
      'issues': {'cost_of_living': 9, 'roads': 5},
      'issues_persuadable': {'agriculture': 2},
      ...changes,
    };

Future<void> pumpAtPhoneWidth(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(320, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: Scaffold(body: child)));
}

void main() {
  test('a candidate covers their election area and chooses among its LGAs', () {
    final p = profile();
    expect(p.isCandidate, isTrue);
    expect(p.picksLga, isTrue);
    expect(p.isStateCoordinator, isFalse);
    expect(p.isLgaCoordinator, isFalse);
    expect(p.roleLabel, 'Candidate');
    expect(p.areaLabel, 'Kwara North');
    expect(p.allLgasLabel, 'All LGAs in Kwara North');
  });

  test('a candidate keeps their area when moved between LGAs and stored', () {
    final p = profile();
    final stored = AppProfile.fromJson(p.forLga(p.lga('b'), const []).toJson());
    expect(stored.areaLabel, 'Kwara North');
    expect(stored.selectedLgaId, 'b');
    expect(stored.lgaName, 'Baruten');
    expect(stored.isCandidate, isTrue);
  });

  test('a presidential candidate has no state, and is labelled by their area', () {
    final j = profile().toJson()
      ..['state_name'] = null
      ..['area_name'] = 'Nigeria';
    final p = AppProfile.fromJson(j);
    expect(p.areaLabel, 'Nigeria');
    expect(p.allLgasLabel, 'All LGAs in Nigeria');
  });

  test('a one-word candidate name has no trailing space', () {
    final j = profile().toJson()..['last_name'] = '';
    expect(AppProfile.fromJson(j).fullName, 'Ada');
  });

  test('a state coordinator still sees their state, and only their LGAs choice', () {
    final j = profile().toJson()
      ..['role'] = 'state_coordinator'
      ..['area_name'] = null;
    final p = AppProfile.fromJson(j);
    expect(p.areaLabel, 'Kwara State');
    expect(p.allLgasLabel, 'All LGAs in Kwara');
    expect(p.isCandidate, isFalse);
  });

  group('on a phone', () {
    StateOverview overview({bool election = true}) => StateOverview.fromJson({
          'next_election': election ? {'name': '2027 Senatorial election – Kwara North', 'date': '2027-01-16'} : null,
          'lgas': [lgaJson('A long local government area'), lgaJson('Moro', {'lga_coordinators': 0})],
          'fetched_at': '2026-11-08T10:00:00Z',
        });

    Widget panels({required bool forCandidate, bool election = true}) => SingleChildScrollView(
          child: StateOverviewPanels(
            overview: overview(election: election),
            areaLabel: 'Kwara North',
            onOpen: (_) {},
            forCandidate: forCandidate,
          ),
        );

    testWidgets('a candidate gets the headline and team strength', (tester) async {
      await pumpAtPhoneWidth(tester, panels(forCandidate: true));
      expect(tester.takeException(), isNull);
      expect(find.text('2027 Senatorial election – Kwara North'), findsOneWidget);
      expect(find.text('days to go'), findsOneWidget);
      expect(find.text('ready to vote'), findsOneWidget);
      expect(find.text('Team strength'), findsOneWidget);
      expect(find.textContaining('18 ward coordinators'), findsOneWidget);
    });

    testWidgets('a state coordinator does not', (tester) async {
      await pumpAtPhoneWidth(tester, panels(forCandidate: false));
      expect(find.text('days to go'), findsNothing);
      expect(find.text('Team strength'), findsNothing);
    });

    testWidgets('the headline copes with no election', (tester) async {
      await pumpAtPhoneWidth(tester, panels(forCandidate: true, election: false));
      expect(tester.takeException(), isNull);
      expect(find.text('At a glance'), findsOneWidget);
      expect(find.text('–'), findsWidgets);
    });

    Widget brief({List<LgaContact>? contacts, String? error, VoidCallback? onSeeWards, Map<String, dynamic> lga = const {}}) => LgaBrief(
          lga: LgaOverview.fromJson(lgaJson('Moro', lga)),
          contacts: contacts,
          contactsError: error,
          onSeeWards: onSeeWards ?? () {},
        );

    testWidgets('the visit brief shows the figures, issues and coordinator', (tester) async {
      var seeWards = 0;
      await pumpAtPhoneWidth(
        tester,
        brief(
          contacts: const [LgaContact(name: 'A very long coordinator name indeed', phone: '+2348031234567')],
          onSeeWards: () => seeWards++,
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Cost of living, Roads'), findsOneWidget);
      expect(find.text('Agriculture'), findsOneWidget);
      expect(find.text('0803 123 4567'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('See ward by ward'), 200, scrollable: find.byType(Scrollable).first);
      await tester.pump();
      await tester.tap(find.text('See ward by ward'));
      expect(seeWards, 1);
    });

    testWidgets('the visit brief says when there is no coordinator or issue yet', (tester) async {
      await pumpAtPhoneWidth(tester, brief(contacts: const [], lga: {'issues': <String, int>{}, 'lga_coordinators': 0}));
      expect(find.text('No LGA coordinator yet.'), findsOneWidget);
      expect(find.text('No issues recorded here yet.'), findsOneWidget);
      expect(find.text('No LGA coordinator'), findsOneWidget);
    });

    testWidgets('the visit brief still shows when the coordinator cannot load', (tester) async {
      await pumpAtPhoneWidth(tester, brief(error: 'No internet'));
      expect(find.textContaining("Couldn't load the LGA coordinator"), findsOneWidget);
    });
  });
}
