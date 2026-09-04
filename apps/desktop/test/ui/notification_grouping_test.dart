import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_android_dex/ui/desk/notification_center.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';
import 'package:open_android_dex/ui/theme/glass.dart';
import 'package:open_dex_api/open_dex_api.dart';

/// A backlog is mostly one chatty app. Before this, a group of thirty pushed
/// every other sender off the screen, so the centre answered "what has
/// happened?" with "Messages happened".
void main() {
  final DateTime now = DateTime.utc(2026, 8, 25, 9);

  NotificationItem n(String pkg, String title, int minsAgo) => NotificationItem(
    id: '$pkg-$title',
    packageName: pkg,
    title: title,
    body: 'body of $title',
    timestamp: now.subtract(Duration(minutes: minsAgo)),
  );

  Future<void> pump(WidgetTester tester, List<NotificationItem> items) async {
    await tester.binding.setSurfaceSize(const Size(1100, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: DexTheme.dark(),
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: DeskWallpaper(
            child: NotificationCenter(
              notifications: items,
              status: LoadStatus.ready,
              applications: const <AndroidApplication>[
                AndroidApplication(
                  packageName: 'com.demo.messages',
                  label: 'Messages',
                ),
                AndroidApplication(
                  packageName: 'com.demo.calendar',
                  label: 'Calendar',
                ),
              ],
              now: now,
              onClose: () {},
              onDismiss: (_) async {},
              onActivate: (_) async {},
              onDismissAll: () async {},
              onOpenPermissions: () {},
            ),
          ),
        ),
      ),
    );
    // Twice, not once: the entrance staggers with Future.delayed, so the
    // controller only advances on the frame after it resolves.
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  List<NotificationItem> many(int count) => <NotificationItem>[
    for (int i = 0; i < count; i++) n('com.demo.messages', 'Message $i', i),
  ];

  testWidgets('a long group shows only the first few', (
    WidgetTester tester,
  ) async {
    await pump(tester, many(6));

    expect(find.text('Message 0'), findsOneWidget);
    expect(find.text('Message 2'), findsOneWidget);
    // Beyond the threshold the rest are not built at all, which is the point:
    // a group of thirty must not cost thirty rows to render.
    expect(find.text('Message 3'), findsNothing);
    expect(find.text('Message 5'), findsNothing);
    expect(find.text('Show 3 more'), findsOneWidget);
  });

  testWidgets('expanding a group reveals the rest', (
    WidgetTester tester,
  ) async {
    await pump(tester, many(6));

    await tester.ensureVisible(find.text('Show 3 more'));
    await tester.pump();
    await tester.tap(find.text('Show 3 more'));
    for (int i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    expect(find.text('Message 5'), findsOneWidget);
    expect(find.text('Show 3 more'), findsNothing);
    expect(find.text('Show less'), findsOneWidget);
  });

  testWidgets('collapsing puts them away again', (WidgetTester tester) async {
    await pump(tester, many(6));

    await tester.ensureVisible(find.text('Show 3 more'));
    await tester.pump();
    await tester.tap(find.text('Show 3 more'));
    for (int i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    await tester.ensureVisible(find.text('Show less'));
    await tester.pump();
    await tester.tap(find.text('Show less'));
    for (int i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    expect(find.text('Message 5'), findsNothing);
    expect(find.text('Show 3 more'), findsOneWidget);
  });

  testWidgets('a group that fits has no control to press', (
    WidgetTester tester,
  ) async {
    await pump(tester, many(3));

    expect(find.text('Message 2'), findsOneWidget);
    expect(find.textContaining('more'), findsNothing);
    expect(find.text('Show less'), findsNothing);
  });

  testWidgets('the header counts a group, and stays quiet about one', (
    WidgetTester tester,
  ) async {
    await pump(tester, <NotificationItem>[
      ...many(4),
      n('com.demo.calendar', 'Standup', 8),
    ]);

    // The count belongs to the sender's row, not to the list.
    final Finder header = find.ancestor(
      of: find.text('Messages'),
      matching: find.byType(Row),
    );
    expect(find.descendant(of: header.first, matching: find.text('4 items')),
        findsOneWidget);

    // A lone notification needs no badge saying "1" — that is noise.
    final Finder calendar = find.ancestor(
      of: find.text('Calendar'),
      matching: find.byType(Row),
    );
    expect(find.descendant(of: calendar.first, matching: find.text('1')),
        findsNothing);
  });
}
