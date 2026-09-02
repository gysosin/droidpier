import 'package:flutter_test/flutter_test.dart';
import 'package:open_android_dex/ui/desk/volume_labels.dart';

/// The volume rows were labelled with Android's raw stream keys — "music",
/// "ring" — printed straight from the map the agent sends. They are internal
/// identifiers, not words anyone uses for the thing they control.
void main() {
  test('the four streams Android actually sends are named', () {
    // These are the only keys the agent emits.
    expect(volumeStreamLabel('music'), 'Media');
    expect(volumeStreamLabel('ring'), 'Ringtone');
    expect(volumeStreamLabel('alarm'), 'Alarm');
    expect(volumeStreamLabel('notification'), 'Notifications');
  });

  test('an unknown stream is tidied, never dropped', () {
    // A key nobody anticipated is still a control the person can move, so it
    // gets a readable label rather than being hidden or left lowercase.
    expect(volumeStreamLabel('voice_call'), 'Voice call');
    expect(volumeStreamLabel('system'), 'System');
  });

  test('an empty key does not produce an empty label', () {
    expect(volumeStreamLabel('').trim(), isNotEmpty);
  });

  test('ordering puts media first and leaves unknowns last', () {
    // Alphabetical put "alarm" above "music", which is not the order anyone
    // reaches for these in.
    final List<String> sorted = sortVolumeStreams(<String>[
      'ring',
      'alarm',
      'music',
      'zzz_unknown',
      'notification',
    ]);
    expect(sorted, <String>[
      'music',
      'ring',
      'notification',
      'alarm',
      'zzz_unknown',
    ]);
  });
}
