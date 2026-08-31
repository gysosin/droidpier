import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_android_dex/ui/desk/notification_center.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';
import 'package:open_dex_api/open_dex_api.dart';

/// The phone owns the notification list. The centre asks it to change and waits
/// — it must never remove an item locally, because showing a notification as
/// gone while it still sits on the phone's shade is worse than a moment of
/// latency.
void main() {
  final DateTime now = DateTime.utc(2026, 8, 25, 9);

  NotificationItem item(String id) => NotificationItem(
    id: id,
    packageName: 'com.demo.messages',
    title: 'Message $id',
    body: 'Body $id',
    timestamp: now.subtract(const Duration(minutes: 4)),
  );

  Future<List<String>> pump(
    WidgetTester tester, {
    required Completer<void> gate,
    List<String> ids = const <String>['a', 'b'],
  }) async {
    final List<String> dismissed = <String>[];
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: DexTheme.dark(),
        home: Scaffold(
          body: NotificationCenter(
            notifications: <NotificationItem>[
              for (final String i in ids) item(i),
            ],
            status: LoadStatus.ready,
            applications: const <AndroidApplication>[],
            now: now,
            onClose: () {},
            onDismiss: (String id) async {
              dismissed.add(id);
              await gate.future;
            },
            onActivate: (_) async {},
            onDismissAll: () async {
              dismissed.add('*');
              await gate.future;
            },
          ),
        ),
      ),
    );
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    return dismissed;
  }

  testWidgets('dismissing asks the phone and keeps showing the item', (
    WidgetTester tester,
  ) async {
    final Completer<void> gate = Completer<void>();
    final List<String> dismissed = await pump(tester, gate: gate);

    await tester.tap(find.bySemanticsLabel('Dismiss Message a'));
    await tester.pump();

    expect(dismissed, <String>['a'], reason: 'the phone was asked');
    expect(
      find.text('Message a'),
      findsOneWidget,
      reason: 'it stays until the phone drops it from the snapshot',
    );
    expect(
      find.text('Dismissing…'),
      findsOneWidget,
      reason: 'the row says a request is in flight rather than going still',
    );

    gate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('a second dismiss of the same item is refused while in flight', (
    WidgetTester tester,
  ) async {
    final Completer<void> gate = Completer<void>();
    final List<String> dismissed = await pump(tester, gate: gate);

    await tester.tap(find.bySemanticsLabel('Dismiss Message a'));
    await tester.pump();
    await tester.tap(
      find.bySemanticsLabel('Dismiss Message a'),
      warnIfMissed: false,
    );
    await tester.pump();

    expect(dismissed, <String>['a'], reason: 'not sent twice');

    gate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('clear all sends one request, not one per item', (
    WidgetTester tester,
  ) async {
    final Completer<void> gate = Completer<void>();
    final List<String> dismissed = await pump(tester, gate: gate);

    await tester.tap(find.text('Clear all'));
    await tester.pump();

    expect(dismissed, <String>['*']);

    gate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  });
}
