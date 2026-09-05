import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:open_dex_api/open_dex_api.dart';

import '../theme/dex_colors.dart';
import '../theme/dex_glass.dart';
import '../theme/dex_theme.dart';
import '../theme/dex_tokens.dart';
import '../util/app_display_name.dart';

/// An Android app's icon, at whatever size the caller needs.
///
/// Shared by the drawer, the phone mirror and the desk grid so an app looks
/// like the same app everywhere. When the backend supplies `iconPng` this is
/// the real launcher icon; until then it is a lettered tile, and the letter is
/// taken from the *displayed* name — taking it from the raw label gave every
/// app "C", because every label was a `com.…` package name.
class AppGlyph extends StatelessWidget {
  const AppGlyph({required this.app, this.size = 40, super.key});

  final AndroidApplication app;
  final double size;

  /// One [MemoryImage] per package, reused across every rebuild.
  ///
  /// `Image.memory` keys the image cache on the byte buffer's *identity*, and
  /// `Uint8List.fromList(png)` produced a fresh buffer on every build. Since the
  /// desk rebuilds on each telemetry tick — many times a second — every rebuild
  /// was a cache miss that re-decoded the PNG, and the icon showed nothing while
  /// it decoded: the whole grid flickered continuously whenever a window
  /// streamed. Caching the provider makes the second build onward a cache hit,
  /// so the icon is decoded once and never blinks.
  static final Map<String, MemoryImage> _providers = <String, MemoryImage>{};

  static MemoryImage _providerFor(AndroidApplication app, List<int> png) {
    final MemoryImage? cached = _providers[app.packageName];
    if (cached != null) return cached;
    final MemoryImage provider = MemoryImage(Uint8List.fromList(png));
    _providers[app.packageName] = provider;
    return provider;
  }

  @override
  Widget build(BuildContext context) {
    final List<int>? png = app.iconPng;
    final String shown = isPlaceholderLabel(app.label, app.packageName)
        ? displayNameFor(app.packageName)
        : app.label;
    // One cliff, at the drawer's tile size: below it a glyph is a chip.
    final double radius = size < 32 ? DexRadius.control : DexRadius.card;

    if (png != null && png.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image(
          image: _providerFor(app, png),
          width: size,
          height: size,
          filterQuality: FilterQuality.medium,
          // A bad PNG must not take the whole grid down with it.
          errorBuilder: (_, _, _) =>
              _LetterTile(name: shown, size: size, radius: radius),
        ),
      );
    }
    return _LetterTile(name: shown, size: size, radius: radius);
  }
}

class _LetterTile extends StatelessWidget {
  const _LetterTile({
    required this.name,
    required this.size,
    required this.radius,
  });

  final String name;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final DexColors colors = Theme.of(context).extension<DexColors>()!;
    final DexGlass glass = DexGlass.of(context);
    final String trimmed = name.trim();
    final String letter = trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();

    // The tint is derived from the package's own name rather than assigned, so
    // an app keeps the same colour between sessions and two neighbours in the
    // grid rarely collide.
    final double hue = (name.hashCode.abs() % 360).toDouble();
    final Color tint = HSLColor.fromAHSL(1, hue, 0.55, 0.62).toColor();

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            tint.withValues(alpha: 0.85),
            tint.withValues(alpha: 0.45),
          ],
        ),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: glass.stroke, width: DexStroke.hairline),
      ),
      child: Text(
        letter,
        style: DexTheme.data(
          colors,
          size: size * 0.42,
          color: Colors.white,
        ).copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}
