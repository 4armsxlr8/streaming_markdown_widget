import 'package:flutter/widgets.dart';

import 'markdown_block.dart';
import 'streaming_reply_style.dart';

/// One paragraph.
class MarkdownParagraph extends StatelessWidget {
  const MarkdownParagraph({super.key, required this.block, this.textStyle});

  /// This paragraph's content (kind is paragraph).
  final MarkdownBlock block;

  /// The base style (default is body text). A paragraph inside a blockquote
  /// calls this with an override.
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final style =
        textStyle ??
        StreamingReplyStyleScope.of(
          context,
        ).resolveBodyTextStyle(DefaultTextStyle.of(context).style);
    return Text.rich(
      applyReveal(
        TextSpan(style: style, children: block.spans!),
        block.revealing,
      ),
    );
  }
}
