import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_android_dex/ui/apps/app_drawer.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';

/// Pinning, from the drawer's right-click menu.
void main() {
  const List<AndroidApplication> apps = <AndroidApplication>[
    AndroidApplication(packageName: 'com.whatsapp', label: 'WhatsApp'),
    AndroidApplication(packageName: 'com.example.wallet', label: 'Wallet'),
  ];

  Future<void> pumpDrawer(
    WidgetTester tester, {
    List<String> pinned = const <String>[],
    ValueChanged<List<String>>? onPinnedChanged,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: DexTheme.dark(),
        home: Scaffold(
          body: AppDrawer(
            status: LoadStatus.ready,
            applications: apps,
            onLaunch: (_) {},
            onRefresh: () {},
            onDismiss: () {},
            pinnedPackages: pinned,
            onPinnedChanged: onPinnedChanged ?? (_) {},
          ),
        ),
      ),
    );
    await tester.pump();
    for (int i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  testWidgets('right-clicking a tile offers to pin it', (
    WidgetTester tester,
  ) async {
    List<String>? saved;
    await pumpDrawer(tester, onPinnedChanged: (List<String> p) => saved = p);

    await tester.tapAt(tester.getCenter(find.text('Wallet')), buttons: 2);
    await tester.pumpAndSettle();
    expect(find.text('Pin to top'), findsOneWidget);

    await tester.tap(find.text('Pin to top'));
    await tester.pumpAndSettle();
    expect(saved, <String>['com.example.wallet']);
  });

  testWidgets('an already pinned tile offers to unpin', (
    WidgetTester tester,
  ) async {
    List<String>? saved;
    await pumpDrawer(
      tester,
      pinned: <String>['com.example.wallet'],
      onPinnedChanged: (List<String> p) => saved = p,
    );

    // The pinned section renders the same app again, so target the one inside
    // the browsing grid by taking the last match.
    await tester.tapAt(tester.getCenter(find.text('Wallet').last), buttons: 2);
    await tester.pumpAndSettle();
    expect(find.text('Unpin from top'), findsOneWidget);

    await tester.tap(find.text('Unpin from top'));
    await tester.pumpAndSettle();
    expect(saved, isEmpty);
  });

  testWidgets('the pinned section appears only when something is pinned', (
    WidgetTester tester,
  ) async {
    await pumpDrawer(tester);
    expect(
      find.text('PINNED TO TOP'),
      findsNothing,
      reason: 'an empty section header is worse than no section',
    );

    await pumpDrawer(tester, pinned: <String>['com.whatsapp']);
    expect(find.text('PINNED TO TOP'), findsOneWidget);
  });

  testWidgets('a pin naming an uninstalled package is skipped', (
    WidgetTester tester,
  ) async {
    // Uninstalling an app should not leave a broken tile behind.
    await pumpDrawer(tester, pinned: <String>['com.gone.forever']);
    expect(find.text('PINNED TO TOP'), findsNothing);
  });
}
