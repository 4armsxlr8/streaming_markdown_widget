import 'package:flutter/widgets.dart';

import 'markdown_block.dart';
import 'streaming_reply_style.dart';

/// One code fence (```` ``` ````). Monospace, dark background. No syntax
/// highlighting and no copy button.
class MarkdownCodeBlock extends StatelessWidget {
  const MarkdownCodeBlock({super.key, required this.block});

  /// This code block's content (kind is codeBlock).
  final MarkdownBlock block;

  @override
  Widget build(BuildContext context) {
    final style = StreamingReplyStyleScope.of(context);
    final ambient = DefaultTextStyle.of(context).style;
    return Container(
      width: double.infinity,
      padding: style.codeBlockPadding,
      decoration: BoxDecoration(
        color: style.codeBlockBackground,
        borderRadius: BorderRadius.circular(style.codeBlockBorderRadius),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Text.rich(
          applyReveal(
            TextSpan(
              text: block.text,
              style: style.resolveCodeBlockTextStyle(ambient),
            ),
            block.revealing,
          ),
        ),
      ),
    );
  }
}
