import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_android_dex/ui/apps/app_drawer.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';
import 'package:open_android_dex/ui/theme/glass.dart';
import 'package:open_dex_api/open_dex_api.dart';

/// The launcher card must be the size of what it holds.
///
/// It used to be a fixed full-height panel, so three apps sat in the corner of
/// roughly 850 px of empty glass. Search results were then bottom-anchored to
/// hug the field and stop the gap appearing between the query and its results
/// — which did not remove the void, it moved it to the top of the card.
///
/// A card that hugs its content has neither gap, at any number of apps.
void main() {
  const List<AndroidApplication> few = <AndroidApplication>[
    AndroidApplication(packageName: 'com.android.chrome', label: 'Chrome'),
    AndroidApplication(packageName: 'com.spotify.music', label: 'Spotify'),
    AndroidApplication(packageName: 'com.google.youtube', label: 'YouTube'),
  ];

  final List<AndroidApplication> many = <AndroidApplication>[
    for (int i = 0; i < 60; i++)
      AndroidApplication(packageName: 'com.example.a$i', label: 'App $i'),
    // Two distinctly-named apps, so a query can select exactly two of sixty.
    const AndroidApplication(packageName: 'com.example.zebra', label: 'Zebra'),
    const AndroidApplication(packageName: 'com.example.zenith', label: 'Zenith'),
  ];

  Future<Size> pumpDrawer(
    WidgetTester tester,
    List<AndroidApplication> apps, {
    String query = '',
  }) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: DexTheme.dark(),
        home: Scaffold(
          body: AppDrawer(
            applications: apps,
            status: LoadStatus.ready,
            onLaunch: (_) {},
            onDismiss: () {},
            onRefresh: () {},
          ),
        ),
      ),
    );
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    if (query.isNotEmpty) {
      await tester.enterText(find.byType(TextField), query);
      for (int i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
    }

    final Finder card = find
        .ancestor(of: find.byType(TextField), matching: find.byType(GlassPanel))
        .first;
    return tester.getSize(card);
  }

  testWidgets('three apps do not get a full-height card', (
    WidgetTester tester,
  ) async {
    final Size size = await pumpDrawer(tester, few);

    // One row of tiles plus a header and the search field. Nothing like the
    // 850 px it used to take.
    expect(
      size.height,
      lessThan(400),
      reason: 'a card holding one row of apps must not fill the screen',
    );
  });

  testWidgets('two search results sit under the field, not across a void', (
    WidgetTester tester,
  ) async {
    final Size size = await pumpDrawer(tester, many, query: 'ze');

    expect(
      size.height,
      lessThan(400),
      reason: 'a two-row result set must not stretch the card',
    );

    // And the results must read downward from the field, not upward into it.
    final double field = tester.getCenter(find.byType(TextField)).dy;
    final double firstResult = tester.getCenter(find.text('Zebra')).dy;
    expect(
      firstResult,
      greaterThan(field),
      reason: 'results belong below the query, as every launcher search has it',
    );
  });

  testWidgets('a full phone of apps still fits and scrolls', (
    WidgetTester tester,
  ) async {
    final Size size = await pumpDrawer(tester, many);

    expect(size.height, lessThanOrEqualTo(800));
    expect(tester.takeException(), isNull);
  });
}
