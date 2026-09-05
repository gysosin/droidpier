import 'package:flutter/material.dart';

import '../theme/dex_colors.dart';
import '../theme/dex_glass.dart';
import '../theme/dex_tokens.dart';

/// A segmented control: two or more mutually exclusive options in one track.
///
/// Written rather than reached for, because Material's ChoiceChip resolves its
/// selected fill from `secondaryContainer`, which lands on emerald here — so
/// choosing a theme in Settings lit up in the colour this design reserves for
/// telemetry. A reserved role stops meaning anything the moment it is spent on
/// selection.
///
/// Selection out-contrasts hover, hover out-contrasts rest, and the selected
/// option is announced through Semantics rather than only painted.
class DexSegmented extends StatelessWidget {
  const DexSegmented({
    required this.options,
    required this.selected,
    required this.colors,
    required this.onSelect,
    super.key,
  });

  final List<String> options;
  final int selected;
  final DexColors colors;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final DexGlass glass = DexGlass.of(context);
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: glass.fillSubtle,
        borderRadius: BorderRadius.circular(DexRadius.control),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (int i = 0; i < options.length; i++)
            Semantics(
              button: true,
              selected: i == selected,
              child: InkWell(
                onTap: () => onSelect(i),
                borderRadius: BorderRadius.circular(DexRadius.control),
                child: Container(
                  constraints: const BoxConstraints(
                    minHeight: DexHit.minimum,
                    minWidth: 72,
                  ),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: DexSpace.md),
                  decoration: BoxDecoration(
                    color: i == selected ? glass.fillStrong : null,
                    borderRadius: BorderRadius.circular(DexRadius.control),
                  ),
                  child: Text(
                    options[i],
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: i == selected ? colors.text : colors.muted,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
