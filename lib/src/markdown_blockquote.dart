import 'package:flutter/widgets.dart';

import 'reply_theme.dart';

/// 引用 (`> `) 1 つ。中身は段落など、他のブロック Widget をそのまま包む。
class MarkdownBlockquote extends StatelessWidget {
  const MarkdownBlockquote({super.key, required this.children});

  /// 引用の中のブロック (通常は段落)。
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 2).copyWith(
        left: ReplyTheme.quoteIndent,
      ),
      decoration: const BoxDecoration(
        border: Border(
          left: BorderSide(
            color: ReplyTheme.quoteBorderColor,
            width: ReplyTheme.quoteBorderWidth,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }
}
