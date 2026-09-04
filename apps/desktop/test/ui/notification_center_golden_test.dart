@Tags(<String>['golden'])
library;

import 'package:open_android_dex/ui/desk/notification_center.dart';
import 'package:open_android_dex/ui/theme/glass.dart';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';

Future<void> _loadFonts() async {
  final String root =
      Platform.environment['FLUTTER_ROOT'] ??
      Directory('../../.tools/flutter').absolute.path;
  final File icons = File(
    '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  if (icons.existsSync()) {
    final FontLoader l = FontLoader('MaterialIcons');
    l.addFont(
      Future<ByteData>.value(ByteData.sublistView(icons.readAsBytesSync())),
    );
    await l.load();
  }
  const Map<String, List<String>> families = <String, List<String>>{
    'Lucide': <String>['assets/icons/lucide.ttf'],
    'InstrumentSans': <String>['assets/fonts/InstrumentSans.ttf'],
    'SpaceGrotesk': <String>['assets/fonts/SpaceGrotesk.ttf'],
    'PublicSans': <String>['assets/fonts/PublicSans.ttf'],
    'IBMPlexMono': <String>[
      'assets/fonts/IBMPlexMono-Regular.ttf',
      'assets/fonts/IBMPlexMono-Medium.ttf',
    ],
  };
  for (final MapEntry<String, List<String>> e in families.entries) {
    final FontLoader loader = FontLoader(e.key);
    for (final String path in e.value) {
      final File f = File(path);
      if (f.existsSync()) {
        loader.addFont(
          Future<ByteData>.value(ByteData.sublistView(f.readAsBytesSync())),
        );
      }
    }
    await loader.load();
  }
}

void main() {
  setUpAll(_loadFonts);

  final DateTime now = DateTime.utc(2026, 8, 25, 9);

  NotificationItem n(String pkg, String title, String body, int minsAgo) =>
      NotificationItem(
        id: '$pkg-$title',
        packageName: pkg,
        title: title,
        body: body,
        timestamp: now.subtract(Duration(minutes: minsAgo)),
      );

  Future<void> pumpCentre(
    WidgetTester tester,
    ThemeData theme,
    List<NotificationItem> items, {
    LoadStatus status = LoadStatus.ready,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1100, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: DeskWallpaper(
            child: NotificationCenter(
              notifications: items,
              status: status,
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
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  testWidgets('notification centre, grouped', (WidgetTester tester) async {
    await pumpCentre(tester, DexTheme.dark(), <NotificationItem>[
      n('com.demo.messages', 'Priya', 'Are you still coming over?', 3),
      n('com.demo.messages', 'Dad', 'Call me when you get a chance', 41),
      n('com.demo.calendar', 'Standup in 10 minutes', 'Design room', 8),
    ]);
    await expectLater(
      find.byType(NotificationCenter),
      matchesGoldenFile('goldens/notifications_dark.png'),
    );
  });

  testWidgets('notification centre, access refused', (
    WidgetTester tester,
  ) async {
    // The empty and blocked states are different problems with different
    // answers, so they must not look the same.
    await pumpCentre(
      tester,
      DexTheme.dark(),
      const <NotificationItem>[],
      status: LoadStatus.unavailable,
    );
    await expectLater(
      find.byType(NotificationCenter),
      matchesGoldenFile('goldens/notifications_blocked_dark.png'),
    );
  });
}
