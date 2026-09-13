import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:markdown/markdown.dart' as md;

import 'markdown_blockquote.dart';
import 'markdown_code_block.dart';
import 'markdown_heading.dart';
import 'markdown_list.dart';
import 'markdown_paragraph.dart';
import 'markdown_table.dart';
import 'partial_markdown.dart';
import 'reply_theme.dart';
import 'reveal_clock.dart' show revealOpacity;
import 'reveal_ticker.dart' show syncTicker;
import 'streaming_reply_controller.dart';

/// Controller の 1 区分 (思考か返答) の `revealedText` を描く Widget。
///
/// [formatted] が true なら Markdown として整形し (見出し・段落・太字・斜体・
/// インラインコード・コードブロック・箇条書き・番号リスト・引用・リンク・表)、
/// false なら素の文字 (改行はそのまま改行) を描く。どちらも同じ出現の仕組みを
/// 使う: 可視文字を AST の走査順 (formatted: false なら文字の並び順そのもの) に
/// 通し番号を振り、前フレームの可視文字列との共通接頭辞より後ろを「今描かれた
/// 文字」として出現開始時刻を付ける (書きかけの記法のために描かれていなかった
/// 文字が、描かれた時点で一斉に出現を始めるのもこの仕組みで説明できる)。
/// 出現中の文字だけを 1 文字 (書記素) 1 TextSpan にして style の色のアルファで
/// 不透明度を出し、表示済みの文字は 1 つの span にまとめる。
///
/// [StreamingReplyController] を listen して再描画するほか、出現中の可視文字が
/// ある間は自前の Ticker で再描画を続ける (Controller 側の needsTicks が false
/// になった後も、その時点で出現中の文字の 300ms を描き切るため)。
class RevealedMarkdown extends StatefulWidget {
  const RevealedMarkdown({
    super.key,
    required this.controller,
    required this.kind,
    this.formatted = true,
  });

  /// 出現状態を含む観測値の入り口。
  final StreamingReplyController controller;

  /// どちらの区分を描くか。
  final ChunkKind kind;

  /// Markdown として整形するかどうか。
  final bool formatted;

  @override
  State<RevealedMarkdown> createState() => _RevealedMarkdownState();
}

class _RevealedMarkdownState extends State<RevealedMarkdown>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;

  /// 前フレームで描いた可視文字 (書記素)。共通接頭辞の比較に使う。
  List<String> _previousChars = const [];

  /// [_previousChars] と対になる、各文字の出現開始時刻。
  List<Duration> _previousStarts = const [];

  /// 直近のフレームで読み取った [SchedulerBinding.currentFrameTimeStamp]。
  /// フレーム外 (`schedulerPhase == idle`、冷間起動の最初の attach など) では
  /// `currentFrameTimeStamp` の読み取りが assert に当たるため、そのときは
  /// これ (無ければ [Duration.zero]) を使う。
  Duration _lastFrameTime = Duration.zero;

  /// 直前のフレームで [build] が算出した「受信完了として parse してよいか」
  /// (前フレームの `complete`)。false → true に切り替わった最初のフレームを
  /// 検出するのに使う (Q11: 書きかけのまま閉じていた記法が、受信完了後の
  /// 生の記号込みの文字列に置き換わって可視文字列の形が変わる瞬間、表示済み
  /// だった文字が出現し直すのを防ぐ)。
  bool _wasComplete = false;

  /// 直前に parse した `(revealedText, complete)` と、その結果の AST。
  /// 可視文字列も [complete] も変わっていないフレーム (毎フレーム描き直す間の
  /// 少なくとも 1/3) は parse をやり直さない — AST は読むだけで書き換えない
  /// ([_buildBlocks] 以下は Widget を作るだけ) ので使い回して安全。
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
    _ticker = createTicker((_) => setState(() {}));
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(covariant RevealedMarkdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
    if (oldWidget.controller != widget.controller || oldWidget.kind != widget.kind) {
      // controller / kind が変わったら、別の文字列を描くことになるので
      // 前フレームの可視文字列との共通接頭辞比較をリセットする (でないと
      // 無関係な文字列同士を比較して出現開始時刻を誤って引き継ぐ)。
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
    final section = widget.kind == ChunkKind.thinking
        ? widget.controller.thinking
        : widget.controller.reply;
    final baseStyle = widget.kind == ChunkKind.thinking
        ? ReplyTheme.thinkingTextStyle
        : ReplyTheme.bodyTextStyle;
    final now = SchedulerBinding.instance.schedulerPhase == SchedulerPhase.idle
        ? _lastFrameTime
        : SchedulerBinding.instance.currentFrameTimeStamp;
    _lastFrameTime = now;

    // 受信完了済みで、受信した文字が (出現の途中であっても) 全て出現を
    // 始めていれば、これで全文として parse する (書きかけの記法を保留・仮閉じ
    // したまま永久に固定されるのを防ぐ)。
    final complete = widget.controller.isComplete && section.startedCount == section.receivedCount;
    // complete が false → true に切り替わる最初のフレームだけ、可視文字列が
    // 前フレームと変わった位置以降の文字を即座に「表示済み」として確定する
    // (Q11)。整形あり (formatted) のときだけ関係する — 書きかけの記法を
    // 保留・仮閉じした可視文字列と、受信完了後の生の記号込みの可視文字列とで、
    // 同じ表示済みの部分の形が変わり得るのはこの経路だけのため。可視文字列が
    // 変わっていなければ (sampleReply など) このフレームは何も変えない。
    final justCompleted = widget.formatted && complete && !_wasComplete;
    _wasComplete = complete;
    final cursor = _RevealCursor(
      now: now,
      previousChars: _previousChars,
      previousStarts: _previousStarts,
      forceOpaque: justCompleted,
    );

    final child = widget.formatted
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: _buildBlocks(
              _parseCached(section.revealedText, complete),
              cursor,
              baseStyle,
            ),
          )
        : Text.rich(TextSpan(style: baseStyle, children: _revealSpans(section.revealedText, cursor, baseStyle)));

    _previousChars = cursor.chars;
    _previousStarts = cursor.starts;

    syncTicker(_ticker, wanted: cursor.hasRevealing);

    return child;
  }
}

/// ブロック 1 つと、その下余白。
class _Block {
  const _Block(this.widget, this.spacingBottom);

  final Widget widget;
  final double spacingBottom;
}

/// 引用の入れ子で [_buildBlocks] が再帰する深さの上限 (安い保険。作り物の
/// サンプルの範囲を超える数千段の入れ子で `StackOverflowError` になるのを防ぐ。
/// パーサー自身の再帰までは面倒を見ない)。
const _maxBlockDepth = 16;

/// ブロックの並びを Widget の並びにする (末尾以外の下余白を SizedBox で挟む)。
List<Widget> _buildBlocks(
  List<md.Node> nodes,
  _RevealCursor cursor,
  TextStyle ambientStyle, {
  int depth = 0,
}) {
  final blocks = <_Block>[
    for (final node in nodes) ?_buildBlock(node, cursor, ambientStyle, depth),
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

/// [spans] を [style] で段落として描く [_Block] (下余白は [ReplyTheme.blockSpacing])。
/// 裸の `Text` の安全網・`p`・引用の深さ上限・未知タグの安全網の 4 か所で使う。
_Block _paragraphBlock(List<InlineSpan> spans, TextStyle style) =>
    _Block(MarkdownParagraph(spans: spans, style: style), ReplyTheme.blockSpacing);

_Block? _buildBlock(md.Node node, _RevealCursor cursor, TextStyle ambientStyle, int depth) {
  if (node is md.Text) {
    // 安全網: 登録したブロック構文はトップレベルに裸の Text を返さないが、
    // 念のため段落として描く。
    return _paragraphBlock(_revealSpans(node.text, cursor, ambientStyle), ambientStyle);
  }
  if (node is! md.Element) return null;

  switch (node.tag) {
    case 'h1':
    case 'h2':
    case 'h3':
    case 'h4':
    case 'h5':
    case 'h6':
      final level = int.parse(node.tag.substring(1));
      final style = headingStyleFor(level, ambientStyle);
      return _Block(
        MarkdownHeading(
          level: level,
          style: style,
          spans: _buildInlineSpans(node.children, cursor, style, depth: depth),
        ),
        level <= 2 ? ReplyTheme.h2SpacingBottom : ReplyTheme.h3SpacingBottom,
      );

    case 'p':
      return _paragraphBlock(
        _buildInlineSpans(node.children, cursor, ambientStyle, depth: depth),
        ambientStyle,
      );

    case 'ul':
    case 'ol':
      final items = <MarkdownListItem>[
        for (final item in node.children ?? const <md.Node>[])
          if (item is md.Element) _buildListItem(item, cursor, ambientStyle, depth),
      ];
      return _Block(
        MarkdownList(ordered: node.tag == 'ol', items: items, style: ambientStyle),
        ReplyTheme.blockSpacing,
      );

    case 'blockquote':
      final quoteStyle = ambientStyle.copyWith(color: ReplyTheme.quoteTextColor);
      if (depth >= _maxBlockDepth) {
        // 深さの上限を超えた部分木は、それ以上再帰せず素の段落として描く。
        return _paragraphBlock(
          _buildInlineSpans(node.children, cursor, quoteStyle, depth: depth),
          quoteStyle,
        );
      }
      return _Block(
        MarkdownBlockquote(
          children: _buildBlocks(node.children ?? const [], cursor, quoteStyle, depth: depth + 1),
        ),
        ReplyTheme.blockSpacing,
      );

    case 'pre':
      final code = _firstElement(node.children);
      final text = code == null ? '' : _stripFencedTrailingNewline(_codeText(code));
      return _Block(
        MarkdownCodeBlock(spans: _revealSpans(text, cursor, ReplyTheme.codeBlockTextStyle)),
        ReplyTheme.blockSpacing,
      );

    case 'table':
      return _Block(_buildTable(node, cursor, depth), ReplyTheme.blockSpacing);

    default:
      // 対応表に無いタグの安全網: children があれば子の文字をそのまま素の文字で
      // 描き、children が null (自己完結要素) なら何も描かない。
      final children = node.children;
      if (children == null) return null;
      return _paragraphBlock(
        _buildInlineSpans(children, cursor, ambientStyle, depth: depth),
        ambientStyle,
      );
  }
}

/// `li` 1 つを、インライン部分と、それに続く子ブロック (入れ子の
/// `MarkdownList`、緩い項目の続きの段落など) に分ける ([Q15])。
///
/// タイトな項目 (`<li>text<ul>…</ul></li>`) は、先頭から `ul`/`ol`/`p` が
/// 現れるまでをインライン部分とする。緩い項目 (`<li><p>text</p><ul>…</ul></li>`)
/// は最初の `p` の中身がインライン部分で、そこから先が子ブロック。
MarkdownListItem _buildListItem(md.Element li, _RevealCursor cursor, TextStyle style, int depth) {
  final children = li.children ?? const <md.Node>[];
  final List<md.Node> inlineNodes;
  final List<md.Node> blockNodes;
  final first = children.isEmpty ? null : children.first;
  if (first is md.Element && first.tag == 'p') {
    inlineNodes = first.children ?? const <md.Node>[];
    blockNodes = children.skip(1).toList(growable: false);
  } else {
    final splitAt = children.indexWhere(
      (n) => n is md.Element && (n.tag == 'ul' || n.tag == 'ol' || n.tag == 'p'),
    );
    if (splitAt == -1) {
      inlineNodes = children;
      blockNodes = const [];
    } else {
      inlineNodes = children.sublist(0, splitAt);
      blockNodes = children.sublist(splitAt);
    }
  }
  return MarkdownListItem(
    inline: _buildInlineSpans(inlineNodes, cursor, style, depth: depth),
    children: depth >= _maxBlockDepth
        ? const []
        : _buildBlocks(blockNodes, cursor, style, depth: depth + 1),
  );
}

Widget _buildTable(md.Element table, _RevealCursor cursor, int depth) {
  md.Element? thead;
  md.Element? tbody;
  for (final child in table.children ?? const <md.Node>[]) {
    if (child is md.Element && child.tag == 'thead') thead = child;
    if (child is md.Element && child.tag == 'tbody') tbody = child;
  }
  final headerRow = _firstElement(thead?.children);
  final headerCells = <List<InlineSpan>>[
    for (final cell in headerRow?.children ?? const <md.Node>[])
      if (cell is md.Element)
        _buildInlineSpans(cell.children, cursor, ReplyTheme.tableHeaderTextStyle, depth: depth),
  ];
  final bodyRows = <List<List<InlineSpan>>>[
    for (final row in tbody?.children ?? const <md.Node>[])
      if (row is md.Element)
        <List<InlineSpan>>[
          for (final cell in row.children ?? const <md.Node>[])
            if (cell is md.Element)
              _buildInlineSpans(cell.children, cursor, ReplyTheme.tableTextStyle, depth: depth),
        ],
  ];
  return MarkdownTable(headerCells: headerCells, bodyRows: bodyRows);
}

/// ノードの並びを [InlineSpan] の並びにする。[depth] は入れ子の深さの上限
/// ([_maxBlockDepth]) を数えるための引き回し (ブロック側の深さと同じカウンタを
/// 共有する — `strong`/`em`/`a`/未知タグの入れ子もこれ以上再帰しない安全網)。
///
/// 画像記法 (`![alt](href)`) は前処理 ([partial_markdown.dart] の
/// `_escapeImageMarkers`) が `![` を `\!\[` にエスケープ済みなので、ここに
/// 画像だけの特別扱いは無い — パーサーが画像にもリンクにもせず、素の文字
/// (`md.Text`) としてそのまま渡ってくる。
List<InlineSpan> _buildInlineSpans(List<md.Node>? nodes, _RevealCursor cursor, TextStyle style, {int depth = 0}) {
  if (nodes == null) return const [];
  final spans = <InlineSpan>[];
  for (final node in nodes) {
    spans.addAll(_buildInline(node, cursor, style, depth: depth));
  }
  return spans;
}

List<InlineSpan> _buildInline(md.Node node, _RevealCursor cursor, TextStyle style, {int depth = 0}) {
  if (node is md.Text) {
    return _revealSpans(node.text, cursor, style);
  }
  if (node is! md.Element) return const [];

  if (depth >= _maxBlockDepth) {
    // 深さの上限を超えた部分木は、それ以上再帰せず素の文字として描く。
    return _revealSpans(node.textContent, cursor, style);
  }

  switch (node.tag) {
    case 'strong':
      return _buildInlineSpans(node.children, cursor, style.copyWith(fontWeight: FontWeight.w700), depth: depth + 1);
    case 'em':
      return _buildInlineSpans(node.children, cursor, style.copyWith(fontStyle: FontStyle.italic), depth: depth + 1);
    case 'code':
      // 周囲の style に merge する (下線・太さなど、コード自身が指定しない
      // ぶんは周囲を引き継ぐ。色・地の色・字体などコードが指定するぶんは
      // 周囲より優先する)。
      return _revealSpans(_codeText(node), cursor, style.merge(ReplyTheme.inlineCodeTextStyle));
    case 'a':
      final linkStyle = style.copyWith(
        color: ReplyTheme.linkColor,
        decoration: TextDecoration.underline,
      );
      return _buildInlineSpans(node.children, cursor, linkStyle, depth: depth + 1);
    case 'br':
      // 自己完結要素 (children が null) の改行。
      return _revealSpans('\n', cursor, style);
    default:
      // 対応表に無いタグの安全網。children が null なら何も描かない。
      final children = node.children;
      if (children == null) return const [];
      return _buildInlineSpans(children, cursor, style, depth: depth + 1);
  }
}

md.Element? _firstElement(List<md.Node>? nodes) {
  if (nodes == null) return null;
  for (final node in nodes) {
    if (node is md.Element) return node;
  }
  return null;
}

/// `code` 要素の中身 (`Element.text` が作る、Text の子 1 つ) を取り出す。
String _codeText(md.Element node) =>
    (node.children ?? const <md.Node>[]).whereType<md.Text>().map((t) => t.text).join();

/// `FencedCodeBlockSyntax` がコードブロックの中身の末尾に付ける改行を 1 つ
/// だけ剥がす (無いと全てのコードブロックが 1 行ぶん高く描かれる)。
String _stripFencedTrailingNewline(String text) =>
    text.endsWith('\n') ? text.substring(0, text.length - 1) : text;

/// [text] の書記素を [cursor] に通し、表示済みの連続区間を 1 つの span に
/// まとめ、出現中の文字だけを 1 文字 1 span にする (契約: 表示済みのインライン
/// 1 区間 = AST のテキストノードと完全一致する 1 span)。
List<InlineSpan> _revealSpans(String text, _RevealCursor cursor, TextStyle style) {
  if (text.isEmpty) return const [];
  final spans = <InlineSpan>[];
  final buffer = StringBuffer();
  for (final char in text.characters) {
    final opacity = cursor.consume(char);
    if (opacity >= 1) {
      buffer.write(char);
      continue;
    }
    if (buffer.isNotEmpty) {
      spans.add(TextSpan(text: buffer.toString(), style: style));
      buffer.clear();
    }
    // インラインコードの地の色など、backgroundColor を持つ style は
    // そのアルファも文字色と同じ不透明度に下げる (でないと出現中の文字の
    // 地の色だけ先に不透明で現れる)。
    spans.add(
      TextSpan(
        text: char,
        style: style.copyWith(
          color: style.color?.withValues(alpha: opacity),
          backgroundColor: style.backgroundColor?.withValues(alpha: opacity),
        ),
      ),
    );
  }
  if (buffer.isNotEmpty) {
    spans.add(TextSpan(text: buffer.toString(), style: style));
  }
  return spans;
}

/// 可視文字に、共通接頭辞をもとに出現開始時刻を割り当てる走査状態。
///
/// [now] は現在のフレーム時刻。前フレームの可視文字列 (`previousChars`/
/// `previousStarts`) との共通接頭辞より後ろの文字は、この [now] を出現開始
/// 時刻にする (同じフレームで新しく描かれた文字は一斉に出現を始める。表示済み
/// の文字は前フレームの開始時刻を引き継ぐので出現し直さない)。
class _RevealCursor {
  _RevealCursor({
    required this.now,
    required this._previousChars,
    required this._previousStarts,
    this.forceOpaque = false,
  });

  final Duration now;
  final List<String> _previousChars;
  final List<Duration> _previousStarts;

  /// true なら、前フレームの可視文字列と比べて変わった位置以降の文字だけを
  /// 即座に表示済み (不透明度 1) として確定する (Q11: complete が false →
  /// true に切り替わる最初のフレームだけ使う。変わっていない位置の文字は
  /// 通常どおり前フレームの出現開始時刻を引き継ぎ、フェード中なら描き直さない
  /// — sampleReply のように切替の前後で可視文字列が同一なら何も変えない)。
  final bool forceOpaque;

  int _index = 0;
  bool _matchesPrevious = true;

  /// 出現中 (不透明度 1 未満) の文字が 1 つでもあったか。
  bool hasRevealing = false;

  /// 今フレームで走査した可視文字 (次フレームの `previousChars` になる)。
  final List<String> chars = [];

  /// [chars] と対になる出現開始時刻 (次フレームの `previousStarts` になる)。
  final List<Duration> starts = [];

  /// 1 文字進め、その不透明度 (0〜1) を返す。
  double consume(String char) {
    Duration start;
    // 新しい書記素が古い書記素で始まる (結合文字が届いて古いものを吸収した)
    // なら同じ文字とみなし、出現開始時刻を引き継ぐ。厳密な一致に絞ると、
    // 例えば `e` の後に結合文字が届いて `é` になった瞬間に別の文字として
    // 扱われ、不透明度 0 から描き直されてしまう。
    if (_matchesPrevious &&
        _index < _previousChars.length &&
        char.startsWith(_previousChars[_index])) {
      start = _previousStarts[_index];
    } else {
      _matchesPrevious = false;
      // Q11: forceOpaque の間は、前フレームの可視文字列と変わった位置
      // (ここ) 以降の文字だけを即座に表示済みにする。変わっていなければ
      // 上の分岐で前の出現開始時刻を引き継ぐのでここには来ない。
      start = forceOpaque ? now - ReplyTheme.fadeDuration : now;
    }
    chars.add(char);
    starts.add(start);
    _index++;

    final elapsed = now - start;
    if (elapsed >= ReplyTheme.fadeDuration) return 1;
    hasRevealing = true;
    return revealOpacity(elapsed, ReplyTheme.fadeDuration);
  }
}
