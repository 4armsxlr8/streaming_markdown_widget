import 'package:flutter/widgets.dart';

import 'markdown_block.dart';
import 'streaming_reply_style.dart';

/// One blockquote (`> `). Its content is other block widgets (paragraphs,
/// etc.) wrapped as-is.
class MarkdownBlockquote extends StatelessWidget {
  const MarkdownBlockquote({super.key, required this.block});

  /// This blockquote's content (kind is blockquote). Child blocks are already rendered.
  final MarkdownBlock block;

  @override
  Widget build(BuildContext context) {
    final style = StreamingReplyStyleScope.of(context);
    return Container(
      padding: EdgeInsets.symmetric(
        vertical: 2,
      ).copyWith(left: style.quoteIndent),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: style.quoteBorderColor,
            width: style.quoteBorderWidth,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: block.children!,
      ),
    );
  }
}
