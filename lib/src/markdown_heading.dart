import 'package:flutter/widgets.dart';

import 'markdown_block.dart';
import 'streaming_reply_style.dart';

/// The style for a heading at [level] (`#`–`######`), merging [style]'s
/// `h2TextStyle`/`h3TextStyle` onto [ambient] (the running style — body or
/// blockquote). The mock only has 2 tiers of look (`h2`-equivalent,
/// `h3`-equivalent), so `##` and shallower (`level` <= 2) get `h2`'s size,
/// weight, and line-height, and `###` and deeper get `h3`'s (same rule as
/// mock.html's `parseBlocks`). Neither role sets its own color, so it is
/// inherited from [ambient] — a heading inside a blockquote gets the quote's
/// color instead of the body color.
TextStyle headingStyleFor(
  int level,
  TextStyle ambient,
  StreamingReplyStyle style,
) => style.resolveHeadingTextStyle(level, ambient);

/// One heading (`#`–`######`).
class MarkdownHeading extends StatelessWidget {
  const MarkdownHeading({
    super.key,
    required this.block,
    required this.textStyle,
  });

  /// This heading's content (kind is heading).
  final MarkdownBlock block;

  /// This heading's style (decided by [headingStyleFor]).
  final TextStyle textStyle;

  /// The heading level (number of `#`, 1–6).
  int get level => block.level!;

  @override
  Widget build(BuildContext context) => Text.rich(
    applyReveal(
      TextSpan(style: textStyle, children: block.spans!),
      block.revealing,
    ),
  );
}
