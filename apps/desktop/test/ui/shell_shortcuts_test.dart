import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_android_dex/ui/shell/shortcuts.dart';

/// The shortcut registry, tested as plain data.
///
/// The point of lifting `_onKey` into a list is that dispatch becomes something
/// you can assert without pumping a widget, a window, or a facade. If any test
/// in this file needs a `WidgetTester`, the registry has stopped being data.
void main() {
  /// A stroke with no modifiers held.
  DexKeyStroke plain(LogicalKeyboardKey k) => DexKeyStroke(k);

  group('DexKeyStroke matching', () {
    test('matches its own key with no modifiers', () {
      final DexKeyStroke s = plain(LogicalKeyboardKey.f11);
      expect(
        s.matches(
          LogicalKeyboardKey.f11,
          control: false,
          shift: false,
          alt: false,
        ),
        isTrue,
      );
    });

    test('a modifier held that the stroke does not want is not a match', () {
      // Ctrl+Space must not fire the bare-Space binding, or every accelerator
      // becomes ambiguous the moment a modifier is down.
      final DexKeyStroke s = plain(LogicalKeyboardKey.space);
      expect(
        s.matches(
          LogicalKeyboardKey.space,
          control: true,
          shift: false,
          alt: false,
        ),
        isFalse,
      );
    });

    test('a modifier the stroke wants but is not held is not a match', () {
      final DexKeyStroke s = DexKeyStroke(
        LogicalKeyboardKey.keyD,
        control: true,
        shift: true,
      );
      expect(
        s.matches(
          LogicalKeyboardKey.keyD,
          control: true,
          shift: false,
          alt: false,
        ),
        isFalse,
      );
    });

    test('a stroke marked anyModifiers matches whatever is held', () {
      // Escape must still cancel the window switcher while Alt is held down —
      // that is exactly how a person's hand sits mid-Alt+Tab, and the shell
      // has always accepted it. A stroke that demanded no modifiers would
      // silently break cancelling a switch.
      const DexKeyStroke s = DexKeyStroke(
        LogicalKeyboardKey.escape,
        anyModifiers: true,
      );
      expect(
        s.matches(
          LogicalKeyboardKey.escape,
          control: false,
          shift: false,
          alt: true,
        ),
        isTrue,
      );
      expect(
        s.matches(
          LogicalKeyboardKey.escape,
          control: false,
          shift: false,
          alt: false,
        ),
        isTrue,
      );
    });

    test('anyModifiers still does not match a different key', () {
      const DexKeyStroke s = DexKeyStroke(
        LogicalKeyboardKey.escape,
        anyModifiers: true,
      );
      expect(
        s.matches(
          LogicalKeyboardKey.keyA,
          control: false,
          shift: false,
          alt: false,
        ),
        isFalse,
      );
    });

    test('renders a human label for the cheat sheet', () {
      // Story 1.2 renders this string; it must come from the stroke rather
      // than a second hand-written list.
      final DexKeyStroke s = DexKeyStroke(
        LogicalKeyboardKey.keyD,
        control: true,
        shift: true,
      );
      expect(s.label, 'Ctrl+Shift+D');
    });
  });

  group('dispatch', () {
    test('returns the first entry whose stroke and condition both hold', () {
      final List<String> fired = <String>[];
      final List<DexShortcut> registry = <DexShortcut>[
        DexShortcut(
          stroke: plain(LogicalKeyboardKey.escape),
          label: 'Leave fullscreen',
          group: DexShortcutGroup.windows,
          when: () => false,
          run: () => fired.add('fullscreen'),
        ),
        DexShortcut(
          stroke: plain(LogicalKeyboardKey.escape),
          label: 'Close diagnostics',
          group: DexShortcutGroup.diagnostics,
          when: () => true,
          run: () => fired.add('diagnostics'),
        ),
      ];

      final DexShortcut? hit = matchShortcut(
        registry,
        LogicalKeyboardKey.escape,
        control: false,
        shift: false,
        alt: false,
      );
      hit?.run();

      expect(hit, isNotNull);
      expect(fired, <String>['diagnostics']);
    });

    test('an earlier entry wins when both conditions hold', () {
      // This is the Escape ladder in miniature: fullscreen outranks
      // diagnostics, so with both open Escape must leave fullscreen first.
      final List<String> fired = <String>[];
      final List<DexShortcut> registry = <DexShortcut>[
        DexShortcut(
          stroke: plain(LogicalKeyboardKey.escape),
          label: 'Leave fullscreen',
          group: DexShortcutGroup.windows,
          when: () => true,
          run: () => fired.add('fullscreen'),
        ),
        DexShortcut(
          stroke: plain(LogicalKeyboardKey.escape),
          label: 'Close diagnostics',
          group: DexShortcutGroup.diagnostics,
          when: () => true,
          run: () => fired.add('diagnostics'),
        ),
      ];

      matchShortcut(
        registry,
        LogicalKeyboardKey.escape,
        control: false,
        shift: false,
        alt: false,
      )?.run();

      expect(fired, <String>['fullscreen']);
    });

    test('no match returns null so the caller can forward the key', () {
      // The shell forwards unclaimed keys to the focused Android window. A
      // registry that swallowed everything would stop the phone receiving
      // any typing at all.
      final List<DexShortcut> registry = <DexShortcut>[
        DexShortcut(
          stroke: plain(LogicalKeyboardKey.escape),
          label: 'Close diagnostics',
          group: DexShortcutGroup.diagnostics,
          when: () => true,
          run: () {},
        ),
      ];

      expect(
        matchShortcut(
          registry,
          LogicalKeyboardKey.keyA,
          control: false,
          shift: false,
          alt: false,
        ),
        isNull,
      );
    });

    test('an entry whose condition is false does not consume the key', () {
      final List<DexShortcut> registry = <DexShortcut>[
        DexShortcut(
          stroke: plain(LogicalKeyboardKey.escape),
          label: 'Close diagnostics',
          group: DexShortcutGroup.diagnostics,
          when: () => false,
          run: () {},
        ),
      ];

      expect(
        matchShortcut(
          registry,
          LogicalKeyboardKey.escape,
          control: false,
          shift: false,
          alt: false,
        ),
        isNull,
      );
    });
  });

  group('the built registry', () {
    ShellShortcutHooks hooks({required bool keyboardIsFree}) =>
        ShellShortcutHooks(
          openPalette: () {},
  isPaletteOpen: () => false,
  closePalette: () {},
  openSheet: () {},
          isSheetOpen: () => false,
          closeSheet: () {},
          keyboardIsFree: () => keyboardIsFree,
          toggleDiagnostics: () {},
          toggleDrawer: () {},
          toggleFullscreen: () {},
          cycleFocus: () {},
          cycleFocusBack: () {},
          isFullscreen: () => false,
          exitFullscreen: () {},
          isDiagnosticsOpen: () => false,
          closeDiagnostics: () {},
          isSwitcherOpen: () => false,
          cancelSwitch: () {},
          isDeskSurfaceOpen: () => false,
          closeDeskSurfaces: () {},
          isConnectOpen: () => false,
          closeConnect: () {},
        );

    test('bare ? opens the sheet when nothing else owns the keyboard', () {
      final DexShortcut? hit = matchShortcut(
        buildShortcuts(hooks(keyboardIsFree: true)),
        LogicalKeyboardKey.question,
        control: false,
        shift: true,
        alt: false,
      );
      expect(hit, isNotNull);
      expect(hit!.label, 'Show keyboard shortcuts');
    });

    test('bare ? is ignored while a desk surface owns the keyboard', () {
      // The guard that stops a question mark typed into the launcher search
      // from throwing a help panel over what you were searching for.
      expect(
        matchShortcut(
          buildShortcuts(hooks(keyboardIsFree: false)),
          LogicalKeyboardKey.question,
          control: false,
          shift: true,
          alt: false,
        ),
        isNull,
      );
    });

    test('Ctrl+/ and F1 open the sheet regardless of the guard', () {
      // Deliberate: an explicit chord is unambiguous, so it does not need the
      // bare key's protection and must work even while typing.
      for (final DexKeyStroke stroke in <DexKeyStroke>[
        const DexKeyStroke(LogicalKeyboardKey.slash, control: true),
        const DexKeyStroke(LogicalKeyboardKey.f1),
      ]) {
        final DexShortcut? hit = matchShortcut(
          buildShortcuts(hooks(keyboardIsFree: false)),
          stroke.key,
          control: stroke.control,
          shift: false,
          alt: false,
        );
        expect(hit?.label, 'Show keyboard shortcuts', reason: stroke.label);
      }
    });

    test('every entry carries a label and a rendered stroke', () {
      // The cheat sheet renders both; an empty one would show a blank row.
      for (final DexShortcut s in buildShortcuts(hooks(keyboardIsFree: true))) {
        expect(s.label, isNotEmpty);
        expect(s.stroke.label, isNotEmpty, reason: s.label);
      }
    });
  });
}
