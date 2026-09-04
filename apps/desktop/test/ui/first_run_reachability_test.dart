import 'package:flutter_test/flutter_test.dart';
import 'package:open_android_dex/bootstrap/desk_preferences.dart';

/// The first-run tour has to be able to happen.
///
/// It is 214 lines with its own test file covering every step, and it could
/// never appear in the product: `AppShell.tourCompleted` defaults to true,
/// `lib/main.dart` never passed it, and there was nowhere to persist it. A
/// feature that is fully tested and permanently off is worse than one that
/// does not exist — the tests say it works.
void main() {
  test('a fresh install has not seen the tour', () {
    const DeskPreferencesData fresh = DeskPreferencesData();
    expect(fresh.tourCompleted, isFalse);
  });

  test('finishing the tour survives a restart', () {
    const DeskPreferencesData fresh = DeskPreferencesData();
    final DeskPreferencesData done = fresh.copyWith(tourCompleted: true);
    expect(done.tourCompleted, isTrue);

    final DeskPreferencesData reloaded = DeskPreferencesData.fromJson(
      done.toJson(),
    );
    expect(
      reloaded.tourCompleted,
      isTrue,
      reason: 'a tour that reappears every launch is worse than none',
    );
  });

  test('a corrupt value degrades to showing the tour', () {
    final DeskPreferencesData loaded = DeskPreferencesData.fromJson(
      <String, Object?>{'tourCompleted': 'yes please'},
    );
    // Showing it once too often is recoverable; silently never showing it is
    // the failure this whole file exists to prevent.
    expect(loaded.tourCompleted, isFalse);
  });
}
