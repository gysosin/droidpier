import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_android_dex/ui/apps/app_glyph.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';

/// The desk grid rebuilds on every telemetry tick. If AppGlyph handed
/// Image.memory a fresh byte buffer each build, the image cache missed every
/// time, the PNG re-decoded, and the icon went blank mid-decode — the desk-wide
/// icon flicker. The provider must be stable across rebuilds.
void main() {
  // A real 1x1 PNG so Image can decode it.
  final List<int> onePx = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9'
    'awAAAABJRU5ErkJggg==',
  );

  const app = AndroidApplication(
    packageName: 'com.example.flicker',
    label: 'Flicker',
  );

  ImageProvider providerIn(WidgetTester tester) {
    final Image image = tester.widget<Image>(find.byType(Image));
    return image.image;
  }

  testWidgets('the icon provider is identical across rebuilds', (
    WidgetTester tester,
  ) async {
    final withIcon = AndroidApplication(
      packageName: app.packageName,
      label: app.label,
      iconPng: onePx,
    );

    Widget frame() => MaterialApp(
      theme: DexTheme.dark(),
      home: Scaffold(body: AppGlyph(app: withIcon, size: 48)),
    );

    await tester.pumpWidget(frame());
    final ImageProvider first = providerIn(tester);

    // Force a full rebuild, the way a telemetry snapshot does.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(frame());
    final ImageProvider second = providerIn(tester);

    expect(
      identical(first, second),
      isTrue,
      reason: 'a rebuild must reuse the cached provider, not re-decode the PNG',
    );
  });

  testWidgets('an app with no icon falls back to a lettered tile', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: DexTheme.dark(),
        home: const Scaffold(body: AppGlyph(app: app, size: 48)),
      ),
    );
    expect(find.byType(Image), findsNothing);
    expect(find.text('F'), findsOneWidget);
  });
}
