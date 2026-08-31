import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_android_dex/ui/permissions/permission_panel.dart';
import 'package:open_android_dex/ui/theme/dex_theme.dart';
import 'package:open_dex_api/open_dex_api.dart';

/// The backend can open the notification-access screen and no other. A single
/// panel-wide callback would put a "Manage"/"Open on phone" button on every
/// row and fail on all but one, which is the exact failure this panel already
/// documents for `onGrant`.
void main() {
  Future<void> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: DexTheme.dark(),
        home: Scaffold(
          body: PermissionPanel(
            permissions: const PermissionState(
              status: LoadStatus.ready,
              grants: <String, PermissionGrant>{
                'notifications': PermissionGrant.requiresSettings,
                'media': PermissionGrant.requiresSettings,
              },
            ),
            onOpenSettings: (String capability) =>
                capability == 'notifications' ? () {} : null,
          ),
        ),
      ),
    );
    await tester.pump();
    for (int i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  testWidgets('only the capability the backend can open gets a button', (
    WidgetTester tester,
  ) async {
    await pump(tester);
    expect(
      find.text('Open on phone'),
      findsOneWidget,
      reason: 'notifications can be opened; media cannot',
    );
  });

  testWidgets('the capability it cannot open says what to do instead', (
    WidgetTester tester,
  ) async {
    await pump(tester);
    expect(
      find.text('Allow on the phone'),
      findsOneWidget,
      reason: 'a row with no action must still tell the person the way out',
    );
  });
}
