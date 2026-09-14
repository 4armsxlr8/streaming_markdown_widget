import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:markdown/markdown.dart' as md;

import 'markdown_block.dart';
import 'markdown_blockquote.dart';
import 'markdown_code_block.dart';
import 'markdown_heading.dart';
import 'markdown_list.dart';
import 'markdown_paragraph.dart';
import 'markdown_table.dart';
import 'partial_markdown.dart';
import 'reveal_clock.dart' show revealOpacity;
import 'reveal_ticker.dart' show syncTicker;
import 'streaming_reply_controller.dart';
import 'streaming_reply_style.dart';

/// Widget that draws the `revealedText` of one of the controller's two
/// sections (thinking or reply).
///
/// When [formatted] is true it formats the text as Markdown (headings,
/// paragraphs, bold, italic, inline code, code blocks, bullet lists, numbered
/// lists, blockquotes, links, tables); when false it draws plain text
/// (newlines stay newlines). Both use the same reveal mechanism: the visible
/// characters are numbered in AST traversal order (with `formatted: false`,
/// simply in the order the characters appear), and everything past the common
/// prefix with the previous frame's visible text counts as "drawn just now"
/// and gets a reveal start time (this also explains why characters that were
/// not being drawn because of partial, not-yet-closed notation all start
/// revealing together at the moment they are drawn). Only the characters that
/// are still revealing become one TextSpan per character (grapheme), with the
/// opacity carried by the alpha of the style's color; already revealed
/// characters are merged into a single span. The fade time behind that
/// opacity is [controller]'s own `style.fadeDuration`, not [style]'s (see the
/// time-fields split in the [StreamingReplyStyle] class doc).
///
/// When [formatted] is true, how a block is drawn can be overridden per kind
/// through [blockBuilders]. Kinds you do not pass are drawn by the default
/// block Widget ([MarkdownHeading] and the like). The default drawing also
/// goes through [applyReveal], so an overridden kind that uses [applyReveal]
/// gets the same opacities as the default.
///
/// Besides listening to [StreamingReplyController] and rebuilding, it keeps
/// rebuilding from its own Ticker while there are visible characters still
/// revealing, and while the controller still needs the clock
/// ([StreamingReplyController.needsTicks]). The former is so that the 300ms of
/// the characters revealing at that moment is drawn to completion even after
/// the controller's own needsTicks has gone false; the latter is so that, when
/// placed on its own rather than wrapped in a `RevealTicker`, it calls
/// [StreamingReplyController.tick] itself to advance the clock (in the
/// composed Widget that layers it with `RevealTicker`, the outer Ticker does
/// the same job).
class RevealedMarkdown extends StatefulWidget {
  const RevealedMarkdown({
    super.key,
    required this.controller,
    required this.kind,
    this.style,
    this.formatted = true,
    this.blockBuilders,
  });

  /// Entry point for the observed values, including the reveal state.
  final StreamingReplyController controller;

  /// Which of the two sections to draw.
  final ChunkKind kind;

  /// Look-and-feel values (the defaults when omitted). Passed down to the
  /// block Widgets through an InheritedWidget ([StreamingReplyStyleScope]).
  final StreamingReplyStyle? style;

  /// Whether to format the text as Markdown.
  final bool formatted;

  /// Per-kind overrides for how a block is drawn. Kinds you do not pass are
  /// drawn by the default block Widget (not consulted at all when [formatted]
  /// is false).
  final Map<MarkdownBlockKind, MarkdownBlockBuilder>? blockBuilders;

  @override
  State<RevealedMarkdown> createState() => _RevealedMarkdownState();
}

class _RevealedMarkdownState extends State<RevealedMarkdown>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;

  /// The visible characters (graphemes) drawn in the previous frame. Used for
  /// the common-prefix comparison.
  List<String> _previousChars = const [];

  /// The reveal start time of each character, paired with [_previousChars].
  List<Duration> _previousStarts = const [];

  /// The [SchedulerBinding.currentFrameTimeStamp] read during the most recent
  /// frame. Outside a frame (`schedulerPhase == idle`, the first attach on a
  /// cold start, and so on) reading `currentFrameTimeStamp` trips an assert,
  /// so this value (or [Duration.zero] if there is none) is used instead.
  Duration _lastFrameTime = Duration.zero;

  /// What [build] computed in the previous frame for "is it safe to parse this
  /// as if receiving had finished" (the previous frame's `complete`). Used to
  /// detect the first frame where it flips from false to true (Q11: at the
  /// moment notation that had been closed off while still partial is replaced
  /// by the post-receiving string that includes the raw markers, and the shape
  /// of the visible text therefore changes, this keeps characters that were
  /// already revealed from revealing all over again).
  bool _wasComplete = false;

  /// The last `(revealedText, complete)` that was parsed, and the AST it
  /// produced. Frames where neither the visible text nor [complete] has
  /// changed (at least one frame in three while it redraws every frame) do not
  /// reparse — the AST is only read and never rewritten ([_buildBlocks] and
  /// below only build Widgets), so reusing it is safe.
  String? _cachedRevealedText;
  bool? _cachedComplete;
  List<md.Node>? _cachedNodes;

  List<md.Node> _parseCached(String revealedText, bool complete) {
    if (_cachedRevealedText == revealedText && _cachedComplete == complete) {
      return _cachedNodes!;
    }
    final nodes = parseReplyMarkdown(revealedText, complete: complete);
    _cachedRevealedText = revealedText;
    _cachedComplete = complete;
    _cachedNodes = nodes;
    return nodes;
  }

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    widget.controller.addListener(_onControllerChanged);
  }

  /// The per-frame callback of [_ticker]: first advance the controller's clock
  /// (when this Widget is placed on its own there is no other part to drive
  /// it), then rebuild so that its own reveal opacities are recomputed.
  void _onTick(Duration elapsed) {
    widget.controller.tick(SchedulerBinding.instance.currentFrameTimeStamp);
    setState(() {});
  }

  @override
  void didUpdateWidget(covariant RevealedMarkdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
    if (oldWidget.controller != widget.controller ||
        oldWidget.kind != widget.kind) {
      // A changed controller / kind means a different string will be drawn,
      // so reset the common-prefix comparison against the previous frame's
      // visible text (otherwise unrelated strings get compared and reveal
      // start times are carried over incorrectly).
      _previousChars = const [];
      _previousStarts = const [];
      _wasComplete = false;
      _cachedRevealedText = null;
      _cachedComplete = null;
      _cachedNodes = null;
    }
  }

  void _onControllerChanged() => setState(() {});

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style ?? StreamingReplyStyleScope.of(context);
    final ambient = DefaultTextStyle.of(context).style;
    final section = widget.kind == ChunkKind.thinking
        ? widget.controller.thinking
        : widget.controller.reply;
    final baseStyle = widget.kind == ChunkKind.thinking
        ? style.resolveThinkingTextStyle(ambient)
        : style.resolveBodyTextStyle(ambient);
    final now = SchedulerBinding.instance.schedulerPhase == SchedulerPhase.idle
        ? _lastFrameTime
        : SchedulerBinding.instance.currentFrameTimeStamp;
    _lastFrameTime = now;

    // Once receiving has finished and every received character has started
    // revealing (even if some are still mid-reveal), parse this as the whole
    // text (which keeps partial notation from staying held back or
    // provisionally closed forever).
    final complete =
        widget.controller.isComplete &&
        section.startedCount == section.receivedCount;
    // Only on the first frame where complete flips from false to true, the
    // characters from the position where the visible text differs from the
    // previous frame onward are settled as "revealed" immediately (Q11). This
    // only matters with formatting on (formatted) — that is the only path
    // where the shape of the same already revealed part can change between
    // the visible text with partial notation held back or provisionally
    // closed and the visible text after receiving has finished, which
    // includes the raw markers. If the visible text has not changed
    // (sampleReply, for instance) this frame changes nothing.
    final justCompleted = widget.formatted && complete && !_wasComplete;
    _wasComplete = complete;
    final cursor = _RevealCursor(
      now: now,
      previousChars: _previousChars,
      previousStarts: _previousStarts,
      forceOpaque: justCompleted,
      // The controller's own style, not the widget-side `style` above — see
      // the class doc and `_RevealCursor.fade`.
      fade: widget.controller.style.fadeDuration,
    );
    final draw = (
      cursor: cursor,
      replyStyle: style,
      ambient: ambient,
      context: context,
      builders: widget.blockBuilders,
    );

    final Widget child;
    if (widget.formatted) {
      child = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: _buildBlocks(
          _parseCached(section.revealedText, complete),
          baseStyle,
          draw,
        ),
      );
    } else {
      final plain = _plainSpan(section.revealedText, cursor, baseStyle);
      child = Text.rich(
        TextSpan(
          style: baseStyle,
          children: [
            for (final span in plain) applyReveal(span, cursor.revealing),
          ],
        ),
      );
    }

    _previousChars = cursor.chars;
    _previousStarts = cursor.starts;

    // Keep it running while there are revealing characters, and also while
    // the Controller still needs the clock (placed on its own, this Ticker
    // stands in for [RevealTicker]). Also tells the Controller whether frames
    // are actually running (see the doc on [syncTicker]).
    syncTicker(
      _ticker,
      widget.controller,
      wanted: cursor.hasRevealing || widget.controller.needsTicks,
    );

    // The screen reader is handed the whole text received so far, even while
    // receiving (including characters that have not started revealing), and
    // the per-character spans of the revealing characters are excluded so
    // they do not get mixed in as child nodes of what is read out.
    final semanticChild = Semantics(
      label: section.text,
      excludeSemantics: true,
      child: child,
    );

    return StreamingReplyStyleScope(style: style, child: semanticChild);
  }
}

/// One block and the spacing below it.
class _Block {
  const _Block(this.widget, this.spacingBottom);

  final Widget widget;
  final double spacingBottom;
}

/// The depth limit on [_buildBlocks] recursing through nested blockquotes
/// (cheap insurance. It prevents a `StackOverflowError` from a nesting
/// thousands of levels deep, beyond anything the fake sample produces. It does
/// not take care of the parser's own recursion).
const _maxBlockDepth = 16;

/// The values that stay the same across one whole [_buildBlocks] traversal,
/// bundled so they thread through as one argument instead of four.
typedef _Draw = ({
  _RevealCursor cursor,
  StreamingReplyStyle replyStyle,
  // The surrounding DefaultTextStyle, captured once in RevealedMarkdown.build
  // (see the StreamingReplyStyle class doc's merge rules) — codeBlock/table
  // roles merge onto this directly, unlike heading/blockquote/link/inline
  // code, which merge onto the running ambientStyle instead.
  TextStyle ambient,
  BuildContext context,
  Map<MarkdownBlockKind, MarkdownBlockBuilder>? builders,
});

/// Turns a sequence of blocks into a sequence of Widgets (inserting the bottom
/// spacing of every block but the last as a SizedBox).
List<Widget> _buildBlocks(
  List<md.Node> nodes,
  TextStyle ambientStyle,
  _Draw draw, {
  int depth = 0,
}) {
  final blocks = <_Block>[
    for (final node in nodes) ?_buildBlock(node, ambientStyle, depth, draw),
  ];
  final widgets = <Widget>[];
  for (var i = 0; i < blocks.length; i++) {
    widgets.add(blocks[i].widget);
    if (i != blocks.length - 1) {
      widgets.add(SizedBox(height: blocks[i].spacingBottom));
    }
  }
  return widgets;
}

/// Returns the override in [_Draw.builders] for [block.kind] if there is one,
/// and [defaultWidget] otherwise.
Widget _resolveBlock(_Draw draw, MarkdownBlock block, Widget defaultWidget) =>
    draw.builders?[block.kind]?.call(draw.context, block) ?? defaultWidget;

/// Assembles a paragraph [MarkdownBlock] from [text] (the visible text to draw
/// as a paragraph) and turns the override from [_Draw.builders] — or the
/// default [MarkdownParagraph] when there is none — into a [_Block]. Called
/// only from [_inlineParagraphBlock].
_Block _paragraphBlock(
  String text,
  List<InlineSpan> spans,
  List<RevealingChar> revealing,
  TextStyle style,
  _Draw draw,
) {
  final block = MarkdownBlock(
    kind: MarkdownBlockKind.paragraph,
    text: text,
    revealing: revealing,
    spans: spans,
  );
  return _Block(
    _resolveBlock(
      draw,
      block,
      MarkdownParagraph(block: block, textStyle: style),
    ),
    draw.replyStyle.blockSpacing,
  );
}

/// Runs [nodes] through [_buildInlineSpans] while recording the visible text
/// and revealing characters they consume from [draw]'s cursor, and turns the
/// result into a paragraph [_Block] via [_paragraphBlock]. The shared body of
/// the four safety nets that draw a subtree as a plain paragraph: a bare
/// `Text` (wrapped as a one-element node list), `p`, the blockquote depth
/// limit, and an unknown tag.
_Block _inlineParagraphBlock(
  List<md.Node>? nodes,
  TextStyle style,
  int depth,
  _Draw draw,
) {
  final cursor = draw.cursor;
  final start = cursor.chars.length;
  final spans = _buildInlineSpans(nodes, style, draw, depth: depth);
  return _paragraphBlock(
    cursor.chars.sublist(start).join(),
    spans,
    revealingSlice(
      cursor.revealing,
      start: start,
      length: cursor.chars.length - start,
    ),
    style,
    draw,
  );
}

_Block? _buildBlock(
  md.Node node,
  TextStyle ambientStyle,
  int depth,
  _Draw draw,
) {
  if (node is md.Text) {
    // Safety net: the block syntaxes that are registered never return a bare
    // Text at the top level, but draw it as a paragraph just in case.
    return _inlineParagraphBlock([node], ambientStyle, depth, draw);
  }
  if (node is! md.Element) return null;

  final cursor = draw.cursor;
  switch (node.tag) {
    case 'h1':
    case 'h2':
    case 'h3':
    case 'h4':
    case 'h5':
    case 'h6':
      final level = int.parse(node.tag.substring(1));
      final style = headingStyleFor(level, ambientStyle, draw.replyStyle);
      final start = cursor.chars.length;
      final spans = _buildInlineSpans(node.children, style, draw, depth: depth);
      final block = MarkdownBlock(
        kind: MarkdownBlockKind.heading,
        text: cursor.chars.sublist(start).join(),
        revealing: revealingSlice(
          cursor.revealing,
          start: start,
          length: cursor.chars.length - start,
        ),
        level: level,
        spans: spans,
      );
      return _Block(
        _resolveBlock(
          draw,
          block,
          MarkdownHeading(block: block, textStyle: style),
        ),
        level <= 2
            ? draw.replyStyle.h2SpacingBottom
            : draw.replyStyle.h3SpacingBottom,
      );

    case 'p':
      return _inlineParagraphBlock(node.children, ambientStyle, depth, draw);

    case 'ul':
    case 'ol':
      final ordered = node.tag == 'ol';
      final start = cursor.chars.length;
      final items = <MarkdownBlockListItem>[
        for (final item in node.children ?? const <md.Node>[])
          if (item is md.Element)
            _buildListItem(item, ambientStyle, depth, draw, listStart: start),
      ];
      final block = MarkdownBlock(
        kind: ordered
            ? MarkdownBlockKind.numberedList
            : MarkdownBlockKind.bulletList,
        text: cursor.chars.sublist(start).join(),
        revealing: revealingSlice(
          cursor.revealing,
          start: start,
          length: cursor.chars.length - start,
        ),
        ordered: ordered,
        items: items,
      );
      return _Block(
        _resolveBlock(
          draw,
          block,
          MarkdownList(block: block, textStyle: ambientStyle),
        ),
        draw.replyStyle.blockSpacing,
      );

    case 'blockquote':
      final quoteStyle = draw.replyStyle.resolveQuoteTextStyle(ambientStyle);
      if (depth >= _maxBlockDepth) {
        // A subtree past the depth limit is drawn as a plain paragraph
        // without recursing any further.
        return _inlineParagraphBlock(node.children, quoteStyle, depth, draw);
      }
      final start = cursor.chars.length;
      final children = _buildBlocks(
        node.children ?? const [],
        quoteStyle,
        draw,
        depth: depth + 1,
      );
      final block = MarkdownBlock(
        kind: MarkdownBlockKind.blockquote,
        text: cursor.chars.sublist(start).join(),
        revealing: revealingSlice(
          cursor.revealing,
          start: start,
          length: cursor.chars.length - start,
        ),
        children: children,
      );
      return _Block(
        _resolveBlock(draw, block, MarkdownBlockquote(block: block)),
        draw.replyStyle.blockSpacing,
      );

    case 'pre':
      final code = _firstElement(node.children);
      final text = code == null
          ? ''
          : _stripFencedTrailingNewline(_codeText(code));
      final start = cursor.chars.length;
      for (final char in text.characters) {
        cursor.consume(char);
      }
      final block = MarkdownBlock(
        kind: MarkdownBlockKind.codeBlock,
        text: text,
        revealing: revealingSlice(
          cursor.revealing,
          start: start,
          length: cursor.chars.length - start,
        ),
        language: code == null ? null : _codeLanguage(code),
      );
      return _Block(
        _resolveBlock(draw, block, MarkdownCodeBlock(block: block)),
        draw.replyStyle.blockSpacing,
      );

    case 'table':
      return _Block(
        _buildTable(node, depth, draw),
        draw.replyStyle.blockSpacing,
      );

    default:
      // Safety net for tags that are not in the mapping: if there are
      // children, draw their text as plain text as-is; if children is null
      // (a self-contained element), draw nothing.
      final children = node.children;
      if (children == null) return null;
      return _inlineParagraphBlock(children, ambientStyle, depth, draw);
  }
}

/// Splits one `li` into its inline part and the child blocks that follow it (a
/// nested `MarkdownList`, the continuation paragraph of a loose item, and so
/// on) ([Q15]).
///
/// For a tight item (`<li>text<ul>…</ul></li>`), the inline part runs from the
/// start up to the first `ul`/`ol`/`p`. For a loose item
/// (`<li><p>text</p><ul>…</ul></li>`) the contents of the first `p` are the
/// inline part, and everything from there on is a child block.
MarkdownBlockListItem _buildListItem(
  md.Element li,
  TextStyle style,
  int depth,
  _Draw draw, {
  required int listStart,
}) {
  final children = li.children ?? const <md.Node>[];
  final List<md.Node> inlineNodes;
  final List<md.Node> blockNodes;
  final first = children.isEmpty ? null : children.first;
  if (first is md.Element && first.tag == 'p') {
    inlineNodes = first.children ?? const <md.Node>[];
    blockNodes = children.skip(1).toList(growable: false);
  } else {
    final splitAt = children.indexWhere(
      (n) =>
          n is md.Element && (n.tag == 'ul' || n.tag == 'ol' || n.tag == 'p'),
    );
    if (splitAt == -1) {
      inlineNodes = children;
      blockNodes = const [];
    } else {
      inlineNodes = children.sublist(0, splitAt);
      blockNodes = children.sublist(splitAt);
    }
  }
  final cursor = draw.cursor;
  final start = cursor.chars.length - listStart;
  final inline = _buildInlineSpans(inlineNodes, style, draw, depth: depth);
  final childWidgets = depth >= _maxBlockDepth
      ? const <Widget>[]
      : _buildBlocks(blockNodes, style, draw, depth: depth + 1);
  return MarkdownBlockListItem(
    inline: inline,
    start: start,
    children: childWidgets,
  );
}

Widget _buildTable(md.Element table, int depth, _Draw draw) {
  md.Element? thead;
  md.Element? tbody;
  for (final child in table.children ?? const <md.Node>[]) {
    if (child is md.Element && child.tag == 'thead') thead = child;
    if (child is md.Element && child.tag == 'tbody') tbody = child;
  }
  final headerRow = _firstElement(thead?.children);
  final cursor = draw.cursor;
  final start = cursor.chars.length;
  final headerTextStyle = draw.replyStyle.resolveTableHeaderTextStyle(
    draw.ambient,
  );
  final bodyTextStyle = draw.replyStyle.resolveTableTextStyle(draw.ambient);
  final headerCells = <List<InlineSpan>>[
    for (final cell in headerRow?.children ?? const <md.Node>[])
      if (cell is md.Element)
        _buildInlineSpans(cell.children, headerTextStyle, draw, depth: depth),
  ];
  final bodyRows = <List<List<InlineSpan>>>[
    for (final row in tbody?.children ?? const <md.Node>[])
      if (row is md.Element)
        <List<InlineSpan>>[
          for (final cell in row.children ?? const <md.Node>[])
            if (cell is md.Element)
              _buildInlineSpans(
                cell.children,
                bodyTextStyle,
                draw,
                depth: depth,
              ),
        ],
  ];
  final block = MarkdownBlock(
    kind: MarkdownBlockKind.table,
    text: cursor.chars.sublist(start).join(),
    revealing: revealingSlice(
      cursor.revealing,
      start: start,
      length: cursor.chars.length - start,
    ),
    headerCells: headerCells,
    bodyRows: bodyRows,
  );
  return _resolveBlock(draw, block, MarkdownTable(block: block));
}

/// Turns a sequence of nodes into a sequence of [InlineSpan]s. [depth] is
/// threaded through in order to count against the nesting depth limit
/// ([_maxBlockDepth]) — it shares the same counter as the block side, as a
/// safety net so that nested `strong`/`em`/`a`/unknown tags do not recurse any
/// further either.
///
/// Image notation (`![alt](href)`) gets no special handling here, because the
/// preprocessing step (`_escapeImageMarkers` in [partial_markdown.dart]) has
/// already escaped `![` to `\!\[` — the parser makes it neither an image nor
/// a link, and it comes through as plain text (`md.Text`) as-is.
List<InlineSpan> _buildInlineSpans(
  List<md.Node>? nodes,
  TextStyle style,
  _Draw draw, {
  int depth = 0,
}) {
  if (nodes == null) return const [];
  final spans = <InlineSpan>[];
  for (final node in nodes) {
    spans.addAll(_buildInline(node, style, draw, depth: depth));
  }
  return spans;
}

List<InlineSpan> _buildInline(
  md.Node node,
  TextStyle style,
  _Draw draw, {
  int depth = 0,
}) {
  if (node is md.Text) {
    return _plainSpan(node.text, draw.cursor, style);
  }
  if (node is! md.Element) return const [];

  if (depth >= _maxBlockDepth) {
    // A subtree past the depth limit is drawn as plain text without recursing
    // any further.
    return _plainSpan(node.textContent, draw.cursor, style);
  }

  switch (node.tag) {
    case 'strong':
      return _buildInlineSpans(
        node.children,
        style.copyWith(fontWeight: FontWeight.w700),
        draw,
        depth: depth + 1,
      );
    case 'em':
      return _buildInlineSpans(
        node.children,
        style.copyWith(fontStyle: FontStyle.italic),
        draw,
        depth: depth + 1,
      );
    case 'code':
      // Merge onto the surrounding style (whatever the code style does not
      // specify itself — underline, weight and so on — is inherited from the
      // surroundings; whatever it does specify — color, background color,
      // font family — takes precedence over the surroundings).
      return _plainSpan(
        _codeText(node),
        draw.cursor,
        draw.replyStyle.resolveInlineCodeTextStyle(style),
      );
    case 'a':
      final linkStyle = draw.replyStyle.resolveLinkTextStyle(style);
      return _buildInlineSpans(
        node.children,
        linkStyle,
        draw,
        depth: depth + 1,
      );
    case 'br':
      // A line break, a self-contained element (children is null).
      return _plainSpan('\n', draw.cursor, style);
    default:
      // Safety net for tags that are not in the mapping. If children is null,
      // draw nothing.
      final children = node.children;
      if (children == null) return const [];
      return _buildInlineSpans(children, style, draw, depth: depth + 1);
  }
}

md.Element? _firstElement(List<md.Node>? nodes) {
  if (nodes == null) return null;
  for (final node in nodes) {
    if (node is md.Element) return node;
  }
  return null;
}

/// Extracts the contents of a `code` element (the single Text child that
/// `Element.text` creates).
String _codeText(md.Element node) => (node.children ?? const <md.Node>[])
    .whereType<md.Text>()
    .map((t) => t.text)
    .join();

/// Strips just one trailing newline, the one `FencedCodeBlockSyntax` appends
/// to the end of a code block's contents (without this, every code block is
/// drawn one line taller).
String _stripFencedTrailingNewline(String text) =>
    text.endsWith('\n') ? text.substring(0, text.length - 1) : text;

/// Extracts the language name from the fence's info string
/// (`class="language-xxx"`), or null when there is none.
String? _codeLanguage(md.Element code) {
  const prefix = 'language-';
  for (final cls in code.attributes['class']?.split(' ') ?? const <String>[]) {
    if (cls.startsWith(prefix)) return cls.substring(prefix.length);
  }
  return null;
}

/// Runs the graphemes of [text] through [cursor] and turns them into a single
/// [TextSpan] with the reveal state not yet applied (the contract: 1 span =
/// 1 AST text node). [applyReveal] applies the reveal state afterwards.
List<InlineSpan> _plainSpan(
  String text,
  _RevealCursor cursor,
  TextStyle style,
) {
  if (text.isEmpty) return const [];
  for (final char in text.characters) {
    cursor.consume(char);
  }
  return [TextSpan(text: text, style: style)];
}

/// The traversal state that assigns reveal start times to the visible
/// characters, based on the common prefix.
///
/// [now] is the current frame's timestamp. Characters past the common prefix
/// with the previous frame's visible text (`previousChars`/`previousStarts`)
/// take this [now] as their reveal start time (characters newly drawn in the
/// same frame all start revealing together; already revealed characters carry
/// over their start time from the previous frame, so they do not reveal
/// again).
class _RevealCursor {
  _RevealCursor({
    required this.now,
    required this._previousChars,
    required this._previousStarts,
    required this.fade,
    this.forceOpaque = false,
  });

  final Duration now;
  final List<String> _previousChars;
  final List<Duration> _previousStarts;

  /// How fast a character reveals ([StreamingReplyController.style]'s
  /// `fadeDuration` — see the time-fields split in the [StreamingReplyStyle]
  /// class doc).
  final Duration fade;

  /// When true, only the characters from the position where the visible text
  /// differs from the previous frame onward are settled as revealed
  /// (opacity 1) immediately (Q11: used only on the first frame where
  /// complete flips from false to true. Characters at positions that have not
  /// changed carry over their reveal start time from the previous frame as
  /// usual and are not redrawn if they are still revealing — when the visible
  /// text is identical before and after the switch, as with sampleReply,
  /// nothing changes at all).
  final bool forceOpaque;

  int _index = 0;
  bool _matchesPrevious = true;

  /// Whether there was at least one revealing character (opacity below 1).
  bool hasRevealing = false;

  /// The visible characters traversed in this frame (they become the next
  /// frame's `previousChars`).
  final List<String> chars = [];

  /// The reveal start times paired with [chars] (they become the next frame's
  /// `previousStarts`).
  final List<Duration> starts = [];

  /// The revealing characters (opacity below 1) traversed so far, at their
  /// absolute position within [chars]. A block slices its own range out of
  /// this with [revealingSlice] once it has finished consuming.
  final List<RevealingChar> revealing = [];

  /// Advances by one character.
  void consume(String char) {
    Duration start;
    // If the new grapheme starts with the old one (a combining mark arrived
    // and absorbed the old one), treat it as the same character and carry
    // over its reveal start time. Narrowing this to an exact match would
    // mean, for example, that the moment a combining mark arrives after `e`
    // and makes it `é`, it is treated as a different character and redrawn
    // from opacity 0.
    if (_matchesPrevious &&
        _index < _previousChars.length &&
        char.startsWith(_previousChars[_index])) {
      start = _previousStarts[_index];
    } else {
      _matchesPrevious = false;
      // Q11: while forceOpaque is set, only the characters from the position
      // where the visible text differs from the previous frame (here) onward
      // are made revealed immediately. If nothing has changed, the branch
      // above carries over the previous reveal start time, so this point is
      // never reached.
      start = forceOpaque ? now - fade : now;
    }
    chars.add(char);
    starts.add(start);
    _index++;

    final elapsed = now - start;
    final opacity = elapsed >= fade ? 1.0 : revealOpacity(elapsed, fade);
    if (opacity < 1) {
      hasRevealing = true;
      revealing.add(
        RevealingChar(index: chars.length - 1, char: char, opacity: opacity),
      );
    }
  }
}
