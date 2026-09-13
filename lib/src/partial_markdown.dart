import 'package:markdown/markdown.dart';

/// フェンスの開始・終了行の判定に使う正規表現。`package:markdown` 7.3.1 の
/// `FencedCodeBlockSyntax().pattern` (`codeFencePattern`) をそのまま使う
/// (自前の正規表現は情報文字列にバッククォートを許してしまい、
/// ```` ```a`b ```` のような行を開きフェンスと誤認する)。名前付きグループ
/// `backtick`/`backtickInfo`/`tilde`/`tildeInfo` を持つ。
final _fenceLinePattern = const FencedCodeBlockSyntax().pattern;

const _asterisk = 0x2A;
const _underscore = 0x5F;
const _backquote = 0x60;
const _backslash = 0x5C;
const _newline = 0x0A;
const _space = 0x20;
const _tab = 0x09;
const _hyphen = 0x2D;
const _plus = 0x2B;
const _pipe = 0x7C;
const _colon = 0x3A;
const _leftBracket = 0x5B;
const _rightBracket = 0x5D;
const _leftParen = 0x28;
const _exclamation = 0x21;
const _greaterThan = 0x3E;
const _period = 0x2E;
const _rightParen = 0x29;
const _hash = 0x23;

/// plan が明示登録した構文だけで [Document] を作る。parse するたびに作り直す
/// (リンク参照定義の状態を持ち越さないため)。前処理の内部での再 parse
/// (フェンス・表の判定、記号閉じの検証) にも同じ構文を使う — 判定はすべて
/// この「パーサーそのもの」に委ねる。
Document _rawDocument() => Document(
  withDefaultBlockSyntaxes: false,
  withDefaultInlineSyntaxes: false,
  encodeHtml: false,
  blockSyntaxes: const [
    EmptyBlockSyntax(),
    HeaderSyntax(),
    FencedCodeBlockSyntax(),
    BlockquoteSyntax(),
    UnorderedListSyntax(),
    OrderedListSyntax(),
    TableSyntax(),
    ParagraphSyntax(),
  ],
  inlineSyntaxes: [
    EscapeSyntax(),
    EmphasisSyntax.asterisk(),
    EmphasisSyntax.underscore(),
    CodeSyntax(),
    LinkSyntax(),
    LineBreakSyntax(),
    SoftLineBreakSyntax(),
  ],
);

/// [parseReplyMarkdown] 1 回の呼び出しの中でだけ有効な、文字列 → parse 結果の
/// メモ。[parseReplyMarkdown] が呼び出しの最初に確保し最後に元に戻す (呼び出し
/// をまたいでは残らない・再入しても外側の呼び出しを壊さない)。null の間は
/// メモを取らずそのまま parse する。
Map<String, List<Node>>? _parseMemo;

/// [_rawDocument] で [text] を parse する。同じ呼び出しの中で同じ文字列を
/// 保留判定 ([_lastTopLevelTag])・ブロック特定 ([_findClosingTarget] の
/// root parse)・最終 parse などで 2〜3 回 parse することがあるため、
/// [_parseMemo] があればその結果を持ち回す (実測で 31〜45% 短縮)。
List<Node> _parse(String text) {
  final memo = _parseMemo;
  if (memo == null) return _rawDocument().parse(text);
  return memo.putIfAbsent(text, () => _rawDocument().parse(text));
}

/// 出現位置までの Markdown (書きかけの記法を含む) を、パーサーに渡せる閉じた形にする前処理。
///
/// 届いた文字を落とすか閉じ記号を足すかだけを行い、順序や中身は書き換えない。
/// `\r\n` `\r` は先に `\n` へそろえる (供給元が CRLF でも区切り行の判定などが
/// 崩れないため)。2 つの段を順に適用する:
///
/// 1. [_applyRenderingFidelity] (描画忠実性の段。[complete] の値によらず常に
///    適用する): 画像記法 `![alt](url)` を `\!\[alt](url)` にエスケープし、
///    パーサーに画像にもリンクにもさせない
///    (spec「画像は整形されず記号のままの文字として出る」)。
/// 2. [_applyReceivingHoldbacks] (受信中限定の段。[complete] が true なら
///    適用しない): 末尾の行レベルの保留と、最後のブロックの記号閉じ・リンク
///    確定。
///
/// [complete] が true (受信完了) なら 1 の結果をそのまま返す — これで全文
/// なので書きかけの記法は何も落とさず何も閉じない (受信完了後も 2 の段を
/// 続けると、届き終わった文字が永久に消えたり生の記号のまま残ったりする経路に
/// なるため)。
///
/// 判定の基本方針: **パーサーそのものを判定器にする**。フェンスの検出だけは
/// 行単位の正規表現 ([_fenceLineFlags]) に頼るが、それ以外の「これは表として
/// 成立しているか」「これは強調記号として閉じられるか」は、実際に候補の文字列を
/// [_rawDocument] で parse して結果を見て決める。
///
/// - 閉じていないコードフェンスの中身は触らない。ただしフェンスの内側の最後の
///   行が同じフェンス文字 1〜2 個だけ (3 個未満で閉じフェンスにまだ届かない)
///   なら、閉じフェンスの書きかけとみなしてその行を落とす
/// - 表になり得る末尾の行 (区切り行の書きかけ・見出し行の候補・確定した表の
///   本体行・散文中の伸びかけの `|`) を、パーサーで「表として成立するか」を
///   確かめながら保留する。ブロック記号になり得る末尾の行 (数字だけ・`-`/`+`
///   1 文字だけ) も、次の文字で箇条書きになるかが決まるまで保留する
/// - 最後の (受信中の) ブロックの末尾に残った、閉じていない `**` `*` `__` `_`
///   `` ` `` を候補として見つけ、実際に閉じ記号を足して再 parse し、
///   `strong`/`em`/`code` として消費されたことを確かめてから採用する
/// - 書きかけのリンク `[ラベル` / `[ラベル](https://…` はラベルだけの素の文字に
///   する。画像記法 `![alt](url)` は [_applyRenderingFidelity] が `![` を
///   `\!\[` にエスケープ済みなので、この対象からは自然に外れる
String closePartialMarkdown(String partial, {bool complete = false}) {
  final normalized = partial.contains('\r')
      ? partial.replaceAll('\r\n', '\n').replaceAll('\r', '\n')
      : partial;
  // フェンスの判定 (行単位の正規表現) と run への分割は、描画忠実性の段と
  // 受信中限定の段で 1 度だけ計算して共有する (画像エスケープは行数も
  // フェンス判定も変えないため、同じ [runs] をどちらの段にもそのまま使える)。
  final lines = normalized.split('\n');
  final isFenceLine = _fenceLineFlags(lines);
  final runs = _splitRuns(isFenceLine);

  final rendered = _applyRenderingFidelity(lines, runs, complete: complete);
  if (complete) return rendered;
  return _applyReceivingHoldbacks(rendered, runs);
}

/// plan の明示登録した構文で [Document] を作り、[closePartialMarkdown] を通した
/// 文字列を parse する。[complete] は [closePartialMarkdown] にそのまま渡す。
List<Node> parseReplyMarkdown(String partial, {bool complete = false}) {
  final outerMemo = _parseMemo;
  _parseMemo = {};
  try {
    return _parse(closePartialMarkdown(partial, complete: complete));
  } finally {
    _parseMemo = outerMemo;
  }
}

// ── 描画忠実性の段 (画像記法のエスケープ。Q8: 描画側の再合成をやめ、前処理で
// 記号のまま固定する。[complete] の値によらず常に適用する) ──

/// [lines] を [runs] ([_fenceLineFlags] → [_splitRuns] で求めた、フェンスかどうか
/// で分けた区間) ごとに処理する: フェンスの中身はそのまま素通りさせ、それ以外は
/// [_escapeImageMarkersInText] で `![alt](url)` の `![` を `\!\[` に変え、
/// パーサーに画像にもリンクにもさせない
/// (spec「画像は整形されず記号のままの文字として出る」)。
///
/// - フェンスの中身は触らない ([runs] の [_LineRun.isFence] で行単位に判定
///   済みの run をそのまま素通りさせる)
/// - コードスパンの中身は触らない。詳細は [_escapeImageMarkersInText] を参照
/// - `!` 自身がすでにエスケープされている (直前のバックスラッシュと対になって
///   いる) 場合は画像記法ではないので触らない — バックスラッシュ + 直後の 1
///   文字を常にペアで読み飛ばすことで、奇数個目のバックスラッシュだけが直後の
///   文字をエスケープする CommonMark の規則を自然に満たす
///   (`a\![重要](url)` は `\!` が先にペアで消費されるので、残る `[重要](url)`
///   はリンクになる)
String _applyRenderingFidelity(
  List<String> lines,
  List<_LineRun> runs, {
  required bool complete,
}) {
  final parts = <String>[
    for (final run in runs)
      if (run.isFence)
        lines.sublist(run.start, run.end).join('\n')
      else
        _escapeImageMarkersInText(
          lines.sublist(run.start, run.end).join('\n'),
          complete: complete,
        ),
  ];
  return parts.join('\n');
}

/// [_applyRenderingFidelity] の 1 run ぶん (フェンスの外側。複数行をまたぐ
/// コードスパンも扱えるよう、行ごとではなく joined な文字列全体を走査する)。
///
/// `![` を含まなければエスケープする対象が無く出力は入力と同一になるので、
/// 1 文字ずつの走査そのものを省いて入力をそのまま返す。
String _escapeImageMarkersInText(String text, {required bool complete}) {
  if (!text.contains('![')) return text;
  final buffer = StringBuffer();
  var i = 0;
  // 閉じた画像 (`![alt](url)` が同じ行で完結) の `]` の位置。着いたら `\]`
  // にエスケープし、外側のリンクの `[` を閉じる記号として使われないようにする
  // ([Q10] リンクの中の画像 `[![alt](img)](href)`)。
  int? pendingImageCloseBracket;
  while (i < text.length) {
    if (i == pendingImageCloseBracket) {
      buffer.write(r'\]');
      i++;
      pendingImageCloseBracket = null;
      continue;
    }
    final ch = text.codeUnitAt(i);
    if (ch == _backquote) {
      final openEnd = _runEnd(text, i, _backquote);
      final closeEnd = _codeSpanCloseEndWithinParagraph(text, i, openEnd - i);
      if (closeEnd == null) {
        if (!complete && text.indexOf('\n\n', openEnd) == -1) {
          // 受信中で、かつここが最後のまだ終わっていない段落: 後から閉じる
          // バッククォートが届くかもしれないので、従来どおり残り全部を
          // コードスパンの内側として触らない。
          buffer.write(text.substring(i));
          return buffer.toString();
        }
        // 受信完了後、または (受信中でも) すでに段落が空行で終わっている:
        // 同じ段落の中に対になる閉じるバッククォートが無いと分かったので、
        // コードスパンの内側と決めつけず素の文字として書き、直後から
        // エスケープを続ける ([Q5])。段落がすでに終わっている場合にここへ
        // 進むのは、対にならないバッククォートのせいで以降の文書全体の
        // 画像エスケープが止まらないようにするため。
        buffer.write(text.substring(i, openEnd));
        i = openEnd;
        continue;
      }
      buffer.write(text.substring(i, closeEnd));
      i = closeEnd;
      continue;
    }
    if (ch == _backslash && i + 1 < text.length) {
      buffer
        ..write(text[i])
        ..write(text[i + 1]);
      i += 2;
      continue;
    }
    if (ch == _exclamation && i + 1 < text.length && text.codeUnitAt(i + 1) == _leftBracket) {
      final closedImage = _closedLinkLabelRange(text, i + 1);
      if (closedImage != null) pendingImageCloseBracket = closedImage.$2;
      buffer.write(r'\!\[');
      i += 2;
      continue;
    }
    buffer.write(text[i]);
    i++;
  }
  return buffer.toString();
}

/// [_codeSpanCloseEnd] と同じだが、対応する閉じるバッククォートの並びを
/// 同じ段落 (次の空行まで) の中でだけ探す。段落をまたいだ対応は
/// `package:markdown` の `CodeSyntax` も別の段落として扱うため対にしない
/// ([Q5])。
int? _codeSpanCloseEndWithinParagraph(String text, int openStart, int openLength) {
  final closeEnd = _codeSpanCloseEnd(text, openStart, openLength);
  if (closeEnd == null) return null;
  final blankLine = text.indexOf('\n\n', openStart);
  if (blankLine != -1 && blankLine < closeEnd) return null;
  return closeEnd;
}

// ── 受信中限定の段 (末尾の行レベルの保留・最後のブロックの記号閉じ。
// [closePartialMarkdown] は [complete] が true ならこの段自体を呼ばない) ──

/// [rendered] ([_applyRenderingFidelity] を通した文字列) に、[runs] ごとの
/// 末尾の保留 ([_applyTrailingHoldbacks]) と最後のブロックの記号閉じ・リンク
/// 確定 ([_closeLastBlock]) を適用する。
///
/// [runs] は [closePartialMarkdown] がエスケープ前の行から計算したものを
/// そのまま受け取る — 画像エスケープは行数もフェンス判定も変えないため、
/// [rendered] に対しても同じ区間がそのまま使える。
String _applyReceivingHoldbacks(String rendered, List<_LineRun> runs) {
  final lines = rendered.split('\n');
  final parts = <String>[];
  for (var r = 0; r < runs.length; r++) {
    final run = runs[r];
    var runLines = lines.sublist(run.start, run.end);
    final isLastRun = r == runs.length - 1;
    if (run.isFence) {
      if (isLastRun) {
        runLines = _dropPendingFenceCloserLine(runLines);
      }
      parts.add(runLines.join('\n'));
      continue;
    }
    if (!isLastRun) {
      // 確定済みのブロック (この後にフェンスなど別の run が続く): 触らない。
      parts.add(runLines.join('\n'));
      continue;
    }
    runLines = _applyTrailingHoldbacks(runLines);
    parts.add(_closeLastBlock(runLines));
  }
  return parts.join('\n');
}

// ── フェンスの run 分割 (unchanged: 行単位の正規表現で十分に正しい) ──

/// [match] が捉えたフェンスの記号の並び (`` ` `` の連続または `~` の連続)。
String? _fenceMarker(RegExpMatch? match) =>
    match?.namedGroup('backtick') ?? match?.namedGroup('tilde');

/// [match] が捉えたフェンスの情報文字列。
String? _fenceInfo(RegExpMatch? match) =>
    match?.namedGroup('backtickInfo') ?? match?.namedGroup('tildeInfo');

/// 行が連続するフェンスの中かどうか (開始・終了行そのものも含む)。
List<bool> _fenceLineFlags(List<String> lines) {
  final flags = List<bool>.filled(lines.length, false);
  String? openMarker;
  for (var i = 0; i < lines.length; i++) {
    final match = _fenceLinePattern.firstMatch(lines[i]);
    final marker = _fenceMarker(match);
    if (openMarker == null) {
      if (marker != null) {
        openMarker = marker;
        flags[i] = true;
      }
      continue;
    }
    flags[i] = true;
    final info = _fenceInfo(match);
    if (marker != null &&
        marker[0] == openMarker[0] &&
        marker.length >= openMarker.length &&
        (info?.trim().isEmpty ?? false)) {
      openMarker = null;
    }
  }
  return flags;
}

/// フェンスかどうかが同じ行が連続する区間。
class _LineRun {
  _LineRun(this.isFence, this.start, this.end);

  final bool isFence;
  final int start;
  final int end;
}

List<_LineRun> _splitRuns(List<bool> isFenceLine) {
  final runs = <_LineRun>[];
  if (isFenceLine.isEmpty) return runs;
  var start = 0;
  for (var i = 1; i <= isFenceLine.length; i++) {
    if (i == isFenceLine.length || isFenceLine[i] != isFenceLine[start]) {
      runs.add(_LineRun(isFenceLine[start], start, i));
      start = i;
    }
  }
  return runs;
}

/// フェンスの中身の最後の行が、閉じフェンスの書きかけ (開いたフェンスと
/// 同じ文字が 1〜2 個だけ、他の文字を含まない) なら落とす。
///
/// 開いたフェンスの文字 (`` ` `` か `~`) は [lines] の最初の行 (開始行) から
/// 読み取る — 例えば `~~~` で開いたフェンスの中に単独の `` ` `` が来ても、
/// それは閉じフェンスの書きかけになり得ない (フェンスは開始行と同じ文字で
/// しか閉じられない) ので落とさない。
List<String> _dropPendingFenceCloserLine(List<String> lines) {
  if (lines.isEmpty) return lines;
  final openMarker = _fenceMarker(_fenceLinePattern.firstMatch(lines.first));
  if (openMarker == null) return lines;
  if (!_looksLikePendingFenceCloser(lines.last, openMarker.codeUnitAt(0))) return lines;
  return lines.sublist(0, lines.length - 1);
}

/// [line] が閉じフェンスの書きかけ (先頭の字下げ 3 スペースまでを除き、
/// 開いたフェンスと同じ文字 [openChar] が 1〜2 個だけ並ぶ) かどうか。
bool _looksLikePendingFenceCloser(String line, int openChar) {
  final trimmed = line.trimLeft();
  if (line.length - trimmed.length > 3) return false;
  if (trimmed.isEmpty || trimmed.length >= 3) return false;
  final first = trimmed.codeUnitAt(0);
  if (first != openChar) return false;
  for (final unit in trimmed.codeUnits) {
    if (unit != first) return false;
  }
  return true;
}

// ── 末尾の行レベルの保留 (表・ブロック記号の書きかけ) ──

/// 最後の (受信中の) 行を、表として成立するかどうかや、次の文字でブロック
/// 記号になり得るかどうかを見ながら保留する。
///
/// 判定は原則パーサーに委ねる (「表として成立したか」は列数を数えず、実際に
/// 候補の文字列を parse して結果のタグが `table` かどうかで決める)。
List<String> _applyTrailingHoldbacks(List<String> lines) {
  if (lines.isEmpty) return lines;

  // ブロック記号になり得る末尾の行 (数字だけ・`-`/`+`/`*` 1 文字だけなど):
  // 次の文字で番号リスト・箇条書きになるかが決まるまで保留する。保留しても
  // なお表の判定は続けて行う (単に「戻す」のではなく、以降の処理を続ける)。
  var current = lines;
  // 引用の中の保留対象は `>` を剥がした中身で判定する (剥がさないと
  // `> -` `> 2` の `>` 自身のせいで判定にかからず、保留されないまま
  // 生の記号が見えてしまう)。
  final droppedMarkerLine =
      current.last.isNotEmpty &&
      _looksLikePendingBlockMarkerLine(_stripBlockquotePrefix(current.last));
  if (droppedMarkerLine) {
    current = current.sublist(0, current.length - 1);
  }
  if (current.isEmpty) return current;

  final blankLineAtEnd = current.last.isEmpty;
  final core = blankLineAtEnd ? current.sublist(0, current.length - 1) : current;
  if (core.isEmpty) return current;
  // 「行末の改行が届いたか」: 元の行の並び ([lines]) から 1 行でも落ちて
  // いれば、その手前の行の改行はすでに届いている (マーカー行を落とした・
  // 空行を落とした、のどちらでも成り立つ)。
  final hasTrailingBlank = core.length < lines.length;

  final lastLine = core.last;
  final precedingCore = core.sublist(0, core.length - 1);

  // 「表として成立しているか」は、実際に parse させて結果の最後のトップ
  // レベル要素が table かどうかで決める (列数は数えない)。この行を含めても
  // 含めなくても表なら、この行はすでに成立した表の本体行の続き (空行を
  // 挟んでいれば含めた方は table にならないので、素通しの散文と区別できる)。
  // 含めたときだけ表になるなら、この行 (区切り行) が届いて初めて成立した
  // ということなので保留しない。
  final establishedIncludingLast = _lastTopLevelTag(core.join('\n')) == 'table';
  if (establishedIncludingLast) {
    final establishedBeforeLast =
        precedingCore.isNotEmpty && _lastTopLevelTag(precedingCore.join('\n')) == 'table';
    if (!establishedBeforeLast) return current; // 区切り行が今しがた成立させた。
    return hasTrailingBlank ? current : precedingCore; // 本体行: 改行待ち。
  }

  final previousLine = core.length >= 2 ? core[core.length - 2] : null;

  // 区切り行の書きかけ (`|` 1 文字だけの状態を含む): 見出し候補と組んで
  // 表として成立するか確かめる。組めない (前の行が無い・空・ブロック記号)
  // 場合は、これ以降の一般的な「表の行候補」判定に委ねる (`---` だけの行で
  // 前の行にも `|` が無ければ、そこでも該当せずそのまま素通しする)。
  if (_looksLikeDelimiterRowShape(lastLine) &&
      previousLine != null &&
      _isTableRowCandidate(previousLine)) {
    final established = _parsesAsTable(previousLine, lastLine);
    // 区切り行が改行まで届いていれば、この行がこれ以上変わることはない。
    // それでも表にならないなら、以後もならないので両方とも解放する
    // (改行が届く前はまだ書きかけなので、従来どおり保留を続ける)。
    if (established || hasTrailingBlank) return current;
    return core.sublist(0, core.length - 2);
  }

  if (_isTableRowCandidate(lastLine)) {
    final startsWithPipe = lastLine.trimLeft().startsWith('|');
    if (startsWithPipe) {
      // まだ表と確定していない見出し行候補 (`|` で始まる): 区切り行が届く
      // (か complete になる) まで、改行の有無によらず保留し続ける。
      return precedingCore;
    }
    // 散文の中の | : その | から行末までだけ保留する。改行が届いた時点で
    // (表でないと分かるので) 全部見せる。
    if (hasTrailingBlank) return current;
    final pipeIndex = _firstUnescapedPipeOutsideCodeSpan(lastLine)!;
    return [...precedingCore, lastLine.substring(0, pipeIndex)];
  }

  return current;
}

/// [line] がブロック記号になり得る末尾の行かどうか: 任意の字下げの後に
/// (`-`/`+`/`*` 1 文字、または数字 1〜9 桁 (`.` か `)` を伴ってもよい)) が
/// 続き、末尾に空白 (半角スペース・タブ) を 0〜1 個伴って行が終わる形。
/// 字下げされた入れ子のリスト記号 (`  - ` `   1.` など) もトップレベルと
/// 同じ規則で対象にする。`#` 単独は中身の空の見出しになり可視文字が増えない
/// ので対象にしない。
///
/// 字下げは ASCII の半角スペース・タブだけを字下げとして扱う
/// (`String.trimLeft` は Unicode の空白も剥がしてしまい、全角スペース
/// U+3000 で始まる `　1.` のような行までブロック記号候補にしてしまうため、
/// 自前で ASCII だけを剥がす)。
bool _looksLikePendingBlockMarkerLine(String line) {
  final trimmed = _trimAsciiLeadingWhitespace(line);
  if (trimmed.isEmpty) return false;

  var body = trimmed;
  final lastUnit = body.codeUnitAt(body.length - 1);
  if (body.length > 1 && (lastUnit == _space || lastUnit == _tab)) {
    body = body.substring(0, body.length - 1);
  }
  if (body.isEmpty) return false;

  if (body.length == 1) {
    final unit = body.codeUnitAt(0);
    if (unit == _hyphen || unit == _plus || unit == _asterisk) return true;
  }

  final digitsEnd = _digitRunEnd(body, 0);
  if (digitsEnd == 0) return false;
  if (digitsEnd == body.length) return true; // 数字だけ。
  if (digitsEnd == body.length - 1) {
    final marker = body.codeUnitAt(digitsEnd);
    return marker == _period || marker == _rightParen;
  }
  return false;
}

/// 行頭がブロック記号 (`#`, `- ` `* ` `+ ` `1. ` など, `> `, フェンス) かどうか。
/// これらで始まる行は表になれないので、表の見出し行候補として保留しない。
bool _startsWithBlockMarker(String line) {
  if (_looksLikeHeadingLine(line)) return true;
  if (_looksLikeListMarker(line)) return true;
  if (_startsWithBlockquoteMarker(line)) return true;
  if (_fenceLinePattern.hasMatch(line)) return true;
  return false;
}

/// 最後の 1 行だけを保留する対象になれるか (ブロック記号で始まらず、
/// コードスパン外の `|` を含む行)。`---` のようなパイプを含まない区切り行の
/// 書きかけは対象にしない ([_canPairWithHeaderCandidate] でだけ扱う)。
bool _isTableRowCandidate(String line) {
  if (_startsWithBlockMarker(line)) return false;
  return _firstUnescapedPipeOutsideCodeSpan(line) != null;
}

/// 区切り行の形 (`-` `:` `|` 空白だけの並びで、`|` か `-` を 1 文字以上含む)
/// かどうか。書きかけの区切り行 (まだハイフンが 1 つも届いていない途中の
/// 並びを含む) も表の行として認識するための緩い判定。「成立したか」自体は
/// [_parsesAsTable] で実際に parse して決める。`|` も `-` も無い (空白・`:`
/// だけの) 行は区切り行の書きかけとは見なさない — 空白だけの行や `:` 単独の
/// 散文の続きまで区切り行候補にすると、成立しなかったときに表示済みの前の
/// 行まで誤って消してしまう。
bool _looksLikeDelimiterRowShape(String line) {
  if (line.isEmpty) return false;
  var hasHyphenOrPipe = false;
  for (final unit in line.codeUnits) {
    if (unit == _hyphen || unit == _pipe) {
      hasHyphenOrPipe = true;
    } else if (unit != _colon && unit != _space && unit != _tab) {
      return false;
    }
  }
  return hasHyphenOrPipe;
}

/// [headerLine] + [delimiterLine] が実際に表として成立するか (パーサーに
/// 決めさせる。列数は数えない)。
bool _parsesAsTable(String headerLine, String delimiterLine) {
  final nodes = _parse('$headerLine\n$delimiterLine');
  return nodes.length == 1 && nodes.single is Element && (nodes.single as Element).tag == 'table';
}

/// [text] を parse した結果の、最後のトップレベル要素のタグ (無ければ null)。
String? _lastTopLevelTag(String text) {
  if (text.isEmpty) return null;
  final nodes = _parse(text);
  if (nodes.isEmpty) return null;
  final last = nodes.last;
  return last is Element ? last.tag : null;
}

/// 行の中に、コードスパンの外側でエスケープされていない `|` があれば、その
/// 位置を返す (閉じていないコードスパンの中は対象外)。無ければ null。
int? _firstUnescapedPipeOutsideCodeSpan(String line) {
  var i = 0;
  while (i < line.length) {
    final ch = line.codeUnitAt(i);
    if (ch == _backquote) {
      final openEnd = _runEnd(line, i, _backquote);
      final closeEnd = _codeSpanCloseEnd(line, i, openEnd - i);
      if (closeEnd == null) return null; // 閉じていない: 以降は全部内側。
      i = closeEnd;
      continue;
    }
    if (ch == _backslash && i + 1 < line.length) {
      i += 2;
      continue;
    }
    if (ch == _pipe) return i;
    i++;
  }
  return null;
}

/// 行頭のリスト記号 (`- ` `* ` `+ ` や `1. ` `12) ` など)。
bool _looksLikeListMarker(String line) => _listMarkerKind(line) != null;

bool _isDigit(int codeUnit) => codeUnit >= 0x30 && codeUnit <= 0x39;

/// [text] の [start] から始まる、連続する数字 (最大 9 桁) の終わりの index
/// (数字が無ければ [start] そのもの)。
int _digitRunEnd(String text, int start) {
  var i = start;
  while (i < text.length && i - start < 9 && _isDigit(text.codeUnitAt(i))) {
    i++;
  }
  return i;
}

/// [line] の先頭の ASCII 空白 (半角スペース・タブ) だけを剥がしたもの
/// (`String.trimLeft` と違い、全角スペースなど他の Unicode 空白は字下げとして
/// 扱わない)。
String _trimAsciiLeadingWhitespace(String line) {
  var i = 0;
  while (i < line.length && (line.codeUnitAt(i) == _space || line.codeUnitAt(i) == _tab)) {
    i++;
  }
  return line.substring(i);
}

/// `#`〜`######` の見出し行。
bool _looksLikeHeadingLine(String line) {
  final trimmed = line.trimLeft();
  var i = 0;
  while (i < trimmed.length && i < 6 && trimmed.codeUnitAt(i) == _hash) {
    i++;
  }
  if (i == 0) return false;
  return i >= trimmed.length ||
      trimmed.codeUnitAt(i) == _space ||
      trimmed.codeUnitAt(i) == _tab;
}

bool _startsWithBlockquoteMarker(String line) => line.trimLeft().startsWith('>');

// ── 最後のブロックの記号閉じ・リンク確定 ──

/// 記号閉じ・リンク確定の対象になる、最後の (受信中の) ブロック。
class _ClosingTarget {
  _ClosingTarget(this.lines, this.tag);

  /// 対象ブロック自身の行 (`ul`/`ol`/`blockquote` ならその末尾の子まで
  /// 絞り込んだもの)。
  final List<String> lines;

  /// 対象ブロックのタグ (`table`/`pre` なら記号閉じ・リンク確定をしない)。
  final String tag;
}

/// [runLines] の中から、記号閉じ・リンク確定の対象になる最後のブロックを、
/// 素の parse の結果と照合しながら特定する (行の見た目だけで判定しない)。
///
/// 最後のトップレベル要素が `ul`/`ol`/`blockquote` なら、その末尾の子
/// (最後の `li` や最後の子ブロック) まで再帰的に絞り込む — 同じ最後の
/// トップレベル要素の中でも、すでに確定した前の項目まで書き換えないため。
/// 絞り込みに失敗したら (対応する行の範囲が特定できなければ) null を返し、
/// 呼び出し側はそのブロックへの記号閉じ・リンク確定を諦める (絞り込めない
/// まま全体を対象にするのは、範囲を誤って確定済みの内容を書き換える方が
/// 危険なため)。
///
/// 最後の要素が `table`/`pre` なら、記号閉じ・リンク確定の対象外
/// ([_closeLastBlock] 側で tag だけ見て弾く) なので、絞り込みに入る前に
/// `nodes.last.tag` だけで打ち切る (このケースは受信中の全プレフィックスで
/// 頻繁に起こり得るので、無駄な絞り込みをしない)。
///
/// それ以外は、行単位のヒューリスティック ([_minimalTrailingLinesForNode] /
/// [_minimalTrailingLinesForChild]) で候補の開始行を 1 つ推定し、その候補
/// だけを実際に parse して確かめる (Q1: 末尾からの全探索 + 再 parse は
/// O(行数²) になるためやめる)。推定が外れた稀なケースに備え、そのときだけ
/// 末尾 8 行 ([_bruteForceFallbackLimit]) までの総当たりにフォールバックする
/// (見つからなければそのフレームは閉じない)。
_ClosingTarget? _findClosingTarget(List<String> runLines) {
  if (runLines.isEmpty) return null;
  final nodes = _parse(runLines.join('\n'));
  if (nodes.isEmpty) return null;

  Node node = nodes.last;
  if (node is Element && (node.tag == 'table' || node.tag == 'pre')) {
    return null; // 記号閉じ・リンク確定の対象外。
  }

  final initialLines = _minimalTrailingLinesForNode(runLines, node);
  if (initialLines == null) return null;
  var lines = initialLines;

  while (node is Element && (node.tag == 'ul' || node.tag == 'ol' || node.tag == 'blockquote')) {
    final children = node.children;
    if (children == null || children.isEmpty) break;
    final lastChild = children.last;
    final narrowed = _minimalTrailingLinesForChild(lines, node.tag, lastChild);
    if (narrowed == null) break;
    lines = narrowed;
    node = lastChild;
  }

  // 引用・リストの中の最後の子ブロックが table/pre なら、ここでも
  // 記号閉じ・リンク確定の対象外になる ([_closeLastBlock] 側で tag を見て弾く)。
  final tag = node is Element ? node.tag : 'text';
  return _ClosingTarget(lines, tag);
}

/// [lines] の末尾から、単独で parse した結果が [matches] を満たす最小の
/// 連続部分行を探す。
///
/// [guess] (呼び出し元があらかじめ推定した候補の開始行) を先に 1 回だけ
/// 試し、合えばそれで済ませる。外れた (または推定できなかった) 稀なケースに
/// 備え、そのときだけ末尾 [_bruteForceFallbackLimit] 行までの総当たりに
/// フォールバックする ([Q1]/[Q2]: 推定が外れた稀なケースでも、この総当たり
/// 自体が行数の 2 乗になってしまうと元の木阿弥のため、上限を設ける)。
/// 見つからなければ null を返し、呼び出し元はそのフレームでの記号閉じ・
/// リンク確定を見送る — 閉じないぶん生の記号が 1 フレーム見える可能性は
/// あるが、2 乗の遅延より安全側。
List<String>? _minimalTrailingLines(
  List<String> lines,
  int? guess,
  bool Function(List<String> candidateLines) matches,
) {
  if (guess != null && matches(lines.sublist(guess))) {
    return lines.sublist(guess);
  }

  final fallbackFloor = lines.length > _bruteForceFallbackLimit
      ? lines.length - _bruteForceFallbackLimit
      : 0;
  for (var start = lines.length - 1; start >= fallbackFloor; start--) {
    if (start == guess) continue; // 推定ですでに試した。
    final candidateLines = lines.sublist(start);
    if (matches(candidateLines)) return candidateLines;
  }
  return null;
}

/// 推定が外れたときの保険の総当たりで試す、末尾からの候補開始行の上限。
const _bruteForceFallbackLimit = 8;

/// [lines] の末尾から、単独で parse した結果が [target] と同じ HTML になる
/// 最小の連続部分行を探す ([_minimalTrailingLines] に委ねる。開始行の推定は
/// [_guessTopLevelStart])。
List<String>? _minimalTrailingLinesForNode(List<String> lines, Node target) {
  final targetHtml = HtmlRenderer().render([target]);
  bool matches(List<String> candidateLines) {
    final candidateNodes = _parse(candidateLines.join('\n'));
    return candidateNodes.length == 1 && HtmlRenderer().render(candidateNodes) == targetHtml;
  }

  return _minimalTrailingLines(lines, _guessTopLevelStart(lines, target), matches);
}

/// [lines] の末尾から、単独で parse した結果がタグ [containerTag] の要素
/// 1 つになり、かつその末尾の子が [targetChild] と同じ HTML になる最小の
/// 連続部分行を探す ([_minimalTrailingLines] に委ねる。開始行の推定は
/// [_guessChildStart])。子だけを比べるのは、`ol` の `start` 属性のように
/// コンテナ自身の属性が候補ごとに変わり得る (項目数が減るぶん `start` が
/// 変わる) ため。
List<String>? _minimalTrailingLinesForChild(
  List<String> lines,
  String containerTag,
  Node targetChild,
) {
  final targetHtml = HtmlRenderer().render([targetChild]);
  bool matches(List<String> candidateLines) {
    final candidateNodes = _parse(candidateLines.join('\n'));
    if (candidateNodes.length != 1) return false;
    final top = candidateNodes.single;
    if (top is! Element || top.tag != containerTag) return false;
    final children = top.children;
    if (children == null || children.isEmpty) return false;
    return HtmlRenderer().render([children.last]) == targetHtml;
  }

  return _minimalTrailingLines(lines, _guessChildStart(lines, containerTag), matches);
}

// ── 最後のブロックの開始行のヒューリスティック (Q1: 末尾 8 行までの総当たりの
// 代わりに、行の形だけで候補を 1 つ推定する。正しさの確認は呼び出し元の 1 回の
// parse に委ねる) ──

/// [target] (最後のトップレベル要素) の種類に応じて、[lines] の中でその要素が
/// 始まる行を推定する (無ければ null。呼び出し元は末尾 8 行
/// ([_bruteForceFallbackLimit]) までの総当たりにフォールバックし、見つから
/// なければそのフレームは閉じない)。
int? _guessTopLevelStart(List<String> lines, Node target) {
  if (lines.isEmpty) return null;
  if (target is Element) {
    switch (target.tag) {
      case 'ul':
      case 'ol':
        return _lastListContainerStartHeuristic(lines);
      case 'blockquote':
        return _lastBlockquoteStartHeuristic(lines);
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        return _lastNonBlankIndex(lines); // ATX 見出しは常に 1 行 (末尾の空行は除く)。
    }
  }
  return _lastParagraphStartHeuristic(lines);
}

/// [containerTag] (`ul`/`ol`/`blockquote`) の最後の子が、すでにコンテナ自身の
/// 行に絞り込み済みの [lines] の中で始まる行を推定する。
int? _guessChildStart(List<String> lines, String containerTag) {
  if (lines.isEmpty) return null;
  switch (containerTag) {
    case 'ul':
    case 'ol':
      return _lastListItemStartHeuristic(lines);
    case 'blockquote':
      return _lastBlockquoteChildStartHeuristic(lines);
  }
  return null;
}

/// 段落 (またはタグを持たない要素) の開始行: 直前の空行、またはブロック記号
/// (見出し・リスト・引用・フェンス) の行の次。
///
/// 末尾に空行が複数続いていても (ブロックの区切りの `\n\n` が 1 文字ずつ
/// 届く途中でこの形になる)、まず [_lastNonBlankIndex] で最後の非空行まで
/// 進めてから境界を探す — でないと「直前の行」がすぐ空行に当たって
/// 1 行も遡らずに打ち切ってしまう。
int _lastParagraphStartHeuristic(List<String> lines) {
  var start = _lastNonBlankIndex(lines);
  while (start > 0 && !_looksLikeBlockBoundary(lines[start - 1])) {
    start--;
  }
  return start;
}

/// [line] が段落を打ち切る境界 (空行・ブロック記号の行) かどうか。
bool _looksLikeBlockBoundary(String line) =>
    line.trim().isEmpty || _startsWithBlockMarker(line);

/// [lines] の末尾から見て最後の非空行の index (全部空行なら 0)。
int _lastNonBlankIndex(List<String> lines) {
  var i = lines.length - 1;
  while (i > 0 && lines[i].trim().isEmpty) {
    i--;
  }
  return i;
}

/// リストの開始行 (コンテナ全体を、前に続く別のブロックから切り離す): 空行・
/// 字下げされた継続行・**同じ種類の**このリストの記号行のどれかが続く間は
/// さかのぼる。さかのぼった先が空行なら、そのぶん (リストの前の空行) は
/// 含めない (最小の範囲に揃える)。
///
/// [strip] は各行を比較の前に変換する (引用の中のリスト向け: `>` を剥がして
/// から字下げ・記号を見る。既定は素通し)。
///
/// 記号の種類 ([_listMarkerKind]。箇条書きの文字・番号リストの区切り文字) が
/// 末尾の行と違う記号行に当たったら、空行をまたいでいてもさかのぼりを止める
/// ([Q2]: `- a\n- b\n\n1. c\n1. d` のように種類が変わる箇所はパーサーも
/// 別々の `ul`/`ol` にするため、そこを跨いで 1 つのリストと推定すると
/// `nodes.length` が 2 になり推定が外れて保険の総当たりに落ちる)。
int _lastListContainerStartHeuristic(
  List<String> lines, {
  String Function(String) strip = _identityLine,
}) {
  var start = lines.length - 1;
  int? refKind = _listMarkerKind(strip(lines[start]));
  while (start > 0) {
    final prev = strip(lines[start - 1]);
    if (!_looksLikeListContinuation(prev, refKind)) break;
    final kind = _listMarkerKind(prev);
    if (kind != null) refKind = kind;
    start--;
  }
  while (start < lines.length - 1 && strip(lines[start]).trim().isEmpty) {
    start++;
  }
  return start;
}

String _identityLine(String line) => line;

/// [line] (すでに [_lastListContainerStartHeuristic] の [strip] を適用済み) が
/// 種類 [refKind] のリストの続きとして数えられるか: 空行・字下げされた継続行は
/// 種類を問わず続きとみなす。リスト記号の行は、記号の種類が [refKind] と
/// 一致するとき (または [refKind] がまだ null、すなわちどの種類にもまだ
/// 出会っていないとき) だけ続きとみなす。
bool _looksLikeListContinuation(String line, int? refKind) {
  if (line.trim().isEmpty) return true;
  if (_indentOf(line) > 0) return true;
  final kind = _listMarkerKind(line);
  return kind != null && (refKind == null || kind == refKind);
}

/// [line] のリスト記号の種類 (箇条書きなら記号の文字コード、番号リストなら
/// 区切り文字 (`.` か `)`) の文字コード)。記号行でなければ null。
/// [_lastListContainerStartHeuristic] が空行をまたいで同じリストの続きかどうか
/// を、記号の種類が変わっていないかで判定するのに使う (種類が変われば
/// CommonMark でも別のリストになるため、空行があってもまたがない)。
int? _listMarkerKind(String line) {
  final trimmed = line.trimLeft();
  if (trimmed.isEmpty) return null;
  final first = trimmed.codeUnitAt(0);
  if (first == _asterisk || first == _hyphen || first == _plus) {
    if (trimmed.length > 1 &&
        (trimmed.codeUnitAt(1) == _space || trimmed.codeUnitAt(1) == _tab)) {
      return first;
    }
    return null;
  }
  final i = _digitRunEnd(trimmed, 0);
  if (i == 0 || i >= trimmed.length) return null;
  final marker = trimmed.codeUnitAt(i);
  if (marker != _period && marker != _rightParen) return null;
  if (i + 1 >= trimmed.length ||
      (trimmed.codeUnitAt(i + 1) != _space && trimmed.codeUnitAt(i + 1) != _tab)) {
    return null;
  }
  return marker;
}

/// リストの最後の項目 (`li`) の開始行: [lines] (リスト自身の行) の中で、
/// 先頭の行と同じ字下げの記号行のうち最後のもの。
int? _lastListItemStartHeuristic(List<String> lines) {
  final baseIndent = _indentOf(lines.first);
  for (var i = lines.length - 1; i >= 0; i--) {
    if (_indentOf(lines[i]) == baseIndent && _looksLikeListMarker(lines[i])) {
      return i;
    }
  }
  return null;
}

/// 引用の開始行 (コンテナ全体): 連続する `>` 行の先頭までさかのぼる。末尾の
/// 複数の空行は [_lastNonBlankIndex] でまず飛ばす (理由は
/// [_lastParagraphStartHeuristic] と同じ)。
int _lastBlockquoteStartHeuristic(List<String> lines) {
  var start = _lastNonBlankIndex(lines);
  while (start > 0 && _startsWithBlockquoteMarker(lines[start - 1])) {
    start--;
  }
  return start;
}

/// 引用の最後の子ブロックの開始行: `>` を剥いだ中身に対して、段落と同じ
/// 境界判定 (空行・ブロック記号の行) を適用する。末尾の複数の空行の扱いも
/// [_lastParagraphStartHeuristic] と同じ。
///
/// 末尾の (空行を除いた) 行が `>` を剥がした形でリスト記号なら、最後の子は
/// リスト (`ul`/`ol`) なので、段落と同じ境界判定ではなく
/// [_lastListContainerStartHeuristic] (`>` を剥がしてから比較する) に委ねる
/// ([Q1]: 段落用の境界判定はリスト記号の行自体を「境界」と見なすため、
/// 剥がした残りがリスト記号の行にいきなり当たって 1 行もさかのぼれず、
/// 引用の中の長いリスト全体を保険の総当たりに落としていた)。
int _lastBlockquoteChildStartHeuristic(List<String> lines) {
  final anchor = _lastNonBlankIndex(lines);
  final strippedAnchor = _stripBlockquotePrefix(lines[anchor]);
  // 剥がした中身がリスト記号、または (中身の無い引用の続き `>` のように)
  // 空なら、リストの続きの可能性があるので [_lastListContainerStartHeuristic]
  // に委ねる。実際にはリストでなかった (例えば段落の後の空の引用の続き)
  // 場合でも、その候補は [_minimalTrailingLinesForChild] の照合で単に
  // 不一致になり、上限付きの総当たりに安全にフォールバックするだけなので
  // 過剰に委ねても害はない。
  if (_listMarkerKind(strippedAnchor) != null || strippedAnchor.trim().isEmpty) {
    return _lastListContainerStartHeuristic(lines, strip: _stripBlockquotePrefix);
  }
  var start = anchor;
  while (start > 0 && !_looksLikeBlockBoundary(_stripBlockquotePrefix(lines[start - 1]))) {
    start--;
  }
  return start;
}

/// [line] の先頭の `>` (と、その直後の空白 1 個) を剥いだ中身。`>` で
/// 始まらなければそのまま返す。
String _stripBlockquotePrefix(String line) {
  if (!_startsWithBlockquoteMarker(line)) return line;
  final trimmedLeft = line.trimLeft();
  final afterMarker = trimmedLeft.substring(1);
  return afterMarker.startsWith(' ') ? afterMarker.substring(1) : afterMarker;
}

/// [line] の先頭の字下げ (半角スペース・タブ) の文字数。
int _indentOf(String line) => line.length - line.trimLeft().length;

/// 最後の非フェンス run の行に対して、末尾の行レベルの保留を済ませたうえで、
/// 記号閉じ・書きかけリンクの確定を行う。
String _closeLastBlock(List<String> runLines) {
  final text = runLines.join('\n');

  final target = _findClosingTarget(runLines);
  if (target == null || target.tag == 'table' || target.tag == 'pre') {
    return text;
  }

  final precedingCount = runLines.length - target.lines.length;
  final preceding = runLines.sublist(0, precedingCount);
  var blockText = target.lines.join('\n');
  blockText = _closePartialLinks(blockText);
  blockText = _closeTrailingDelimiters(blockText);

  return preceding.isEmpty ? blockText : '${preceding.join('\n')}\n$blockText';
}

// ── 書きかけのリンク ──

/// 書きかけのリンク `[ラベル` / `[ラベル](url` をラベルだけの素の文字にする。
///
/// 画像記法 `![alt](url` の `[` (直前が `!`) は対象外 — 常に手つかずのまま
/// 残す。この前処理より前の描画忠実性の段 ([_applyRenderingFidelity]) が
/// `![` を `\!\[` にエスケープ済みなので通常この分岐には来ないが、
/// エスケープが届かない経路のための保険として残す。閉じたリンク
/// `[ラベル](url)` は触らずそのまま残す (パーサーがリンクにする)。
/// インラインコードスパンの内側はコードスパンの区切りごと素通りさせ、
/// `[` `]` `(` `)` をリンクの記号として解釈しない。
String _closePartialLinks(String text) {
  final buffer = StringBuffer();
  var i = 0;
  while (i < text.length) {
    if (text.codeUnitAt(i) == _backquote) {
      final openEnd = _runEnd(text, i, _backquote);
      final closeEnd = _codeSpanCloseEnd(text, i, openEnd - i);
      if (closeEnd == null) {
        // 閉じていないコードスパン: 残りは全部その内側なので素のまま書いて終わる。
        buffer.write(text.substring(i));
        return buffer.toString();
      }
      buffer.write(text.substring(i, closeEnd));
      i = closeEnd;
      continue;
    }

    final ch = text[i];
    if (ch == r'\' && i + 1 < text.length) {
      buffer
        ..write(ch)
        ..write(text[i + 1]);
      i += 2;
      continue;
    }
    if (ch != '[' || (i > 0 && text[i - 1] == '!')) {
      buffer.write(ch);
      i++;
      continue;
    }

    final labelStart = i + 1;
    final labelEnd = _findUnescaped(text, ']', labelStart);
    if (labelEnd == -1) {
      // ラベルの途中で切れている: [ を落としてラベルだけ残す。
      buffer.write(text.substring(labelStart));
      return buffer.toString();
    }

    final label = text.substring(labelStart, labelEnd);
    final afterLabel = labelEnd + 1;
    if (afterLabel < text.length && text[afterLabel] == '(') {
      final urlStart = afterLabel + 1;
      final urlEnd = _findLinkDestinationEnd(text, urlStart);
      if (urlEnd == null) {
        final newlineInUrl = text.indexOf('\n', urlStart);
        if (newlineInUrl != -1) {
          // URL が改行より前で切れている: URL 部分だけ落とし、改行以後は
          // 捨てずに通常どおり走査を続ける (次の行に届いた文字を消さない)。
          buffer.write(label);
          i = newlineInUrl;
          continue;
        }
        // 改行も無いまま文字列が終わっている: ラベルだけ残す。
        buffer.write(label);
        return buffer.toString();
      }
      // 閉じたリンク: 触らずそのまま書く。
      buffer.write(text.substring(i, urlEnd + 1));
      i = urlEnd + 1;
      continue;
    }

    if (afterLabel == text.length) {
      // 閉じ角括弧まで届いて ( がまだの段階で文字列が終わっている:
      // ラベルだけの素の文字にする (生の [ ] を一瞬も見せない)。
      buffer.write(label);
      return buffer.toString();
    }

    // `[ラベル]` の形 (URL 無し、後ろに ( 以外の文字が続く) はこのスライスの
    // 対象外なので触らない。
    buffer.write(text.substring(i, labelEnd + 1));
    i = labelEnd + 1;
  }
  return buffer.toString();
}

/// [start] から、エスケープを飛ばしつつ [target] の出現位置を探す。無ければ -1。
int _findUnescaped(String text, String target, int start) {
  var i = start;
  while (i < text.length) {
    final ch = text[i];
    if (ch == r'\' && i + 1 < text.length) {
      i += 2;
      continue;
    }
    if (ch == target) return i;
    i++;
  }
  return -1;
}

/// [start] (URL の先頭) から、リンク先の終わりの `)` を探す。URL の中の
/// 対になった `(` `)` (`Foo_(bar)` など) は閉じ括弧として数えない (`(` と
/// `)` の対応を数える)。探索は同じ行の中に限る (改行をまたいだら見つからない
/// ものとして扱う)。見つからなければ null。
int? _findLinkDestinationEnd(String text, int start) {
  var depth = 0;
  var i = start;
  while (i < text.length) {
    final ch = text[i];
    if (ch == '\n') return null;
    if (ch == r'\' && i + 1 < text.length) {
      i += 2;
      continue;
    }
    if (ch == '(') {
      depth++;
      i++;
      continue;
    }
    if (ch == ')') {
      if (depth == 0) return i;
      depth--;
      i++;
      continue;
    }
    i++;
  }
  return null;
}

/// [text] の [openStart] (`` ` `` の並びの先頭) から始まる長さ [openLength] の
/// コードスパンが閉じる位置 (閉じる並びの直後の index) を返す。閉じていなければ
/// null (バックスラッシュはコードスパンの区切りには意味を持たない)。
int? _codeSpanCloseEnd(String text, int openStart, int openLength) {
  var i = openStart + openLength;
  while (i < text.length) {
    if (text.codeUnitAt(i) == _backquote) {
      final end = _runEnd(text, i, _backquote);
      if (end - i == openLength) return end;
      i = end;
    } else {
      i++;
    }
  }
  return null;
}

// ── 最後のブロックの記号閉じ ──

/// [blockText] (最後のブロック自身の生の文字列) の末尾に残った、閉じていない
/// `**` `*` `__` `_` `` ` `` を閉じる。
///
/// 候補の発見は [_scanDelimiterTokens] (CommonMark の flanking 規則どおりの
/// can-open/can-close 判定) に委ねるが、**採用するかどうかはパーサーに確かめ
/// させる**: 内側の候補から順に閉じ記号を 1 つだけ足して再 parse し、
/// `strong`/`em`/`code` の数が実際に増えたことを確認できたものだけを残す。
/// 増えなければそこで打ち切る (それより外側の候補も、内側が閉じない限り
/// 意味を持たない)。中身がまだ空白しか届いていない末尾の開き記号は、
/// 確かめるまでもなく落とす (落として空いた外側も中身が無ければ続けて落とす)。
String _closeTrailingDelimiters(String blockText) {
  final tokens = _scanDelimiterTokens(blockText);
  final stack = <_DelimiterToken>[];
  for (final token in tokens) {
    if (token.canClose) {
      final top = stack.isNotEmpty ? stack.last : null;
      if (top != null && top.char == token.char && top.length == token.length) {
        stack.removeLast();
        continue;
      }
    }
    if (token.canOpen) {
      stack.add(token);
    }
    // canClose だが対応する開き記号が無い run はそのまま (素通し)。
  }
  if (stack.isEmpty) return blockText;

  var result = blockText;
  while (stack.isNotEmpty && _isAllLineWhitespace(result, stack.last.end)) {
    final candidate = stack.removeLast();
    result = result.substring(0, candidate.start) + result.substring(candidate.end);
  }
  if (stack.isEmpty) return result;

  var acceptedCount = _emphasisLikeElementCount(_parse(result));
  while (stack.isNotEmpty) {
    final opener = stack.last;
    final insertAt = _closerInsertionPoint(result);
    final candidate =
        result.substring(0, insertAt) + opener.marker + result.substring(insertAt);
    final candidateNodes = _parse(candidate);
    final candidateCount = _emphasisLikeElementCount(candidateNodes);
    // 個数が増えただけでは採用しない: 足した閉じ記号の一部だけが要素に消費され
    // 残りが生の記号として尾を引く形 (`***` の 3 個中 1 個だけが `em` の閉じに
    // 使われ、残り 2 個が浮く、など。この前処理の run 長一致マッチングでは
    // CommonMark の run 分割を再現できないため実際にレンダーして確かめる) や、
    // 足した記号が別の (無関係な) 開き記号と組んで個数を押し上げただけの形は
    // 弾く。足した記号のすぐ後ろに、その記号自身が生のまま残っていないか
    // (AST のテキストの末尾が閉じ記号の文字で終わっていないか) で確かめる
    // ([Q4])。AST の [Node.textContent] を使う (HTML にレンダーしてタグを
    // 正規表現で剥がす方式だと、`encodeHtml: false` のため本文の生の `<` が
    // タグとして誤って剥がされてしまう)。
    final leftoverRawMarker = candidateNodes
        .map((node) => node.textContent)
        .join()
        .trimRight()
        .endsWith(String.fromCharCode(opener.char));
    if (candidateCount <= acceptedCount || leftoverRawMarker) {
      break; // 消費されなかった: これ以上は閉じない。
    }
    result = candidate;
    acceptedCount = candidateCount;
    stack.removeLast();
  }
  return result;
}

/// [nodes] の中に現れる `strong`/`em`/`code` 要素の総数 (再帰的に数える)。
int _emphasisLikeElementCount(List<Node> nodes) {
  var count = 0;
  void visit(Node node) {
    if (node is Element) {
      if (node.tag == 'strong' || node.tag == 'em' || node.tag == 'code') count++;
      for (final child in node.children ?? const <Node>[]) {
        visit(child);
      }
    }
  }
  for (final node in nodes) {
    visit(node);
  }
  return count;
}

/// [text] の [start] 以降が空白 (半角スペース・タブ・改行) だけ、または
/// 何も届いていないか。
bool _isAllLineWhitespace(String text, int start) {
  for (var i = start; i < text.length; i++) {
    if (!_isUnicodeWhitespace(text.codeUnitAt(i))) return false;
  }
  return true;
}

/// 末尾の空白 (半角スペース・タブ・改行)、および中身の無い引用の続き
/// (`\n>` `\n> `) の直前の位置。
///
/// 中身の無い引用の続きも飛び越すのは、そこに閉じ記号を置くと `>` の
/// 後ろに置かれてしまい (`> 引用 **太字\n>` の末尾など)、閉じ記号が
/// right-flanking にならず生の記号のまま見えてしまうため — 閉じ記号は
/// 実際に中身がある最後の文字のすぐ後ろに置く。
int _closerInsertionPoint(String text) {
  var i = text.length;
  while (i > 0) {
    final unit = text.codeUnitAt(i - 1);
    if (_isUnicodeWhitespace(unit)) {
      i--;
      continue;
    }
    if (unit == _greaterThan && _isEmptyBlockquoteContinuationMarker(text, i - 1)) {
      i--;
      continue;
    }
    break;
  }
  return i;
}

/// [index] (`>` の位置) が「中身の無い引用の続き」の `>` かどうか: 直前が
/// 改行 (または文字列の先頭) で、[index] の直後が空白・改行・文字列の終わりの
/// どれか (`>` の後ろに引用の中身が届いていない)。
bool _isEmptyBlockquoteContinuationMarker(String text, int index) {
  if (index > 0 && text.codeUnitAt(index - 1) != _newline) return false;
  final after = index + 1;
  if (after >= text.length) return true;
  final unit = text.codeUnitAt(after);
  return unit == _space || unit == _tab || unit == _newline;
}

/// [_closeTrailingDelimiters] が対象にする 1 つの開き・閉じ記号の並び。
///
/// [canOpen] な run だけがスタックに積まれ、[canClose] な run は対応する
/// 開き記号を pop する (CommonMark の can-open / can-close の判定)。
class _DelimiterToken {
  _DelimiterToken(
    this.char,
    this.start,
    this.end, {
    required this.canOpen,
    required this.canClose,
  });

  final int char;
  final int start;
  final int end;
  final bool canOpen;
  final bool canClose;

  int get length => end - start;

  /// この記号の並びそのもの (`**` `*` `__` `_` `` ` ``)。
  String get marker => String.fromCharCode(char) * length;

  /// [offset] だけ位置をずらした同じ内容の token (リンクのラベルを親の
  /// 座標系へ書き戻すのに使う)。
  _DelimiterToken shift(int offset) =>
      _DelimiterToken(char, start + offset, end + offset, canOpen: canOpen, canClose: canClose);
}

/// 開き・閉じ記号として数える `**` `*` `__` `_` `` ` `` の並びを、出現順に拾う。
///
/// コードスパンの内側 (同じ長さのバッククォートの並びで閉じるまで)・
/// 閉じた (完成した) リンクの `](…)` の中と、行頭の箇条書き記号
/// (`* ` `- ` `+ `)・語中の `_` (前後がどちらも英数字) は対象から外す。
/// `*`/`_` は CommonMark の flanking 規則どおり can-open / can-close を
/// 判定する:
/// - `*`: can-open = left-flanking、can-close = right-flanking
/// - `_`: can-open = left-flanking かつ (not right-flanking or 前が句読点)、
///   can-close = right-flanking かつ (not left-flanking or 後が句読点)
///
/// 前の文字も次の文字もどちらも句読点の並び (`(*)` のような形。
/// [_isFlankedByPunctuationOnBothSides] 参照) は、can-open の判定からだけ
/// 除外する (can-close には適用しない)。次の文字がまだ届いていない (末尾の)
/// 並びは left-flanking の判定を保留し can-open とみなす。[initialAtLineStart]
/// は [text] の先頭が実際に行頭かどうか (閉じたリンクのラベルを再帰的に
/// 走査するときは false になる)。
///
/// ここで見つけた候補が本当に閉じられるかどうかは、[_closeTrailingDelimiters]
/// が実際に parse して確かめる — この関数は候補を挙げるだけで、採否は決めない。
List<_DelimiterToken> _scanDelimiterTokens(String text, {bool initialAtLineStart = true}) {
  final tokens = <_DelimiterToken>[];
  var i = 0;
  var atLineStart = initialAtLineStart;
  while (i < text.length) {
    final ch = text.codeUnitAt(i);
    if (ch == _backquote) {
      final openEnd = _runEnd(text, i, _backquote);
      final openLength = openEnd - i;
      tokens.add(_DelimiterToken(_backquote, i, openEnd, canOpen: true, canClose: false));
      final closeEnd = _codeSpanCloseEnd(text, i, openLength);
      if (closeEnd == null) {
        // 閉じていない: 以降は全部コードスパンの内側なので走査を打ち切る。
        break;
      }
      tokens.add(
        _DelimiterToken(_backquote, closeEnd - openLength, closeEnd, canOpen: false, canClose: true),
      );
      i = closeEnd;
      atLineStart = false;
      continue;
    }
    if (ch == _leftBracket) {
      final linkLabel = _closedLinkLabelRange(text, i);
      if (linkLabel != null) {
        final (labelStart, labelEnd, afterUrl) = linkLabel;
        tokens.addAll(
          _scanDelimiterTokens(text.substring(labelStart, labelEnd), initialAtLineStart: false)
              .map((t) => t.shift(labelStart)),
        );
        i = afterUrl;
        atLineStart = false;
        continue;
      }
    }
    if (ch == _rightBracket &&
        i + 1 < text.length &&
        text.codeUnitAt(i + 1) == _leftParen &&
        _findLinkDestinationEnd(text, i + 2) == null) {
      // 閉じていない `](` (画像のエスケープ後に残る URL など): これ以降は
      // リンク先の途中なので、強調記号の候補として走査しない (URL の中の
      // `_` などを拾わないため)。
      break;
    }
    if (ch == _backslash) {
      i += (i + 1 < text.length) ? 2 : 1;
      atLineStart = false;
      continue;
    }
    if (ch == _newline) {
      i++;
      atLineStart = true;
      continue;
    }
    if (ch == _space || ch == _tab) {
      i++;
      continue;
    }
    if (atLineStart && (ch == _asterisk || ch == _hyphen || ch == _plus)) {
      final markerEnd = i + 1;
      if (markerEnd < text.length &&
          (text.codeUnitAt(markerEnd) == _space ||
              text.codeUnitAt(markerEnd) == _tab)) {
        // 箇条書き記号 (`* ` `- ` `+ `): 開き記号として数えない。
        i = markerEnd;
        atLineStart = false;
        continue;
      }
    }
    atLineStart = false;
    if (ch == _asterisk || ch == _underscore) {
      final end = _runEnd(text, i, ch);
      if (ch == _underscore) {
        final before = i > 0 ? text.codeUnitAt(i - 1) : null;
        final after = end < text.length ? text.codeUnitAt(end) : null;
        if (_isAlnum(before) && _isAlnum(after)) {
          // 語中の `_` (例: my_var の 1 つ目): 開き記号にも閉じ記号にもしない。
          i = end;
          continue;
        }
      }
      final leftFlanking = _isLeftFlanking(text, i, end);
      final rightFlanking = _isRightFlanking(text, i, end);
      final bool canOpen;
      final bool canClose;
      if (ch == _asterisk) {
        canOpen = leftFlanking && !_isFlankedByPunctuationOnBothSides(text, i, end);
        canClose = rightFlanking;
      } else {
        final precededByPunctuation = i > 0 && _isUnicodePunctuation(text.codeUnitAt(i - 1));
        final followedByPunctuation = end < text.length && _isUnicodePunctuation(text.codeUnitAt(end));
        // 文字列の末尾にある run (後ろに文字が一切届いていない) は、
        // right-flanking による「語中の `_`」の除外規則を適用せず、中身の
        // 無い開き記号として扱う (対応する開き記号が無ければ
        // [_closeTrailingDelimiters] が落とす)。そうしないと、例えば
        // `と __太字_` の末尾の `_` が can-open にも can-close にもならず
        // トークンにならないまま素通りし、パーサーが 1 つだけ消費して
        // `_<em>太字</em>` のような形になってしまう。
        final atTextEnd = _isAllLineWhitespace(text, end);
        canOpen = atTextEnd ||
            (leftFlanking &&
                (!rightFlanking || precededByPunctuation) &&
                !_isFlankedByPunctuationOnBothSides(text, i, end));
        canClose = rightFlanking && (!leftFlanking || followedByPunctuation);
      }
      if (canOpen || canClose) {
        tokens.add(_DelimiterToken(ch, i, end, canOpen: canOpen, canClose: canClose));
      }
      i = end;
      continue;
    }
    i++;
  }
  return tokens;
}

/// [start] (`[`) から始まる閉じた (完成した) リンク `[label](url)` を検出する。
/// 見つかれば (ラベル開始, ラベル終了, 閉じ括弧の直後) を返し、見つからなければ
/// null。画像記法 (`!` の直後の `[`) かどうかは問わない — 描画時にリンクとして
/// 扱うかどうかは別の話で、走査から外す対象としては通常のリンクと同じに扱う。
(int, int, int)? _closedLinkLabelRange(String text, int start) {
  final labelStart = start + 1;
  final labelEnd = _findUnescaped(text, ']', labelStart);
  if (labelEnd == -1) return null;
  final afterLabel = labelEnd + 1;
  if (afterLabel >= text.length || text[afterLabel] != '(') return null;
  final urlStart = afterLabel + 1;
  final urlEnd = _findLinkDestinationEnd(text, urlStart);
  if (urlEnd == null) return null;
  return (labelStart, labelEnd, urlEnd + 1);
}

/// [start, end) の記号の並びが CommonMark の left-flanking (開き記号になれる)
/// かどうかの簡略版。次の文字がまだ届いていない (末尾)、または空白しか
/// 届いていないときは、書きかけの記法をいったん開き記号として扱う既存の
/// 挙動 (中身が空白しか届いていない末尾の開き記号は閉じずに落とす) を保つ
/// ため、flanking とみなす。
bool _isLeftFlanking(String text, int start, int end) {
  if (_isAllLineWhitespace(text, end)) return true;
  final next = text.codeUnitAt(end);
  if (_isUnicodeWhitespace(next)) return false;
  if (!_isUnicodePunctuation(next)) return true;
  final prev = start > 0 ? text.codeUnitAt(start - 1) : null;
  return prev == null || _isUnicodeWhitespace(prev) || _isUnicodePunctuation(prev);
}

/// [start, end) の記号の並びが CommonMark の right-flanking (閉じ記号になれる)
/// かどうかの簡略版。ブロックの先頭 (前の文字が無い) は行頭の空白と同じ扱いで
/// flanking なしとする。
bool _isRightFlanking(String text, int start, int end) {
  if (start <= 0) return false;
  final prev = text.codeUnitAt(start - 1);
  if (_isUnicodeWhitespace(prev)) return false;
  if (!_isUnicodePunctuation(prev)) return true;
  final next = end < text.length ? text.codeUnitAt(end) : null;
  return next == null || _isUnicodeWhitespace(next) || _isUnicodePunctuation(next);
}

/// [start, end) の記号の並びの前の文字も次の文字もどちらも句読点かどうか
/// (`(*)` `"*"` のような形。CommonMark の left-flanking / right-flanking の
/// 規則 2b はどちらもこの形を flanking と認めてしまうが、書きかけの強調では
/// なく素の記号として使われている形なので、開き記号の候補から外す。前後の
/// どちらかが無い (文字列の先頭・末尾) 場合は対象にしない)。
bool _isFlankedByPunctuationOnBothSides(String text, int start, int end) {
  if (start <= 0 || end >= text.length) return false;
  return _isUnicodePunctuation(text.codeUnitAt(start - 1)) &&
      _isUnicodePunctuation(text.codeUnitAt(end));
}

/// [codeUnit] が CommonMark の Unicode whitespace かどうか
/// ([DelimiterRun.unicodeWhitespace] をそのまま使う。ASCII の空白・改行に加え
/// 全角スペース U+3000 や U+00A0 も含む — 自前で ASCII だけに絞ると、全角
/// スペースの直後に閉じ記号を置いてしまいパーサーの right-flanking 判定と
/// 食い違う)。
bool _isUnicodeWhitespace(int codeUnit) =>
    DelimiterRun.unicodeWhitespace.contains(String.fromCharCode(codeUnit));

/// [codeUnit] が CommonMark の Unicode punctuation かどうか
/// ([DelimiterRun.unicodePunctuationPattern] をそのまま使う。`markdown-7.3.1`
/// の `lib/src/inline_syntaxes/delimiter_syntax.dart` で定義され、
/// `package:markdown/markdown.dart` から公開されている。ASCII punctuation
/// だけの自前判定だと `、。「」（）・！？：` などの日本語の句読点を見落とし、
/// パーサーの flanking 判定とずれる)。
bool _isUnicodePunctuation(int codeUnit) =>
    DelimiterRun.unicodePunctuationPattern.hasMatch(String.fromCharCode(codeUnit));

int _runEnd(String text, int start, int charCode) {
  var i = start;
  while (i < text.length && text.codeUnitAt(i) == charCode) {
    i++;
  }
  return i;
}

bool _isAlnum(int? codeUnit) {
  if (codeUnit == null) return false;
  if (_isDigit(codeUnit)) return true;
  if (codeUnit >= 0x41 && codeUnit <= 0x5A) return true; // A-Z
  if (codeUnit >= 0x61 && codeUnit <= 0x7A) return true; // a-z
  return false;
}
