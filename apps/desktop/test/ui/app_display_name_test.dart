import 'package:flutter_test/flutter_test.dart';
import 'package:open_android_dex/ui/util/app_display_name.dart';

/// The derived name is a stopgap for the agent sending `label = packageName`.
/// These record both what it gets right and what it cannot.
void main() {
  test('detects a label that is only the package name', () {
    expect(
      isPlaceholderLabel('com.android.settings', 'com.android.settings'),
      isTrue,
    );
    expect(isPlaceholderLabel('Settings', 'com.android.settings'), isFalse);
  });

  test('derives a readable name from common package shapes', () {
    expect(displayNameFor('com.android.settings'), 'Settings');
    expect(displayNameFor('com.spotify.music'), 'Music');
    expect(displayNameFor('com.whatsapp'), 'Whatsapp');
    // Trailing noise segments are skipped for the one before them.
    expect(displayNameFor('com.example.myapp.android'), 'Myapp');
    // camelCase and underscores become words.
    expect(displayNameFor('com.example.mediaPlayer'), 'Media Player');
    expect(displayNameFor('com.example.file_manager'), 'File Manager');
  });

  test('is honestly wrong where a package cannot say the name', () {
    // Gmail's package gives "Gm". Nothing can derive "Gmail" from it, which is
    // exactly why the drawer keeps the package name visible beneath the guess
    // rather than replacing it.
    expect(displayNameFor('com.google.android.gm'), 'Gm');
  });

  test('never returns empty for odd input', () {
    expect(displayNameFor('singleword'), isNotEmpty);
    expect(displayNameFor(''), isNotNull);
  });
}
