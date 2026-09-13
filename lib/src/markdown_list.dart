import 'package:flutter/widgets.dart';

import 'reply_theme.dart';

/// 箇条書き (`- `) または番号リスト (`1. `) の項目 1 つぶんの、出現状態を
/// 反映済みの中身。
class MarkdownListItem {
  const MarkdownListItem({required this.inline, this.children = const []});

  /// 項目自身のインライン部分 (タイトな項目の中身、または緩い項目の最初の
  /// 段落の中身)。
  final List<InlineSpan> inline;

  /// [inline] に続く子ブロック (入れ子の `MarkdownList`、緩い項目の続きの
  /// 段落など)。無ければ空。
  final List<Widget> children;
}

/// 箇条書き (`- `) または番号リスト (`1. `) 1 つ。
///
/// 点 "•" と番号 "1." は受信した文字ではなく、この Widget が描く
/// (出現の対象外。常に不透明)。
class MarkdownList extends StatelessWidget {
  const MarkdownList({super.key, required this.ordered, required this.items, required this.style});

  /// 番号リストなら true、箇条書きなら false。
  final bool ordered;

  /// 項目ごとの、出現状態を反映済みの中身。
  final List<MarkdownListItem> items;

  /// 周囲の style (色を含む)。マーカー ("•"/"1.") と項目の基準 style に使う
  /// (引用の中では本文色ではなく引用の色になるように、常に周囲を引き継ぐ)。
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    // OS の文字サイズ設定 (textScaler) を掛ける (掛けないと 100% を超える
    // 設定で番号・点の幅が本文の文字幅に追いつかず、はみ出す)。
    final indent = MediaQuery.textScalerOf(context).scale(ReplyTheme.listIndent);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: EdgeInsets.only(
              bottom: i == items.length - 1 ? 0 : ReplyTheme.listItemSpacing,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 幅を固定の SizedBox にせず ConstrainedBox の minWidth に
                    // するのは、"10." のような 2 桁の番号が固定幅に収まらず
                    // 折り返してしまうのを防ぐため — 記号の Text は softWrap:
                    // false / maxLines: 1 で 1 行に固定し、幅は自然にはみ出させる。
                    ConstrainedBox(
                      constraints: BoxConstraints(minWidth: indent),
                      child: Text(
                        ordered ? '${i + 1}.' : '•',
                        style: style,
                        softWrap: false,
                        maxLines: 1,
                      ),
                    ),
                    Expanded(
                      child: Text.rich(TextSpan(style: style, children: items[i].inline)),
                    ),
                  ],
                ),
                if (items[i].children.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(left: indent, top: ReplyTheme.listItemSpacing),
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
