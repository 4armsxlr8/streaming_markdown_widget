import 'package:flutter/widgets.dart';

import 'reply_theme.dart';

/// コードフェンス (```) 1 つ。等幅・暗色背景。シンタックスハイライトも
/// コピーボタンも持たない。
class MarkdownCodeBlock extends StatelessWidget {
  const MarkdownCodeBlock({super.key, required this.spans});

  /// 出現状態を反映済みの中身 (素の文字。記法として整形しない)。
  final List<InlineSpan> spans;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: ReplyTheme.codeBlockPadding,
      decoration: BoxDecoration(
        color: ReplyTheme.codeBlockBackground,
        borderRadius: BorderRadius.circular(ReplyTheme.codeBlockBorderRadius),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Text.rich(
          TextSpan(style: ReplyTheme.codeBlockTextStyle, children: spans),
        ),
      ),
    );
  }
}
