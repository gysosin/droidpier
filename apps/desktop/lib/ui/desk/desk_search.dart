import 'package:flutter/material.dart';

import '../theme/dex_icons.dart';

import '../theme/dex_colors.dart';
import '../theme/dex_tokens.dart';
import '../theme/glass.dart';

/// The desk search bar: a single translucent Google pill at the top-left.
/// Submitting opens the query in the browser via
/// [onSearch] (a full URL).
class DeskSearchBars extends StatelessWidget {
  const DeskSearchBars({required this.onSearch, super.key});

  final ValueChanged<String> onSearch;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      // The reference sets this at max-w-sm. A 620px bar across the top-left
      // reads as a browser chrome; a pill reads as a desk affordance.
      constraints: const BoxConstraints(maxWidth: 384),
      child: _SearchBar(
        hint: 'Search the web or apps…',
        onSubmit: (String q) => onSearch(
          'https://www.google.com/search?q=${Uri.encodeQueryComponent(q)}',
        ),
      ),
    );
  }
}

class _SearchBar extends StatefulWidget {
  const _SearchBar({required this.hint, required this.onSubmit});

  final String hint;
  final ValueChanged<String> onSubmit;

  @override
  State<_SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<_SearchBar> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final String q = _controller.text.trim();
    if (q.isEmpty) return;
    widget.onSubmit(q);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final DexColors c = Theme.of(context).extension<DexColors>()!;
    return GlassPanel(
      radius: 26,
      stroke: Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: DexSpace.md, vertical: 2),
      child: Row(
        children: <Widget>[
          const _GoogleWordmark(),
          const SizedBox(width: DexSpace.md),
          Expanded(
            child: TextField(
              controller: _controller,
              onSubmitted: (_) => _submit(),
              textInputAction: TextInputAction.search,
              style: Theme.of(context).textTheme.bodyLarge
                  ?.copyWith(color: c.text),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: widget.hint,
                hintStyle: Theme.of(context).textTheme.bodyLarge
                    ?.copyWith(color: c.muted),
              ),
            ),
          ),
          const SizedBox(width: DexSpace.sm),
          IconButton(
            onPressed: _submit,
            icon: Icon(DexIcons.search, size: 16, color: c.muted),
            splashRadius: 18,
            tooltip: 'Search',
          ),
        ],
      ),
    );
  }
}

/// The Google wordmark, letter by letter, as the reference sets it.
///
/// Six letters in the brand's four colours — except the `l`, which the
/// reference draws in this design's own trace emerald rather than Google's
/// green. That is the one place the two palettes touch, and it is deliberate.
class _GoogleWordmark extends StatelessWidget {
  const _GoogleWordmark();

  static const List<(String, Color)> _letters = <(String, Color)>[
    ('G', Color(0xFF4285F4)),
    ('o', Color(0xFFEA4335)),
    ('o', Color(0xFFFBBC05)),
    ('g', Color(0xFF4285F4)),
    ('l', Color(0xFF34D399)),
    ('e', Color(0xFFEA4335)),
  ];

  @override
  Widget build(BuildContext context) {
    final TextStyle? base = Theme.of(context).textTheme.labelLarge;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final (String letter, Color colour) in _letters)
          Text(
            letter,
            style: base?.copyWith(
              color: colour,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.6,
            ),
          ),
      ],
    );
  }
}
