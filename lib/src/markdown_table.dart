import 'package:flutter/widgets.dart';

import 'markdown_block.dart';
import 'streaming_reply_style.dart';

/// One table (`| ... |` plus a delimiter row).
///
/// Column widths are decided from the content received so far
/// (`IntrinsicColumnWidth`). Body rows are simply appended as they arrive;
/// the table itself doesn't appear until the delimiter row arrives (the
/// preprocessing step's job).
class MarkdownTable extends StatelessWidget {
  const MarkdownTable({super.key, required this.block});

  /// This table's content (kind is table).
  final MarkdownBlock block;

  @override
  Widget build(BuildContext context) {
    final style = StreamingReplyStyleScope.of(context);
    final ambient = DefaultTextStyle.of(context).style;
    final headerTextStyle = style.resolveTableHeaderTextStyle(ambient);
    final bodyTextStyle = style.resolveTableTextStyle(ambient);
    // Cells consume received characters in header-row-then-body-rows order,
    // and column order within a row (see `_buildTable` in
    // revealed_markdown.dart), so [offset] can be advanced in that same
    // order to slice out each cell's portion of [block.revealing].
    final noRevealing = block.revealing.isEmpty;
    var offset = 0;
    InlineSpan revealCell(List<InlineSpan> spans, TextStyle cellStyle) {
      if (noRevealing) return TextSpan(style: cellStyle, children: spans);
      final length = inlineSpansLength(spans);
      final local = revealingSlice(
        block.revealing,
        start: offset,
        length: length,
      );
      offset += length;
      return applyReveal(TextSpan(style: cellStyle, children: spans), local);
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        border: TableBorder.all(
          color: style.tableBorderColor,
          width: style.tableBorderWidth,
        ),
        defaultColumnWidth: const IntrinsicColumnWidth(),
        defaultVerticalAlignment: TableCellVerticalAlignment.top,
        children: [
          TableRow(
            decoration: BoxDecoration(color: style.tableHeaderBackground),
            children: [
              for (final cell in block.headerCells!)
                _cell(revealCell(cell, headerTextStyle), style),
            ],
          ),
          for (final row in block.bodyRows!)
            TableRow(
              children: [
                for (final cell in row)
                  _cell(revealCell(cell, bodyTextStyle), style),
              ],
            ),
        ],
      ),
    );
  }

  Widget _cell(InlineSpan span, StreamingReplyStyle style) =>
      Padding(padding: style.tableCellPadding, child: Text.rich(span));
}
