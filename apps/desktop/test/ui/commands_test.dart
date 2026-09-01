import 'package:flutter_test/flutter_test.dart';
import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_android_dex/ui/shell/commands.dart';

/// The command catalogue.
///
/// One list assembled from what the shell can actually do right now, so the
/// palette can never offer something that does not work.
void main() {
  const List<AndroidApplication> apps = <AndroidApplication>[
    AndroidApplication(packageName: 'com.whatsapp', label: 'WhatsApp'),
    AndroidApplication(
      packageName: 'com.example.settings',
      label: 'Settings',
      isSystemApp: true,
    ),
  ];

  const List<WindowSessionState> windows = <WindowSessionState>[
    WindowSessionState(
      id: 'w1',
      application: AndroidApplication(
        packageName: 'com.google.android.youtube',
        label: 'YouTube',
      ),
      status: WindowSessionStatus.streaming,
      geometry: WindowGeometry(x: 0, y: 0, width: 640, height: 480),
    ),
  ];

  List<DexCommand> build({
    List<AndroidApplication> applications = apps,
    List<WindowSessionState> openWindows = windows,
    List<DexCommandEntry> shell = const <DexCommandEntry>[],
    void Function(String)? onLaunch,
    void Function(String)? onFocusWindow,
  }) => buildCommands(
    applications: applications,
    windows: openWindows,
    shellEntries: shell,
    onLaunchApplication: onLaunch ?? (_) {},
    onFocusWindow: onFocusWindow ?? (_) {},
  );

  test('offers every installed application', () {
    final List<DexCommand> all = build();
    final Iterable<DexCommand> appCommands =
        all.where((DexCommand c) => c.group == DexCommandGroup.app);
    expect(appCommands.length, apps.length);
    expect(
      appCommands.map((DexCommand c) => c.title),
      containsAll(<String>['WhatsApp', 'Settings']),
    );
  });

  test('offers every open window, and says which they are', () {
    final List<DexCommand> all = build();
    final DexCommand window = all.firstWhere(
      (DexCommand c) => c.group == DexCommandGroup.window,
    );
    expect(window.title, contains('YouTube'));
  });

  test('an app command launches that package', () {
    final List<String> launched = <String>[];
    final List<DexCommand> all = build(onLaunch: launched.add);
    all
        .firstWhere((DexCommand c) => c.title == 'WhatsApp')
        .run();
    expect(launched, <String>['com.whatsapp']);
  });

  test('a window command focuses that window', () {
    final List<String> focused = <String>[];
    final List<DexCommand> all = build(onFocusWindow: focused.add);
    all
        .firstWhere((DexCommand c) => c.group == DexCommandGroup.window)
        .run();
    expect(focused, <String>['w1']);
  });

  test('shell entries are carried through', () {
    final List<String> ran = <String>[];
    final List<DexCommand> all = build(
      shell: <DexCommandEntry>[
        DexCommandEntry(title: 'Open settings', run: () => ran.add('settings')),
      ],
    );
    all.firstWhere((DexCommand c) => c.title == 'Open settings').run();
    expect(ran, <String>['settings']);
  });

  test('every command has a stable id, and no two collide', () {
    final List<DexCommand> all = build(
      shell: <DexCommandEntry>[
        DexCommandEntry(title: 'Open settings', run: () {}),
      ],
    );
    final Set<String> ids = all.map((DexCommand c) => c.id).toSet();
    expect(ids.length, all.length, reason: 'ids must be unique');
    for (final DexCommand c in all) {
      expect(c.id, isNotEmpty);
    }
  });

  test('with no phone connected the catalogue is still valid', () {
    // Someone opening the palette before connecting must not meet a crash or a
    // list of commands that cannot run.
    final List<DexCommand> all = build(
      applications: const <AndroidApplication>[],
      openWindows: const <WindowSessionState>[],
    );
    expect(all, isEmpty);
  });

  group('searching the catalogue', () {
    test('finds a command by name', () {
      final List<DexCommand> all = build();
      final List<DexCommand> hits = searchCommands(all, 'whats');
      expect(hits.first.title, 'WhatsApp');
    });

    test('finds a command by its initials', () {
      final List<DexCommand> all = build(
        shell: <DexCommandEntry>[
          DexCommandEntry(title: 'Toggle stream diagnostics', run: () {}),
        ],
      );
      expect(searchCommands(all, 'tsd').first.title,
          'Toggle stream diagnostics');
    });

    test('keywords find a command the title does not name', () {
      // "dark mode" should find the theme command even though the title says
      // Theme, because that is what a person types.
      final List<DexCommand> all = build(
        shell: <DexCommandEntry>[
          DexCommandEntry(
            title: 'Use the dark theme',
            keywords: <String>['appearance', 'night'],
            run: () {},
          ),
        ],
      );
      expect(searchCommands(all, 'night'), isNotEmpty);
    });

    test('an empty query returns everything', () {
      final List<DexCommand> all = build();
      expect(searchCommands(all, '').length, all.length);
    });

    test('a query matching nothing returns nothing', () {
      expect(searchCommands(build(), 'zzzzq'), isEmpty);
    });
  });
}
