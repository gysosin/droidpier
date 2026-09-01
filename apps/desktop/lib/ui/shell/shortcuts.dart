import 'package:flutter/services.dart';

/// Where a shortcut belongs in the cheat sheet.
enum DexShortcutGroup { launcher, windows, session, diagnostics }

/// A key plus the modifiers it needs.
class DexKeyStroke {
  const DexKeyStroke(
    this.key, {
    this.control = false,
    this.shift = false,
    this.alt = false,
    this.anyModifiers = false,
  });

  final LogicalKeyboardKey key;
  final bool control;
  final bool shift;
  final bool alt;

  /// Fires on the key whatever modifiers happen to be held.
  ///
  /// The Escape ladder needs this and is the only thing that should. Escape
  /// arrives mid-Alt+Tab with Alt still physically down — that is how a hand
  /// sits while cycling windows — and demanding a bare Escape there would
  /// silently stop a person cancelling a switch. Accelerators that are
  /// *entered* with a modifier stay exact, or Ctrl+Space would also fire the
  /// bare-Space binding.
  final bool anyModifiers;

  /// Every modifier must agree in both directions.
  ///
  /// A held modifier the stroke does not want fails the match as surely as a
  /// wanted one that is absent — otherwise Ctrl+Space would also fire the bare
  /// Space binding, and every accelerator would be ambiguous the moment a
  /// modifier went down.
  bool matches(
    LogicalKeyboardKey pressed, {
    required bool control,
    required bool shift,
    required bool alt,
  }) {
    if (pressed != key) return false;
    if (anyModifiers) return true;
    return control == this.control &&
        shift == this.shift &&
        alt == this.alt;
  }

  /// How the cheat sheet writes this stroke, e.g. `Ctrl+Shift+D`.
  String get label {
    final StringBuffer b = StringBuffer();
    if (control) b.write('Ctrl+');
    if (shift) b.write('Shift+');
    if (alt) b.write('Alt+');
    b.write(_keyName);
    return b.toString();
  }

  /// `keyLabel` is unhelpful for the non-printing keys — Space renders as an
  /// actual space, which reads as a missing word in the sheet.
  String get _keyName => switch (key) {
    LogicalKeyboardKey.space => 'Space',
    LogicalKeyboardKey.escape => 'Esc',
    LogicalKeyboardKey.tab => 'Tab',
    LogicalKeyboardKey.slash => '/',
    _ => key.keyLabel,
  };
}

/// One app-global accelerator.
class DexShortcut {
  const DexShortcut({
    required this.stroke,
    required this.label,
    required this.group,
    required this.when,
    required this.run,
  });

  final DexKeyStroke stroke;
  final String label;
  final DexShortcutGroup group;
  final bool Function() when;
  final void Function() run;
}

/// The first entry whose stroke matches and whose condition holds, or null.
///
/// Order is the whole mechanism. Escape is not one binding but a ladder —
/// fullscreen, then diagnostics, then the switcher, then the desk surfaces,
/// then connect — and first-match-wins over an ordered list is what reproduces
/// it. A map could not express that at all.
///
/// Returning null rather than a no-op matters: the shell forwards unclaimed
/// keys to the focused Android window, so a registry that swallowed everything
/// would stop the phone receiving any typing.
DexShortcut? matchShortcut(
  List<DexShortcut> registry,
  LogicalKeyboardKey pressed, {
  required bool control,
  required bool shift,
  required bool alt,
}) {
  for (final DexShortcut s in registry) {
    if (s.stroke.matches(
          pressed,
          control: control,
          shift: shift,
          alt: alt,
        ) &&
        s.when()) {
      return s;
    }
  }
  return null;
}

/// What the registry needs from the shell to decide and act.
///
/// Passed as one object rather than a dozen loose callbacks, so adding a
/// shortcut does not change [buildShortcuts]'s signature and every call site
/// with it. Each condition is a function, not a value, because the list is
/// built per key press and must read state as it is *now*.
class ShellShortcutHooks {
  const ShellShortcutHooks({
    required this.openSheet,
    required this.isSheetOpen,
    required this.closeSheet,
    required this.keyboardIsFree,
    required this.toggleDiagnostics,
    required this.toggleDrawer,
    required this.toggleFullscreen,
    required this.cycleFocus,
    required this.isFullscreen,
    required this.exitFullscreen,
    required this.isDiagnosticsOpen,
    required this.closeDiagnostics,
    required this.isSwitcherOpen,
    required this.cancelSwitch,
    required this.isDeskSurfaceOpen,
    required this.closeDeskSurfaces,
    required this.isConnectOpen,
    required this.closeConnect,
  });

  final void Function() openSheet;
  final bool Function() isSheetOpen;
  final void Function() closeSheet;

  /// False while a desk surface or one of our own text fields holds the
  /// keyboard. Guards the bare `?` binding only: a question mark typed into
  /// the launcher search must reach the search box, not open a help panel.
  final bool Function() keyboardIsFree;

  final void Function() toggleDiagnostics;
  final void Function() toggleDrawer;
  final void Function() toggleFullscreen;
  final void Function() cycleFocus;

  final bool Function() isFullscreen;
  final void Function() exitFullscreen;

  final bool Function() isDiagnosticsOpen;
  final void Function() closeDiagnostics;

  final bool Function() isSwitcherOpen;
  final void Function() cancelSwitch;

  final bool Function() isDeskSurfaceOpen;
  final void Function() closeDeskSurfaces;

  final bool Function() isConnectOpen;
  final void Function() closeConnect;
}

bool _always() => true;

/// Every app-global accelerator, in dispatch order.
///
/// Order is the mechanism, not decoration. Escape is a ladder — fullscreen,
/// then diagnostics, then the switcher, then the desk surfaces, then connect —
/// and [matchShortcut] takes the first entry whose condition holds, which is
/// what reproduces it. Reordering these entries reorders the ladder.
///
/// `label` and `group` are what the cheat sheet renders, so they are written
/// for a person rather than as identifiers.
List<DexShortcut> buildShortcuts(ShellShortcutHooks hooks) => <DexShortcut>[
  DexShortcut(
    stroke: const DexKeyStroke(
      LogicalKeyboardKey.keyD,
      control: true,
      shift: true,
    ),
    label: 'Toggle stream diagnostics',
    group: DexShortcutGroup.diagnostics,
    when: _always,
    run: hooks.toggleDiagnostics,
  ),
  DexShortcut(
    stroke: const DexKeyStroke(LogicalKeyboardKey.space, control: true),
    label: 'Toggle the launcher',
    group: DexShortcutGroup.launcher,
    when: _always,
    run: hooks.toggleDrawer,
  ),
  DexShortcut(
    stroke: const DexKeyStroke(LogicalKeyboardKey.f11),
    label: 'Toggle fullscreen',
    group: DexShortcutGroup.windows,
    when: _always,
    run: hooks.toggleFullscreen,
  ),
  DexShortcut(
    stroke: const DexKeyStroke(LogicalKeyboardKey.tab, alt: true),
    label: 'Switch window',
    group: DexShortcutGroup.windows,
    when: _always,
    run: hooks.cycleFocus,
  ),
  DexShortcut(
    stroke: const DexKeyStroke(LogicalKeyboardKey.slash, control: true),
    label: 'Show keyboard shortcuts',
    group: DexShortcutGroup.session,
    when: _always,
    run: hooks.openSheet,
  ),
  DexShortcut(
    stroke: const DexKeyStroke(LogicalKeyboardKey.f1),
    label: 'Show keyboard shortcuts',
    group: DexShortcutGroup.session,
    when: _always,
    run: hooks.openSheet,
  ),
  DexShortcut(
    // `?` is Shift+/ on most layouts, so the modifiers cannot be pinned down.
    // Guarded by [ShellShortcutHooks.keyboardIsFree] instead of by modifiers.
    stroke: const DexKeyStroke(
      LogicalKeyboardKey.question,
      anyModifiers: true,
    ),
    label: 'Show keyboard shortcuts',
    group: DexShortcutGroup.session,
    when: hooks.keyboardIsFree,
    run: hooks.openSheet,
  ),
  // The Escape ladder. One press peels exactly one layer, outermost first.
  DexShortcut(
    stroke: const DexKeyStroke(LogicalKeyboardKey.escape, anyModifiers: true),
    label: 'Leave fullscreen',
    group: DexShortcutGroup.windows,
    when: hooks.isFullscreen,
    run: hooks.exitFullscreen,
  ),
  DexShortcut(
    stroke: const DexKeyStroke(LogicalKeyboardKey.escape, anyModifiers: true),
    label: 'Close the shortcut sheet',
    group: DexShortcutGroup.session,
    // Below fullscreen deliberately: the sheet renders under the fullscreen
    // stage, so dismissing it first would look like Escape did nothing.
    when: hooks.isSheetOpen,
    run: hooks.closeSheet,
  ),
  DexShortcut(
    stroke: const DexKeyStroke(LogicalKeyboardKey.escape, anyModifiers: true),
    label: 'Close diagnostics',
    group: DexShortcutGroup.diagnostics,
    when: hooks.isDiagnosticsOpen,
    run: hooks.closeDiagnostics,
  ),
  DexShortcut(
    stroke: const DexKeyStroke(LogicalKeyboardKey.escape, anyModifiers: true),
    label: 'Cancel the window switcher',
    group: DexShortcutGroup.windows,
    // Cancels the switch rather than committing it, which is the whole reason
    // a person reaches for Escape mid-Alt+Tab.
    when: hooks.isSwitcherOpen,
    run: hooks.cancelSwitch,
  ),
  DexShortcut(
    stroke: const DexKeyStroke(LogicalKeyboardKey.escape, anyModifiers: true),
    label: 'Close the open desk surface',
    group: DexShortcutGroup.session,
    when: hooks.isDeskSurfaceOpen,
    run: hooks.closeDeskSurfaces,
  ),
  DexShortcut(
    stroke: const DexKeyStroke(LogicalKeyboardKey.escape, anyModifiers: true),
    label: 'Close the connection screen',
    group: DexShortcutGroup.session,
    // One layer, so one Escape. Closing it also stops discovery and cancels
    // any pairing — see [ConnectionScreen.dispose].
    when: hooks.isConnectOpen,
    run: hooks.closeConnect,
  ),
];
