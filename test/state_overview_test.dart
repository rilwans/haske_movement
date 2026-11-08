import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haske_movement/canvass/state_overview_tab.dart';
import 'package:haske_movement/data/models.dart';
import 'package:haske_movement/theme.dart';

/// An LGA with nothing wrong, changed by [changes].
Map<String, dynamic> lga(String id, [Map<String, dynamic> changes = const {}]) => {
      'id': id,
      'name': id,
      'voters': 1000,
      'canvassed': 100,
      'supporters': 40,
      'persuadable': 20,
      'visits_7d': 50,
      'visits_prev_7d': 50,
      'new_7d': 14,
      'new_prev_7d': 14,
      'lga_coordinators': 1,
      ...changes,
    };

StateOverview overview(List<Map<String, dynamic>> lgas, {String? electionDate}) => StateOverview.fromJson({
      'next_election': electionDate == null ? null : {'name': 'Governorship', 'date': electionDate},
      'lgas': lgas,
      'fetched_at': '2026-11-08T10:00:00Z',
    });

void main() {
  final today = DateTime(2026, 11, 8, 15, 30);

  test('raises nothing for an LGA going well', () {
    expect(LgaOverview.fromJson(lga('a')).concerns, isEmpty);
    expect(overview([lga('a')]).needingAttention, isEmpty);
  });

  test('says what is wrong, the most serious first', () {
    final l = LgaOverview.fromJson(lga('a', {
      'lga_coordinators': 0,
      'visits_7d': 0,
      'wards_missed': 1,
      'wards_behind': 2,
    }));
    expect(l.concerns, [
      'No LGA coordinator',
      'No visits in the last 7 days',
      '1 ward past the target date',
      '2 wards behind target',
    ]);
  });

  test('only calls a real fall in visits slowing down', () {
    expect(LgaOverview.fromJson(lga('a', {'visits_7d': 20, 'visits_prev_7d': 50})).concerns, [
      'Visits down 60% on the week before',
    ]);
    expect(LgaOverview.fromJson(lga('a', {'visits_7d': 26, 'visits_prev_7d': 50})).concerns, isEmpty);
    expect(LgaOverview.fromJson(lga('a', {'visits_7d': 2, 'visits_prev_7d': 9})).concerns, isEmpty);
  });

  test('raises visits to check once they are many and a large share', () {
    expect(LgaOverview.fromJson(lga('a', {'flagged_7d': 10})).concerns, ['10 visits to check']);
    expect(LgaOverview.fromJson(lga('a', {'flagged_7d': 9})).concerns, isEmpty);
    expect(LgaOverview.fromJson(lga('a', {'flagged_7d': 4, 'visits_7d': 8, 'visits_prev_7d': 8})).concerns, isEmpty);
  });

  test('does not raise a quiet LGA that has no voters', () {
    expect(LgaOverview.fromJson(lga('a', {'voters': 0, 'visits_7d': 0})).concerns, isEmpty);
  });

  test('puts the LGAs with the most concerns first, then the largest', () {
    final o = overview([
      lga('small', {'lga_coordinators': 0, 'voters': 500}),
      lga('big', {'lga_coordinators': 0, 'voters': 5000}),
      lga('worst', {'lga_coordinators': 0, 'wards_behind': 1, 'voters': 100}),
      lga('fine'),
    ]);
    expect(o.needingAttention.map((l) => l.id), ['worst', 'big', 'small']);
  });

  test('projects coverage to the election at the last 14 days pace', () {
    // 2 LGAs each 2 new a day; 200 canvassed, 4 a day for 68 days is 472.
    final o = overview([lga('a'), lga('b')], electionDate: '2027-01-15');
    expect(o.newPerDay, 4);
    expect(o.daysLeft(today), 68);
    expect(o.projectedCanvassed(today), 472);
  });

  test('never projects more voters than there are', () {
    final o = overview([lga('a', {'new_7d': 700, 'new_prev_7d': 700})], electionDate: '2027-01-15');
    expect(o.projectedCanvassed(today), 1000);
  });

  test('makes no projection without an election or recent progress', () {
    expect(overview([lga('a')]).projectedCanvassed(today), isNull);
    expect(overview([lga('a', {'new_7d': 0, 'new_prev_7d': 0})], electionDate: '2027-01-15').projectedCanvassed(today), isNull);
  });

  test('adds up issues across LGAs, the most named first', () {
    final o = overview([
      lga('a', {
        'issues': {'roads': 5, 'water': 3},
        'issues_persuadable': {'jobs': 2},
      }),
      lga('b', {
        'issues': {'water': 4, 'security': 1},
      }),
    ]);
    expect(o.topIssues().map((e) => '${e.key}:${e.value}'), ['water:7', 'roads:5', 'security:1']);
    expect(o.topIssues(persuadableOnly: true).single.key, 'jobs');
    expect(LgaOverview.fromJson(lga('c', {'issues': {'a': 1, 'b': 2, 'c': 3, 'd': 4}})).topIssues(), ['d', 'c', 'b']);
  });

  group('on a phone', () {
    final busy = overview([
      for (var i = 0; i < 7; i++)
        lga('A long local government area name $i', {
          'voters': 1234567,
          'lga_coordinators': 0,
          'visits_7d': 0,
          'wards': 11,
          'wards_no_coordinator': 3,
          'wards_behind': 2,
          'wards_missed': 1,
          'units': 231,
          'units_no_canvasser': 120,
          'ready': 30,
          'need_pvc': 10,
          'wavering': 5,
          'issues': {'cost_of_living': 9, 'roads': 5, 'security': 1},
          'issues_persuadable': {'agriculture': 2},
        }),
    ], electionDate: '2027-01-15');

    Future<List<String>> pump(WidgetTester tester, StateOverview o) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final opened = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: StateOverviewPanels(overview: o, areaLabel: 'Kwara State', onOpen: (l) => opened.add(l.name)),
            ),
          ),
        ),
      );
      return opened;
    }

    testWidgets('shows every section without overflowing', (tester) async {
      await pump(tester, busy);
      expect(tester.takeException(), isNull);
      for (final title in ['Needs attention', 'Momentum', 'Vote count', 'LGAs ranked', 'Coverage gaps', 'Top issues']) {
        expect(find.text(title), findsOneWidget);
      }
      expect(find.text('Cost of living'), findsOneWidget);
    });

    testWidgets('shows five LGAs needing attention until asked for all', (tester) async {
      await pump(tester, busy);
      expect(find.text('No LGA coordinator · No visits in the last 7 days · 1 ward past the target date · 2 wards behind target'), findsNWidgets(5));
      await tester.ensureVisible(find.text('Show all 7'));
      await tester.pump();
      await tester.tap(find.text('Show all 7'));
      await tester.pump();
      expect(find.text('No LGA coordinator · No visits in the last 7 days · 1 ward past the target date · 2 wards behind target'), findsNWidgets(7));
    });

    testWidgets('opens the LGA tapped and switches to persuadable issues', (tester) async {
      final opened = await pump(tester, busy);
      await tester.tap(find.widgetWithText(ListTile, 'A long local government area name 0').first);
      expect(opened, ['A long local government area name 0']);
      await tester.ensureVisible(find.text('Persuadable').last);
      await tester.tap(find.text('Persuadable').last);
      await tester.pump();
      expect(find.text('Agriculture'), findsOneWidget);
      expect(find.text('Cost of living'), findsNothing);
    });

    testWidgets('copes with nothing canvassed and no election', (tester) async {
      await pump(tester, overview([lga('a', {'canvassed': 0, 'new_7d': 0, 'new_prev_7d': 0})]));
      expect(tester.takeException(), isNull);
      expect(find.text('Nobody has been canvassed yet.'), findsOneWidget);
      expect(find.text('No issues recorded yet.'), findsOneWidget);
      expect(find.textContaining("so there's no projection"), findsOneWidget);
    });
  });

  test('sees a gap in wards or polling units', () {
    expect(LgaOverview.fromJson(lga('a')).hasGaps, isFalse);
    expect(LgaOverview.fromJson(lga('a', {'units_no_canvasser': 1})).hasGaps, isTrue);
    expect(LgaOverview.fromJson(lga('a', {'wards_no_coordinator': 1})).hasGaps, isTrue);
  });
}
