import 'package:flutter_test/flutter_test.dart';
import 'package:haske_movement/data/models.dart';

/// A ward of 1,000 voters with 100 canvassed when its 60% target was set on
/// 1 Oct for 31 Oct: 600 voters, 500 more over 30 days.
WardProgress ward({required int canvassed, int recent = 0, bool target = true}) => WardProgress(
      id: 'w',
      name: 'Ward',
      voters: 1000,
      canvassed: canvassed,
      recent: recent,
      recentDays: 14,
      target: target
          ? WardTarget(percent: 60, dueOn: DateTime(2026, 10, 31), startsOn: DateTime(2026, 10, 1), startCanvassed: 100)
          : null,
    );

void main() {
  final midway = DateTime(2026, 10, 16, 15, 30);

  test('expects an even pace from when the target was set', () {
    expect(ward(canvassed: 0).targetCount, 600);
    expect(ward(canvassed: 0).expectedBy(DateTime(2026, 10, 1)), 100);
    expect(ward(canvassed: 0).expectedBy(midway), 350);
    expect(ward(canvassed: 0).expectedBy(DateTime(2026, 11, 20)), 600);
  });

  test('says whether a ward is on pace, behind, done or past its date', () {
    expect(ward(canvassed: 350).statusOn(midway), TargetStatus.onPace);
    expect(ward(canvassed: 349).statusOn(midway), TargetStatus.behind);
    expect(ward(canvassed: 600).statusOn(midway), TargetStatus.done);
    expect(ward(canvassed: 599).statusOn(DateTime(2026, 11, 1)), TargetStatus.missed);
    expect(ward(canvassed: 599).statusOn(DateTime(2026, 10, 31, 23)), TargetStatus.behind);
    expect(ward(canvassed: 0, target: false).statusOn(midway), TargetStatus.none);
  });

  test('projects the finish from the recent rate', () {
    // 140 new in 14 days is 10 a day; 250 to go is 25 days.
    expect(ward(canvassed: 350, recent: 140).projectedOn(midway), DateTime(2026, 11, 10));
    expect(ward(canvassed: 350).projectedOn(midway), isNull);
    expect(ward(canvassed: 600, recent: 140).projectedOn(midway), isNull);
  });
}
