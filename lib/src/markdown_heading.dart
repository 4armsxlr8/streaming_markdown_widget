import 'package:flutter/widgets.dart';

import 'reply_theme.dart';

/// [level] (`#`〜`######`) の見出しの style を、[ambient] (周囲の style) の
/// 色を引き継いで返す。mock は見た目を 2 段階 (`h2` 相当・`h3` 相当) しか
/// 持たないため、`##` まで (`level` <= 2) は `h2` のサイズ・太さ・行間、
/// `###` 以降は `h3` のそれにする (mock.html の `parseBlocks` と同じ規則)。
/// 色だけは周囲を引き継ぐ — 引用の中の見出しが本文色ではなく引用の色に
/// なるようにするため。
TextStyle headingStyleFor(int level, TextStyle ambient) =>
    (level <= 2 ? ReplyTheme.h2TextStyle : ReplyTheme.h3TextStyle).copyWith(color: ambient.color);

/// 見出し (`#`〜`######`) 1 つ。
class MarkdownHeading extends StatelessWidget {
  const MarkdownHeading({super.key, required this.level, required this.style, required this.spans});

  /// 記法の段 (`#` の数。1〜6)。
  final int level;

  /// この見出しの style ([headingStyleFor] で決めたもの)。
  final TextStyle style;

  /// 出現状態を反映済みの見出しの中身。
  final List<InlineSpan> spans;

  @override
  Widget build(BuildContext context) => Text.rich(TextSpan(style: style, children: spans));
}
