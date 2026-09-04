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
        hint: 'Search Google',
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
      padding: const EdgeInsets.symmetric(
        horizontal: DexSpace.md,
        vertical: 2,
      ),
      child: Row(
        children: <Widget>[
          const _GoogleMark(),
          const SizedBox(width: DexSpace.md),
          Expanded(
            child: TextField(
              controller: _controller,
              onSubmitted: (_) => _submit(),
              textInputAction: TextInputAction.search,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: c.text,
              ),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: widget.hint,
                hintStyle: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: c.muted,
                ),
              ),
            ),
          ),
          const SizedBox(width: DexSpace.sm),
          IconButton(
            onPressed: _submit,
            icon: Icon(DexIcons.microphone, size: 18, color: c.muted),
            splashRadius: 18,
            tooltip: 'Search',
          ),
        ],
      ),
    );
  }
}

/// A small multicolour Google "G" mark, drawn rather than shipped.
class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 22,
      height: 22,
      child: CustomPaint(painter: _GooglePainter()),
    );
  }
}

class _GooglePainter extends CustomPainter {
  const _GooglePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final double r = size.shortestSide / 2;
    final Rect ring = Rect.fromCircle(center: center, radius: r - 2);
    final Paint p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.butt;
    const List<Color> colors = <Color>[
      Color(0xFF4285F4),
      Color(0xFF34A853),
      Color(0xFFFBBC05),
      Color(0xFFEA4335),
    ];
    const List<double> starts = <double>[-0.5, 1.7, 2.9, 3.9];
    const List<double> sweeps = <double>[2.2, 1.2, 1.0, 1.2];
    for (int i = 0; i < 4; i++) {
      canvas.drawArc(ring, starts[i], sweeps[i], false, p..color = colors[i]);
    }
    canvas.drawLine(
      center,
      Offset(size.width - 3, center.dy),
      Paint()
        ..color = const Color(0xFF4285F4)
        ..strokeWidth = 4,
    );
  }

  @override
  bool shouldRepaint(_GooglePainter oldDelegate) => false;
}
