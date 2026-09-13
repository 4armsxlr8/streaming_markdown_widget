import 'package:flutter/widgets.dart';

import 'reply_theme.dart';

/// 段落 1 つ。
class MarkdownParagraph extends StatelessWidget {
  const MarkdownParagraph({super.key, required this.spans, this.style});

  /// 出現状態を反映済みの段落の中身。
  final List<InlineSpan> spans;

  /// 基準の style (既定は本文)。引用の中の段落はこれを差し替えて呼ぶ。
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Text.rich(TextSpan(style: style ?? ReplyTheme.bodyTextStyle, children: spans));
  }
}
