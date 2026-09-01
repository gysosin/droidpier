import 'package:flutter_test/flutter_test.dart';
import 'package:open_dex_api/open_dex_api.dart';
import 'package:open_android_dex/ui/apps/app_ranking.dart';

/// Drawer search ranking, as pure functions.
///
/// A real device reports on the order of eighty to four hundred applications,
/// so the drawer is a finder, not a browser. The old behaviour was a `contains`
/// match sorted alphabetically, which put "Software Update" above "WhatsApp"
/// for the query "wa" — the case that motivated all of this.
void main() {
  AndroidApplication app(String label, {String? pkg, bool system = false}) =>
      AndroidApplication(
        label: label,
        packageName: pkg ?? 'com.example.${label.toLowerCase().replaceAll(' ', '')}',
        isSystemApp: system,
      );

  final List<AndroidApplication> catalogue = <AndroidApplication>[
    app('Software Update', system: true),
    app('WhatsApp', pkg: 'com.whatsapp'),
    app('Google Maps', pkg: 'com.google.android.apps.maps'),
    app('Calculator', system: true),
    app('Camera', system: true),
  ];

  List<String> labels(List<AndroidApplication> l) =>
      l.map((AndroidApplication a) => a.label).toList();

  group('match quality', () {
    test('a prefix outranks a later match', () {
      // The case the whole item exists for.
      final List<AndroidApplication> r = rankApps(catalogue, 'wa');
      expect(r, isNotEmpty);
      expect(r.first.label, 'WhatsApp');
    });

    test('matches the start of any word, not just the first', () {
      // "Google Maps" should be reachable by typing what you think of it as.
      final List<AndroidApplication> r = rankApps(catalogue, 'maps');
      expect(r.first.label, 'Google Maps');
    });

    test('matches scattered letters as a subsequence', () {
      final List<AndroidApplication> r = rankApps(catalogue, 'gmp');
      expect(labels(r), contains('Google Maps'));
    });

    test('a word-start match outranks a scattered one', () {
      // 'ca' starts Calculator and Camera, and appears scattered elsewhere.
      final List<AndroidApplication> r = rankApps(catalogue, 'ca');
      expect(labels(r).take(2), containsAll(<String>['Calculator', 'Camera']));
    });

    test('an empty query returns everything, alphabetically', () {
      final List<AndroidApplication> r = rankApps(catalogue, '');
      expect(r.length, catalogue.length);
      expect(labels(r), <String>[
        'Calculator',
        'Camera',
        'Google Maps',
        'Software Update',
        'WhatsApp',
      ]);
    });

    test('a query matching nothing returns nothing', () {
      expect(rankApps(catalogue, 'zzzzq'), isEmpty);
    });

    test('the package name is searchable but ranks below the label', () {
      final List<AndroidApplication> r = rankApps(catalogue, 'whatsapp');
      expect(r.first.label, 'WhatsApp');
    });

    test('initials match a run-together name', () {
      // "wa" does not occur in "WhatsApp" as a substring at all; the capitals
      // are the only word boundary it has.
      expect(rankApps(catalogue, 'wa').first.label, 'WhatsApp');
    });

    test('initials match across words', () {
      expect(rankApps(catalogue, 'gm').first.label, 'Google Maps');
    });
  });

  group('launch history weighting', () {
    test('a frequently launched app rises above an equal match', () {
      // Camera and Calculator both start with "ca". Habit breaks the tie.
      // Unweighted, Camera leads: both are prefix matches and the shorter
      // label wins the tie.
      final List<AndroidApplication> plain = rankApps(catalogue, 'ca');
      expect(plain.first.label, 'Camera');

      final List<AndroidApplication> weighted = rankApps(
        catalogue,
        'ca',
        history: <String, AppLaunchStats>{
          'com.example.calculator': const AppLaunchStats(
            count: 40,
            lastLaunchedMs: 2000,
          ),
        },
        now: 2000,
      );
      expect(
        weighted.first.label,
        'Calculator',
        reason: 'habit should reorder an otherwise even match',
      );
    });

    test('recency breaks a tie between equally used apps', () {
      final List<AndroidApplication> r = rankApps(
        catalogue,
        'ca',
        history: <String, AppLaunchStats>{
          'com.example.calculator': const AppLaunchStats(
            count: 5,
            lastLaunchedMs: 1000,
          ),
          'com.example.camera': const AppLaunchStats(
            count: 5,
            lastLaunchedMs: 9000,
          ),
        },
        now: 10000,
      );
      expect(r.first.label, 'Camera');
    });

    test('history never promotes a non-match', () {
      // Habit reorders results; it must not invent them.
      final List<AndroidApplication> r = rankApps(
        catalogue,
        'wa',
        history: <String, AppLaunchStats>{
          'com.example.calculator': const AppLaunchStats(
            count: 999,
            lastLaunchedMs: 9999,
          ),
        },
      );
      expect(labels(r), isNot(contains('Calculator')));
    });

    test('history naming an uninstalled package is ignored', () {
      final List<AndroidApplication> r = rankApps(
        catalogue,
        'ca',
        history: <String, AppLaunchStats>{
          'com.gone.forever': const AppLaunchStats(
            count: 99,
            lastLaunchedMs: 9999,
          ),
        },
      );
      expect(r, isNotEmpty);
    });
  });

  group('cost', () {
    test('scores a large catalogue without pathological slowness', () {
      // Runs on every keystroke, so a per-item regex or repeated lowercasing
      // would be felt. Not a benchmark, just a tripwire.
      final List<AndroidApplication> many = <AndroidApplication>[
        for (int i = 0; i < 400; i++) app('Application $i'),
      ];
      final Stopwatch sw = Stopwatch()..start();
      for (int i = 0; i < 20; i++) {
        rankApps(many, 'app');
      }
      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(500));
    });
  });
}
