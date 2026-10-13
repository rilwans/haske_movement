import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haske_movement/splash/splash_screen.dart';

void main() {
  Widget app(Future<void> ready) =>
      MaterialApp(home: SplashGate(ready: ready, child: const Text('App')));

  testWidgets('shows the app once the animation and start-up are both done', (tester) async {
    await tester.pumpWidget(app(Future.value()));
    expect(find.text('App'), findsNothing);
    await tester.pump(const Duration(milliseconds: 1000));
    expect(find.text('App'), findsNothing, reason: 'still animating');
    await tester.pumpAndSettle();
    expect(find.text('App'), findsOneWidget);
  });

  testWidgets('waits with loading dots when start-up is slower than the animation', (tester) async {
    final ready = Completer<void>();
    await tester.pumpWidget(app(ready.future));
    await tester.pump(const Duration(milliseconds: 1700));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('App'), findsNothing);
    expect(find.bySemanticsLabel('Loading'), findsOneWidget);
    ready.complete();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('App'), findsOneWidget);
  });

  testWidgets('skips the animation when animations are turned off', (tester) async {
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: app(Future.value()),
    ));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('App'), findsOneWidget);
  });
}
