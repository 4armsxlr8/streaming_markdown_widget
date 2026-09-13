import 'package:flutter/widgets.dart';

import 'reply_theme.dart';

/// 表 (`| ... |` + 区切り行) 1 つ。
///
/// 列幅は届いた内容で決まる (`IntrinsicColumnWidth`)。本体の行は届いた行から
/// 足すだけで、表そのものは区切り行が届くまで現れない (前処理の役目)。
class MarkdownTable extends StatelessWidget {
  const MarkdownTable({super.key, required this.headerCells, required this.bodyRows});

  /// 見出し行のセルごとの中身。
  final List<List<InlineSpan>> headerCells;

  /// 本体行 (行ごと・セルごと) の中身。届いていなければ空。
  final List<List<List<InlineSpan>>> bodyRows;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        border: TableBorder.all(
          color: ReplyTheme.tableBorderColor,
          width: ReplyTheme.tableBorderWidth,
        ),
        defaultColumnWidth: const IntrinsicColumnWidth(),
        defaultVerticalAlignment: TableCellVerticalAlignment.top,
        children: [
          TableRow(
            decoration: const BoxDecoration(color: ReplyTheme.tableHeaderBackground),
            children: [for (final cell in headerCells) _cell(cell, ReplyTheme.tableHeaderTextStyle)],
          ),
          for (final row in bodyRows)
            TableRow(
              children: [for (final cell in row) _cell(cell, ReplyTheme.tableTextStyle)],
            ),
        ],
      ),
    );
  }

  Widget _cell(List<InlineSpan> spans, TextStyle style) {
    return Padding(
      padding: ReplyTheme.tableCellPadding,
      child: Text.rich(TextSpan(style: style, children: spans)),
    );
  }
}
