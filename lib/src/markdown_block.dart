import 'package:flutter/widgets.dart';

import 'reveal_clock.dart' show RevealingChar;

export 'reveal_clock.dart' show RevealingChar;

/// The kind of a block.
enum MarkdownBlockKind {
  heading,
  paragraph,
  bulletList,
  numberedList,
  blockquote,
  codeBlock,
  table,
}

/// The function through which a builder overrides how one block is drawn.
typedef MarkdownBlockBuilder =
    Widget Function(BuildContext context, MarkdownBlock block);

/// The contents and reveal state of one block, as a builder receives them.
///
/// [text] (this block's visible text) and [revealing] (the position from the
/// start of [text], and the opacity, of each revealing character) are
/// available for every [kind]. The remaining fields carry contents matched to
/// the existing per-[kind] drawing, and are non-null only for the [kind] they
/// correspond to ([level]/[spans] for a heading, [spans] for a paragraph,
/// [ordered]/[items] for a list, [children] for a blockquote, [language] for a
/// code block, [headerCells]/[bodyRows] for a table).
class MarkdownBlock {
  const MarkdownBlock({
    required this.kind,
    required this.text,
    required this.revealing,
    this.level,
    this.spans,
    this.ordered,
    this.items,
    this.children,
    this.language,
    this.headerCells,
    this.bodyRows,
  });

  final MarkdownBlockKind kind;

  /// This block's visible text.
  final String text;

  /// The revealing characters within [text] (positions are running indices
  /// from the start of [text]).
  final List<RevealingChar> revealing;

  /// The heading level (the number of `#`; 1–6). Non-null only when kind is
  /// heading.
  final int? level;

  /// The inline contents (the sequence of leaf TextSpans, with the reveal
  /// state not yet applied). Non-null only when kind is heading/paragraph.
  final List<InlineSpan>? spans;

  /// True for a numbered list, false for a bullet list. Non-null only when
  /// kind is bulletList/numberedList.
  final bool? ordered;

  /// The contents of each item. Non-null only when kind is
  /// bulletList/numberedList.
  final List<MarkdownBlockListItem>? items;

  /// The child blocks, already built as Widgets. Non-null only when kind is
  /// blockquote.
  final List<Widget>? children;

  /// The language name taken from the fence's info string (null when there is
  /// none). Only meaningful when kind is codeBlock.
  final String? language;

  /// The contents of each cell of the header row (with the reveal state not
  /// yet applied). Non-null only when kind is table.
  final List<List<InlineSpan>>? headerCells;

  /// The contents of the body rows (per row, per cell; with the reveal state
  /// not yet applied). Non-null only when kind is table.
  final List<List<List<InlineSpan>>>? bodyRows;
}

/// The contents of one bullet-list or numbered-list item, with the reveal
/// state not yet applied.
class MarkdownBlockListItem {
  const MarkdownBlockListItem({
    required this.inline,
    required this.start,
    this.children = const [],
  });

  /// The item's own inline part (the contents of a tight item, or the
  /// contents of the first paragraph of a loose item). The sequence of leaf
  /// TextSpans, with the reveal state not yet applied.
  final List<InlineSpan> inline;

  /// The position (running index) at which the start of [inline] begins within
  /// the [MarkdownBlock.text] of the list containing this item. Used to slice
  /// [MarkdownBlock.revealing] to match [inline].
  final int start;

  /// The child blocks that follow [inline], already built as Widgets (a nested
  /// list, the continuation paragraph of a loose item, and so on). Empty when
  /// there are none.
  final List<Widget> children;
}

/// The number of visible characters (graphemes) in [spans] (a sequence of leaf
/// TextSpans).
int inlineSpansLength(List<InlineSpan> spans) => spans.fold(
  0,
  (sum, span) => sum + ((span as TextSpan).text ?? '').characters.length,
);

/// Takes only the entries of [revealing] that are at or after [start] and
/// below [start] + [length], with [start] subtracted (rebased to their
/// position within that range).
List<RevealingChar> revealingSlice(
  List<RevealingChar> revealing, {
  required int start,
  required int length,
}) => [
  for (final r in revealing)
    if (r.index >= start && r.index < start + length)
      RevealingChar(index: r.index - start, char: r.char, opacity: r.opacity),
];

/// Applies [revealing] (the position and opacity, within [span]'s visible
/// text, of each revealing character) to [span] (a leaf
/// `TextSpan(text:, style:)`, a `TextSpan(children:)` that merely holds such
/// leaves as its children, or a `TextSpan(text:, children:)` that carries
/// both — walked text-first, since that is the order Flutter itself paints
/// them in, so the indices in [revealing] stay lined up with the traversal
/// order).
///
/// A leaf that contains no revealing character is returned as-is. A leaf that
/// does contain one is rebuilt so that each run of already revealed characters
/// becomes one span and each revealing character becomes one span per
/// character (for a revealing character, the alpha of the style's color and
/// background color becomes the opacity) — these are the same rules the
/// default block Widgets follow, so going through this gives the same look as
/// the default (the spec's contract for block overrides).
InlineSpan applyReveal(InlineSpan span, List<RevealingChar> revealing) {
  if (revealing.isEmpty) return span;
  final byIndex = {for (final r in revealing) r.index: r.opacity};
  var offset = 0;

  // A TextSpan's own `text` renders before its `children` (Flutter's own
  // paint order), so a node carrying both is walked text-first — advancing
  // `offset` over `text` before recursing into `children` — to keep the
  // indices in `revealing` lined up with the traversal order.
  InlineSpan walk(InlineSpan node) {
    if (node is! TextSpan) return node;
    final text = node.text;
    final children = node.children;

    List<InlineSpan>? textPieces;
    if (text != null && text.isNotEmpty) {
      final start = offset;
      offset += text.characters.length;

      final pieces = <InlineSpan>[];
      final buffer = StringBuffer();
      var hasRevealing = false;
      var i = start;
      for (final char in text.characters) {
        final opacity = byIndex[i];
        if (opacity == null) {
          buffer.write(char);
        } else {
          hasRevealing = true;
          if (buffer.isNotEmpty) {
            pieces.add(TextSpan(text: buffer.toString(), style: node.style));
            buffer.clear();
          }
          pieces.add(
            TextSpan(
              text: char,
              style: node.style?.copyWith(
                color: node.style?.color?.withValues(alpha: opacity),
                backgroundColor: node.style?.backgroundColor?.withValues(
                  alpha: opacity,
                ),
              ),
            ),
          );
        }
        i++;
      }
      if (hasRevealing) {
        if (buffer.isNotEmpty) {
          pieces.add(TextSpan(text: buffer.toString(), style: node.style));
        }
        textPieces = pieces;
      }
    }

    if (children == null || children.isEmpty) {
      // A leaf: text only (or none at all).
      return textPieces == null ? node : TextSpan(children: textPieces);
    }

    final walkedChildren = [for (final child in children) walk(child)];
    if (textPieces == null) {
      // This node's own text has no revealing character (or none at all) —
      // it stays as this span's `text`; only `children` is rebuilt.
      return TextSpan(text: text, style: node.style, children: walkedChildren);
    }
    // This node's own text does contain a revealing character. It can no
    // longer stay as this span's `text` (each revealing character needs its
    // own per-character style), so its pieces are spliced in ahead of the
    // (already walked) children instead — the "1 revealed run = 1 span"
    // contract is about leaf spans, and a node with both text and children
    // is not itself a leaf.
    return TextSpan(
      style: node.style,
      children: [...textPieces, ...walkedChildren],
    );
  }

  return walk(span);
}
