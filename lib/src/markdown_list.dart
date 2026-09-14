import 'package:flutter/widgets.dart';

import 'markdown_block.dart';
import 'streaming_reply_style.dart';

/// One bullet list (`- `) or numbered list (`1. `).
///
/// The bullet "•" and the number "1." are drawn by this widget, not received
/// text (not subject to revealing — always opaque).
class MarkdownList extends StatelessWidget {
  const MarkdownList({super.key, required this.block, required this.textStyle});

  /// This list's content (kind is bulletList or numberedList).
  final MarkdownBlock block;

  /// The surrounding style (including color). Used as the base style for
  /// both the marker ("•"/"1.") and the items — always inherited from the
  /// surroundings so a list inside a blockquote gets the quote's color
  /// instead of the body color.
  final TextStyle textStyle;

  /// True for a numbered list, false for a bullet list.
  bool get ordered => block.ordered!;

  @override
  Widget build(BuildContext context) {
    final style = StreamingReplyStyleScope.of(context);
    final items = block.items!;
    // Apply the OS text-scale setting (textScaler) — without it, a scale
    // setting above 100% makes the number/bullet column too narrow for the
    // body text, causing overflow.
    final indent = MediaQuery.textScalerOf(context).scale(style.listIndent);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: EdgeInsets.only(
              bottom: i == items.length - 1 ? 0 : style.listItemSpacing,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Uses ConstrainedBox's minWidth instead of a fixed-width
                    // SizedBox so a 2-digit number like "10." doesn't get
                    // wrapped for not fitting a fixed width — the marker
                    // text is pinned to one line (softWrap: false, maxLines:
                    // 1) and allowed to overflow that width naturally.
                    ConstrainedBox(
                      constraints: BoxConstraints(minWidth: indent),
                      child: Text(
                        ordered ? '${i + 1}.' : '•',
                        style: textStyle,
                        softWrap: false,
                        maxLines: 1,
                      ),
                    ),
                    Expanded(
                      child: Text.rich(
                        _revealItem(items[i], block.revealing, textStyle),
                      ),
                    ),
                  ],
                ),
                if (items[i].children.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(
                      left: indent,
                      top: style.listItemSpacing,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: items[i].children,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Applies [item]'s own inline content the slice of [revealing] (belonging
/// to the whole list it's part of) that falls within [item]'s range.
InlineSpan _revealItem(
  MarkdownBlockListItem item,
  List<RevealingChar> revealing,
  TextStyle style,
) {
  if (revealing.isEmpty) return TextSpan(style: style, children: item.inline);
  final length = inlineSpansLength(item.inline);
  final local = revealingSlice(revealing, start: item.start, length: length);
  return applyReveal(TextSpan(style: style, children: item.inline), local);
}
