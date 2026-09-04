@Tags(<String>['golden'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_android_dex/ui/apps/app_drawer.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';

/// Every state the drawer can be in, as pixels.
///
/// The happy path had goldens; loading, empty, no-match, ranked results and the
/// pinned row did not. Failure paths are where a beta is judged.
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
    'SpaceGrotesk': <String>['assets/fonts/SpaceGrotesk.ttf'],
    'PublicSans': <String>['assets/fonts/PublicSans.ttf'],
    'IBMPlexMono': <String>['assets/fonts/IBMPlexMono-Regular.ttf'],
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

const List<AndroidApplication> _apps = <AndroidApplication>[
  AndroidApplication(packageName: 'com.whatsapp', label: 'WhatsApp'),
  AndroidApplication(packageName: 'com.example.wallet', label: 'Wallet'),
  AndroidApplication(
    packageName: 'com.example.settings',
    label: 'Settings',
    isSystemApp: true,
  ),
];

void main() {
  setUpAll(_loadFonts);

  Future<void> pump(
    WidgetTester tester, {
    required LoadStatus status,
    required List<AndroidApplication> apps,
    List<String> pinned = const <String>[],
  }) async {
    await tester.binding.setSurfaceSize(const Size(1100, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: DexTheme.dark(),
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: AppDrawer(
            status: status,
            applications: apps,
            onLaunch: (_) {},
            onRefresh: () {},
            onDismiss: () {},
            pinnedPackages: pinned,
          ),
        ),
      ),
    );
    // Twice: Entrance resolves its stagger during a pump.
    await tester.pump();
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  testWidgets('loading mirrors the grid it will become', (
    WidgetTester tester,
  ) async {
    await pump(
      tester,
      status: LoadStatus.loading,
      apps: const <AndroidApplication>[],
    );
    await expectLater(
      find.byType(AppDrawer),
      matchesGoldenFile('goldens/drawer_loading.png'),
    );
  });

  testWidgets('empty invites an action rather than dead-ending', (
    WidgetTester tester,
  ) async {
    await pump(
      tester,
      status: LoadStatus.ready,
      apps: const <AndroidApplication>[],
    );
    expect(find.text('No apps yet'), findsOneWidget);
    expect(
      find.widgetWithText(OutlinedButton, 'Look again'),
      findsOneWidget,
      reason: 'an empty screen is an invitation to act, never a dead end',
    );
    await expectLater(
      find.byType(AppDrawer),
      matchesGoldenFile('goldens/drawer_empty.png'),
    );
  });

  testWidgets('a query matching nothing offers a way back', (
    WidgetTester tester,
  ) async {
    await pump(tester, status: LoadStatus.ready, apps: _apps);
    await tester.enterText(find.byType(TextField), 'zzzzq');
    await tester.pump();
    for (int i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(find.widgetWithText(OutlinedButton, 'Clear search'), findsOneWidget);
    await expectLater(
      find.byType(AppDrawer),
      matchesGoldenFile('goldens/drawer_no_match.png'),
    );
  });

  testWidgets('ranked results with a selection', (WidgetTester tester) async {
    await pump(tester, status: LoadStatus.ready, apps: _apps);
    await tester.enterText(find.byType(TextField), 'wa');
    await tester.pump();
    for (int i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    // Exactly one row is marked, or the keyboard has nowhere visible to be.
    expect(find.text('Enter'), findsOneWidget);
    await expectLater(
      find.byType(AppDrawer),
      matchesGoldenFile('goldens/drawer_results.png'),
    );
  });

  testWidgets('the pinned row sits above the rest', (
    WidgetTester tester,
  ) async {
    await pump(
      tester,
      status: LoadStatus.ready,
      apps: _apps,
      pinned: const <String>['com.whatsapp'],
    );
    expect(find.text('PINNED'), findsOneWidget);
    await expectLater(
      find.byType(AppDrawer),
      matchesGoldenFile('goldens/drawer_pinned.png'),
    );
  });
}
