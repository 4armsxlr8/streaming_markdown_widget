import 'package:markdown/markdown.dart';

/// Regular expression used to decide whether a line opens or closes a fence.
/// It reuses `package:markdown` 7.3.1's `FencedCodeBlockSyntax().pattern`
/// (`codeFencePattern`) as-is (a hand-written regular expression would allow
/// backticks in the info string, and would mistake a line such as
/// ```` ```a`b ```` for an opening fence). It has the named groups
/// `backtick`/`backtickInfo`/`tilde`/`tildeInfo`.
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

/// Builds a [Document] with only the syntaxes the plan explicitly registers.
/// A fresh one is built for every parse (so that link reference definition
/// state is not carried over). The same syntaxes are also used for the
/// re-parses inside the preprocessing (deciding on fences and tables,
/// verifying delimiter closing) — every such decision is delegated to "the
/// parser itself".
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

/// A string → parse result memo that is valid only within a single call to
/// [parseReplyMarkdown]. [parseReplyMarkdown] installs it at the start of the
/// call and restores the previous value at the end (so it never survives
/// across calls, and re-entering does not break the outer call). While it is
/// null, nothing is memoized and the text is simply parsed.
Map<String, List<Node>>? _parseMemo;

/// Parses [text] with [_rawDocument]. Within a single call the same string can
/// be parsed two or three times — for the holdback decision
/// ([_lastTopLevelTag]), for locating the block ([_findClosingTarget]'s root
/// parse), for the final parse, and so on — so when [_parseMemo] exists its
/// result is carried around through it (measured 31-45% shorter).
List<Node> _parse(String text) {
  final memo = _parseMemo;
  if (memo == null) return _rawDocument().parse(text);
  return memo.putIfAbsent(text, () => _rawDocument().parse(text));
}

/// Preprocessing that turns the Markdown up to the reveal position (including
/// not-yet-closed notation) into a closed form that can be handed to the parser.
///
/// It only drops characters that have arrived or adds closing delimiters; it
/// never rewrites their order or their content. `\r\n` and `\r` are first
/// normalized to `\n` (so that delimiter row detection and the like do not
/// break even when the supply uses CRLF). Two stages are applied in order:
///
/// 1. [_applyRenderingFidelity] (the rendering fidelity stage; always applied
///    regardless of the value of [complete]): escapes the image notation
///    `![alt](url)` to `\!\[alt](url)` so that the parser makes it neither an
///    image nor a link
///    (spec: "images are not formatted and appear as literal delimiter
///    characters").
/// 2. [_applyReceivingHoldbacks] (the receiving-only stage; not applied when
///    [complete] is true): the trailing line-level holdbacks, plus delimiter
///    closing and partial link closing for the last block.
///
/// When [complete] is true (receiving has finished), the result of stage 1 is
/// returned as-is — this is the whole text, so nothing is dropped and nothing
/// is closed for not-yet-closed notation (continuing to run stage 2 after
/// receiving has finished would open a path where characters that have
/// finished arriving disappear forever, or stay as raw delimiters).
///
/// The basic policy behind these decisions: **use the parser itself as the
/// decision procedure**. Only fence detection relies on a line-wise regular
/// expression ([_fenceLineFlags]); everything else — "does this hold together
/// as a table?", "can this be closed as an emphasis delimiter?" — is decided by
/// actually parsing the candidate string with [_rawDocument] and looking at the
/// result.
///
/// - The contents of an unclosed code fence are left untouched. However, if the
///   last line inside the fence consists of only 1 or 2 of the same fence
///   character (fewer than 3, so it does not yet reach a closing fence), it is
///   treated as a partial closing fence and that line is dropped
/// - A trailing line that could become a table (a partial delimiter row, a
///   candidate header row, a body row of an already settled table, a `|` in
///   prose that is still growing) is held back while the parser is asked
///   whether it "holds together as a table". A trailing line that could become
///   a block marker (only digits, or a single `-`/`+`) is likewise held back
///   until the next character settles whether it becomes a bullet list
/// - Unclosed `**` `*` `__` `_` `` ` `` left at the end of the last (receiving)
///   block are found as candidates; a closing delimiter is actually added, the
///   text is re-parsed, and a candidate is accepted only after confirming that
///   it was consumed as `strong`/`em`/`code`
/// - A partial link `[label` / `[label](https://…` is reduced to plain text
///   containing just the label. The image notation `![alt](url)` falls outside
///   this naturally, because [_applyRenderingFidelity] has already escaped `![`
///   to `\!\[`
String closePartialMarkdown(String partial, {bool complete = false}) {
  final normalized = partial.contains('\r')
      ? partial.replaceAll('\r\n', '\n').replaceAll('\r', '\n')
      : partial;
  // The fence decision (the line-wise regular expression) and the split into
  // runs are computed once and shared by the rendering fidelity stage and the
  // receiving-only stage (image escaping changes neither the number of lines
  // nor the fence decision, so the same [runs] can be used as-is by both
  // stages).
  final lines = normalized.split('\n');
  final isFenceLine = _fenceLineFlags(lines);
  final runs = _splitRuns(isFenceLine);

  final rendered = _applyRenderingFidelity(lines, runs, complete: complete);
  if (complete) return rendered;
  return _applyReceivingHoldbacks(rendered, runs);
}

/// Builds a [Document] with the syntaxes the plan explicitly registers and
/// parses the string that has been run through [closePartialMarkdown].
/// [complete] is passed straight through to [closePartialMarkdown].
List<Node> parseReplyMarkdown(String partial, {bool complete = false}) {
  final outerMemo = _parseMemo;
  _parseMemo = {};
  try {
    return _parse(closePartialMarkdown(partial, complete: complete));
  } finally {
    _parseMemo = outerMemo;
  }
}

// ── Rendering fidelity stage (escaping the image notation. Q8: stop
// re-assembling on the rendering side and instead pin the delimiters in place
// during preprocessing. Always applied regardless of the value of
// [complete]) ──

/// Processes [lines] run by run over [runs] (the spans split by whether a line
/// is a fence, computed by [_fenceLineFlags] → [_splitRuns]): the contents of a
/// fence pass through untouched, and everything else goes through
/// [_escapeImageMarkersInText], which turns the `![` of `![alt](url)` into
/// `\!\[` so that the parser makes it neither an image nor a link
/// (spec: "images are not formatted and appear as literal delimiter
/// characters").
///
/// - The contents of a fence are left untouched (a run that [runs] has already
///   classified line by line via [_LineRun.isFence] passes straight through)
/// - The contents of a code span are left untouched. See
///   [_escapeImageMarkersInText] for the details
/// - When the `!` is itself already escaped (paired with an immediately
///   preceding backslash) it is not image notation, so it is left untouched —
///   by always skipping a backslash together with the single character that
///   follows it as a pair, the CommonMark rule that only an odd-numbered
///   backslash escapes the character after it is satisfied naturally
///   (in `a\![important](url)` the `\!` is consumed as a pair first, so the
///   remaining `[important](url)` becomes a link)
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

/// One run's worth of [_applyRenderingFidelity] (outside a fence. So that code
/// spans crossing several lines can be handled too, the whole joined string is
/// scanned rather than each line separately).
///
/// If it contains no `![` there is nothing to escape and the output would be
/// identical to the input, so the character-by-character scan itself is skipped
/// and the input is returned as-is.
String _escapeImageMarkersInText(String text, {required bool complete}) {
  if (!text.contains('![')) return text;
  final buffer = StringBuffer();
  var i = 0;
  // The position of the `]` of a closed image (`![alt](url)` completed on the
  // same line). When it is reached it is escaped to `\]` so that it cannot be
  // used as the delimiter that closes the `[` of an enclosing link
  // ([Q10] an image inside a link, `[![alt](img)](href)`).
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
          // Receiving, and this is the last paragraph that has not ended yet:
          // a closing backtick may still arrive later, so as before the whole
          // remainder is treated as being inside the code span and left
          // untouched.
          buffer.write(text.substring(i));
          return buffer.toString();
        }
        // Either receiving has finished, or (even while receiving) the
        // paragraph has already ended with a blank line: we now know there is
        // no matching closing backtick within the same paragraph, so rather
        // than assuming this is inside a code span it is written out as plain
        // text and escaping continues from right after it ([Q5]). The reason
        // we come here when the paragraph has already ended is to keep an
        // unmatched backtick from stopping image escaping for the whole rest
        // of the document.
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
    if (ch == _exclamation &&
        i + 1 < text.length &&
        text.codeUnitAt(i + 1) == _leftBracket) {
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

/// The same as [_codeSpanCloseEnd], except that the matching run of closing
/// backticks is looked for only within the same paragraph (up to the next blank
/// line). A match across a paragraph boundary is not treated as a pair, because
/// `package:markdown`'s `CodeSyntax` also treats it as a separate paragraph
/// ([Q5]).
int? _codeSpanCloseEndWithinParagraph(
  String text,
  int openStart,
  int openLength,
) {
  final closeEnd = _codeSpanCloseEnd(text, openStart, openLength);
  if (closeEnd == null) return null;
  final blankLine = text.indexOf('\n\n', openStart);
  if (blankLine != -1 && blankLine < closeEnd) return null;
  return closeEnd;
}

// ── Receiving-only stage (trailing line-level holdbacks and delimiter closing
// for the last block. [closePartialMarkdown] does not call this stage at all
// when [complete] is true) ──

/// Applies, run by run over [runs], the trailing holdbacks
/// ([_applyTrailingHoldbacks]) and the delimiter closing and partial link
/// closing of the last block ([_closeLastBlock]) to [rendered] (the string that
/// has been run through [_applyRenderingFidelity]).
///
/// [runs] is received exactly as [closePartialMarkdown] computed it from the
/// lines before escaping — image escaping changes neither the number of lines
/// nor the fence decision, so the same spans can be used as-is for [rendered].
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
      // An already settled block (another run, such as a fence, follows it):
      // leave it untouched.
      parts.add(runLines.join('\n'));
      continue;
    }
    runLines = _applyTrailingHoldbacks(runLines);
    parts.add(_closeLastBlock(runLines));
  }
  return parts.join('\n');
}

// ── Splitting fences into runs (unchanged: the line-wise regular expression is
// correct enough) ──

/// The run of fence markers captured by [match] (a run of `` ` `` or a run of
/// `~`).
String? _fenceMarker(RegExpMatch? match) =>
    match?.namedGroup('backtick') ?? match?.namedGroup('tilde');

/// The info string of the fence captured by [match].
String? _fenceInfo(RegExpMatch? match) =>
    match?.namedGroup('backtickInfo') ?? match?.namedGroup('tildeInfo');

/// Whether each line is inside a contiguous fence (including the opening and
/// closing lines themselves).
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

/// A span of consecutive lines that all share the same fence-or-not status.
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

/// Drops the last line of the fence contents if it is a partial closing fence
/// (only 1 or 2 of the same character as the opening fence, containing no other
/// characters).
///
/// The character of the opening fence (`` ` `` or `~`) is read from the first
/// line of [lines] (the opening line) — for example, even if a lone `` ` ``
/// arrives inside a fence opened with `~~~`, it cannot become a partial closing
/// fence (a fence can only be closed with the same character as its opening
/// line), so it is not dropped.
List<String> _dropPendingFenceCloserLine(List<String> lines) {
  if (lines.isEmpty) return lines;
  final openMarker = _fenceMarker(_fenceLinePattern.firstMatch(lines.first));
  if (openMarker == null) return lines;
  if (!_looksLikePendingFenceCloser(lines.last, openMarker.codeUnitAt(0))) {
    return lines;
  }
  return lines.sublist(0, lines.length - 1);
}

/// Whether [line] is a partial closing fence (leaving aside up to 3 spaces of
/// leading indentation, only 1 or 2 of [openChar], the same character as the
/// opening fence, in a row).
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

// ── Trailing line-level holdbacks (partial tables and partial block
// markers) ──

/// Holds back the last (receiving) line while looking at whether it holds
/// together as a table, and at whether the next character could turn it into a
/// block marker.
///
/// As a rule the decision is delegated to the parser ("did it hold together as
/// a table?" is decided not by counting columns but by actually parsing the
/// candidate string and checking whether the resulting tag is `table`).
List<String> _applyTrailingHoldbacks(List<String> lines) {
  if (lines.isEmpty) return lines;

  // A trailing line that could become a block marker (only digits, a single
  // `-`/`+`/`*`, and so on): hold it back until the next character settles
  // whether it becomes an ordered list or a bullet list. Even after holding it
  // back, the table decision is still carried out (rather than simply
  // "returning", processing continues below).
  var current = lines;
  // A holdback candidate inside a blockquote is judged on the contents with the
  // `>` stripped off (without stripping, the `>` of `> -` or `> 2` would itself
  // keep the line from matching, and the raw delimiter would become visible
  // without being held back).
  final droppedMarkerLine =
      current.last.isNotEmpty &&
      _looksLikePendingBlockMarkerLine(_stripBlockquotePrefix(current.last));
  if (droppedMarkerLine) {
    current = current.sublist(0, current.length - 1);
  }
  if (current.isEmpty) return current;

  final blankLineAtEnd = current.last.isEmpty;
  final core = blankLineAtEnd
      ? current.sublist(0, current.length - 1)
      : current;
  if (core.isEmpty) return current;
  // "Has the newline at the end of the line arrived?": if even one line has
  // been dropped from the original sequence of lines ([lines]), then the
  // newline of the line before it has already arrived (this holds whether a
  // marker line was dropped or a blank line was dropped).
  final hasTrailingBlank = core.length < lines.length;

  final lastLine = core.last;
  final precedingCore = core.sublist(0, core.length - 1);

  // "Does it hold together as a table?" is decided by actually parsing and
  // checking whether the last top-level element of the result is a table
  // (columns are not counted). If it is a table both with and without this
  // line, then this line is a continuation of the body rows of a table that
  // already holds together (if there is a blank line in between, the version
  // that includes the line does not become a table, so it can be told apart
  // from prose that simply passes through). If it becomes a table only when the
  // line is included, then it first held together exactly when this line (the
  // delimiter row) arrived, so the line is not held back.
  final establishedIncludingLast = _lastTopLevelTag(core.join('\n')) == 'table';
  if (establishedIncludingLast) {
    final establishedBeforeLast =
        precedingCore.isNotEmpty &&
        _lastTopLevelTag(precedingCore.join('\n')) == 'table';
    if (!establishedBeforeLast) {
      return current; // The delimiter row just made it hold together.
    }
    return hasTrailingBlank
        ? current
        : precedingCore; // A body row: waiting for the newline.
  }

  final previousLine = core.length >= 2 ? core[core.length - 2] : null;

  // A partial delimiter row (including the state where only a single `|` has
  // arrived): check whether it holds together as a table when paired with the
  // header row candidate. When they cannot be paired (there is no preceding
  // line, it is empty, or it is a block marker), the decision is left to the
  // general "table row candidate" check below (for a line of only `---` where
  // the preceding line has no `|` either, that check does not match there
  // either and the line simply passes through).
  if (_looksLikeDelimiterRowShape(lastLine) &&
      previousLine != null &&
      _isTableRowCandidate(previousLine)) {
    final established = _parsesAsTable(previousLine, lastLine);
    // If the delimiter row has arrived through its newline, this line will not
    // change any further. If it still does not become a table, it never will,
    // so both lines are released (before the newline arrives it is still
    // partial, so it keeps being held back as before).
    if (established || hasTrailingBlank) return current;
    return core.sublist(0, core.length - 2);
  }

  if (_isTableRowCandidate(lastLine)) {
    final startsWithPipe = lastLine.trimLeft().startsWith('|');
    if (startsWithPipe) {
      // A header row candidate that is not yet settled as a table (it starts
      // with `|`): keep holding it back until the delimiter row arrives (or
      // until complete), regardless of whether the newline has arrived.
      return precedingCore;
    }
    // A | in prose: hold back only from that | to the end of the line. Once the
    // newline arrives it is known not to be a table, so everything is revealed.
    if (hasTrailingBlank) return current;
    final pipeIndex = _firstUnescapedPipeOutsideCodeSpan(lastLine)!;
    return [...precedingCore, lastLine.substring(0, pipeIndex)];
  }

  return current;
}

/// Whether [line] is a trailing line that could become a block marker: the
/// shape where any amount of indentation is followed by (a single `-`/`+`/`*`,
/// or 1 to 9 digits (optionally with a `.` or `)`)), and the line then ends
/// with 0 or 1 trailing whitespace characters (a space or a tab). An indented
/// nested list marker (`  - `, `   1.` and so on) is covered by the same rule
/// as a top-level one. A lone `#` is not covered, because it becomes a heading
/// with empty contents and adds no visible characters.
///
/// Only ASCII spaces and tabs are treated as indentation (`String.trimLeft`
/// would also strip Unicode whitespace, making even a line such as `　1.` that
/// starts with the ideographic space U+3000 a block marker candidate, so only
/// ASCII is stripped here by hand).
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
  if (digitsEnd == body.length) return true; // Digits only.
  if (digitsEnd == body.length - 1) {
    final marker = body.codeUnitAt(digitsEnd);
    return marker == _period || marker == _rightParen;
  }
  return false;
}

/// Whether the line starts with a block marker (`#`, `- ` `* ` `+ ` `1. ` and
/// so on, `> `, a fence). A line starting with one of these cannot become a
/// table, so it is not held back as a table header row candidate.
bool _startsWithBlockMarker(String line) {
  if (_looksLikeHeadingLine(line)) return true;
  if (_looksLikeListMarker(line)) return true;
  if (_startsWithBlockquoteMarker(line)) return true;
  if (_fenceLinePattern.hasMatch(line)) return true;
  return false;
}

/// Whether the line can be a candidate for holding back just the last line (a
/// line that does not start with a block marker and contains a `|` outside a
/// code span). A partial delimiter row that contains no pipe, such as `---`, is
/// not covered here (it is handled only in [_canPairWithHeaderCandidate]).
bool _isTableRowCandidate(String line) {
  if (_startsWithBlockMarker(line)) return false;
  return _firstUnescapedPipeOutsideCodeSpan(line) != null;
}

/// Whether the line has the shape of a delimiter row (a run of only `-`, `:`,
/// `|` and whitespace that contains at least one `|` or `-`). This is a loose
/// check, so that a partial delimiter row (including a run partway through
/// where not a single hyphen has arrived yet) is also recognized as a table
/// row. Whether it actually "holds together" is decided by really parsing it in
/// [_parsesAsTable]. A line with neither `|` nor `-` (only whitespace and `:`)
/// is not considered a partial delimiter row — making a whitespace-only line,
/// or a continuation of prose that is just a `:`, a delimiter row candidate
/// would wrongly erase even the already revealed preceding line when it fails
/// to hold together.
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

/// Whether [headerLine] + [delimiterLine] actually holds together as a table
/// (the parser decides; columns are not counted).
bool _parsesAsTable(String headerLine, String delimiterLine) {
  final nodes = _parse('$headerLine\n$delimiterLine');
  return nodes.length == 1 &&
      nodes.single is Element &&
      (nodes.single as Element).tag == 'table';
}

/// The tag of the last top-level element of the result of parsing [text] (null
/// if there is none).
String? _lastTopLevelTag(String text) {
  if (text.isEmpty) return null;
  final nodes = _parse(text);
  if (nodes.isEmpty) return null;
  final last = nodes.last;
  return last is Element ? last.tag : null;
}

/// Returns the position of a `|` in the line that is outside a code span and
/// not escaped, if there is one (anything inside an unclosed code span is out
/// of scope). Returns null if there is none.
int? _firstUnescapedPipeOutsideCodeSpan(String line) {
  var i = 0;
  while (i < line.length) {
    final ch = line.codeUnitAt(i);
    if (ch == _backquote) {
      final openEnd = _runEnd(line, i, _backquote);
      final closeEnd = _codeSpanCloseEnd(line, i, openEnd - i);
      if (closeEnd == null) {
        return null; // Not closed: everything after this is inside.
      }
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

/// A list marker at the start of the line (`- ` `* ` `+ `, or `1. ` `12) ` and
/// so on).
bool _looksLikeListMarker(String line) => _listMarkerKind(line) != null;

bool _isDigit(int codeUnit) => codeUnit >= 0x30 && codeUnit <= 0x39;

/// The index of the end of the run of consecutive digits (at most 9) starting
/// at [start] in [text] ([start] itself if there are no digits).
int _digitRunEnd(String text, int start) {
  var i = start;
  while (i < text.length && i - start < 9 && _isDigit(text.codeUnitAt(i))) {
    i++;
  }
  return i;
}

/// [line] with only the leading ASCII whitespace (spaces and tabs) stripped off
/// (unlike `String.trimLeft`, other Unicode whitespace such as the ideographic
/// space is not treated as indentation).
String _trimAsciiLeadingWhitespace(String line) {
  var i = 0;
  while (i < line.length &&
      (line.codeUnitAt(i) == _space || line.codeUnitAt(i) == _tab)) {
    i++;
  }
  return line.substring(i);
}

/// A heading line, `#` through `######`.
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

bool _startsWithBlockquoteMarker(String line) =>
    line.trimLeft().startsWith('>');

// ── Delimiter closing and partial link closing for the last block ──

/// The last (receiving) block that delimiter closing and partial link closing
/// apply to.
class _ClosingTarget {
  _ClosingTarget(this.lines, this.tag);

  /// The lines of the target block itself (for `ul`/`ol`/`blockquote`, narrowed
  /// down to its last child).
  final List<String> lines;

  /// The tag of the target block (for `table`/`pre`, neither delimiter closing
  /// nor partial link closing is performed).
  final String tag;
}

/// Locates the last block within [runLines] that delimiter closing and partial
/// link closing apply to, cross-checking it against the result of a plain parse
/// (the decision is not made from how the lines look alone).
///
/// If the last top-level element is `ul`/`ol`/`blockquote`, it is narrowed down
/// recursively to its last child (the last `li`, or the last child block) — so
/// that even within the same last top-level element, earlier items that are
/// already settled are not rewritten. If the narrowing fails (the corresponding
/// range of lines cannot be identified), null is returned and the caller gives
/// up delimiter closing and partial link closing for that block (taking the
/// whole thing as the target without narrowing would be more dangerous, because
/// getting the range wrong rewrites content that is already settled).
///
/// If the last element is `table`/`pre` it is out of scope for delimiter
/// closing and partial link closing ([_closeLastBlock] rejects it by looking at
/// the tag alone), so we bail out on `nodes.last.tag` alone before entering the
/// narrowing (this case can occur frequently across all the prefixes seen while
/// receiving, so no narrowing work is wasted on it).
///
/// Otherwise, a line-wise heuristic ([_minimalTrailingLinesForNode] /
/// [_minimalTrailingLinesForChild]) estimates a single candidate start line, and
/// only that candidate is actually parsed and checked (Q1: an exhaustive search
/// from the end plus a re-parse is O(lines²), so that approach is abandoned).
/// For the rare case where the estimate is wrong, and only then, it falls back
/// to brute force over up to the last 8 lines ([_bruteForceFallbackLimit]) (if
/// nothing is found, that frame is not closed).
_ClosingTarget? _findClosingTarget(List<String> runLines) {
  if (runLines.isEmpty) return null;
  final nodes = _parse(runLines.join('\n'));
  if (nodes.isEmpty) return null;

  Node node = nodes.last;
  if (node is Element && (node.tag == 'table' || node.tag == 'pre')) {
    return null; // Out of scope for delimiter closing and partial link closing.
  }

  final initialLines = _minimalTrailingLinesForNode(runLines, node);
  if (initialLines == null) return null;
  var lines = initialLines;

  while (node is Element &&
      (node.tag == 'ul' || node.tag == 'ol' || node.tag == 'blockquote')) {
    final children = node.children;
    if (children == null || children.isEmpty) break;
    final lastChild = children.last;
    final narrowed = _minimalTrailingLinesForChild(lines, node.tag, lastChild);
    if (narrowed == null) break;
    lines = narrowed;
    node = lastChild;
  }

  // If the last child block inside a blockquote or a list is a table/pre, it is
  // out of scope for delimiter closing and partial link closing here too
  // ([_closeLastBlock] rejects it by looking at the tag).
  final tag = node is Element ? node.tag : 'text';
  return _ClosingTarget(lines, tag);
}

/// Searches from the end of [lines] for the smallest run of consecutive
/// trailing lines whose result, parsed on its own, satisfies [matches].
///
/// [guess] (the candidate start line the caller estimated in advance) is tried
/// once first, and if it matches that is all that is needed. For the rare case
/// where it is wrong (or could not be estimated), and only then, it falls back
/// to brute force over up to the last [_bruteForceFallbackLimit] lines
/// ([Q1]/[Q2]: even in the rare case where the estimate is wrong, letting this
/// brute force itself grow with the square of the number of lines would bring
/// back the very quadratic cost this was meant to remove, so a cap is set).
/// If nothing is found, null is returned and the caller skips delimiter closing
/// and partial link closing for that frame — not closing may mean raw
/// delimiters are visible for one frame, but that is the safer side compared to
/// quadratic latency.
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
    if (start == guess) continue; // Already tried as the estimate.
    final candidateLines = lines.sublist(start);
    if (matches(candidateLines)) return candidateLines;
  }
  return null;
}

/// The cap on how many candidate start lines from the end are tried in the
/// fallback brute force used when the estimate is wrong.
const _bruteForceFallbackLimit = 8;

/// Searches from the end of [lines] for the smallest run of consecutive
/// trailing lines whose result, parsed on its own, becomes the same HTML as
/// [target] (delegated to [_minimalTrailingLines]; the start line is estimated
/// by [_guessTopLevelStart]).
List<String>? _minimalTrailingLinesForNode(List<String> lines, Node target) {
  final targetHtml = HtmlRenderer().render([target]);
  bool matches(List<String> candidateLines) {
    final candidateNodes = _parse(candidateLines.join('\n'));
    return candidateNodes.length == 1 &&
        HtmlRenderer().render(candidateNodes) == targetHtml;
  }

  return _minimalTrailingLines(
    lines,
    _guessTopLevelStart(lines, target),
    matches,
  );
}

/// Searches from the end of [lines] for the smallest run of consecutive
/// trailing lines whose result, parsed on its own, becomes a single element with
/// the tag [containerTag] and whose last child becomes the same HTML as
/// [targetChild] (delegated to [_minimalTrailingLines]; the start line is
/// estimated by [_guessChildStart]). Only the child is compared because
/// attributes of the container itself, such as the `start` attribute of `ol`,
/// can differ from candidate to candidate (`start` changes as the number of
/// items drops).
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

  return _minimalTrailingLines(
    lines,
    _guessChildStart(lines, containerTag),
    matches,
  );
}

// ── Heuristics for the start line of the last block (Q1: instead of brute
// force over up to the last 8 lines, a single candidate is estimated from the
// shape of the lines alone. Confirming that it is correct is left to the
// caller's single parse) ──

/// Estimates, according to the kind of [target] (the last top-level element),
/// the line within [lines] at which that element starts (null if there is none;
/// the caller then falls back to brute force over up to the last 8 lines
/// ([_bruteForceFallbackLimit]), and if nothing is found that frame is not
/// closed).
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
        return _lastNonBlankIndex(
          lines,
        ); // ATX heading = always 1 line (trailing blanks aside).
    }
  }
  return _lastParagraphStartHeuristic(lines);
}

/// Estimates the line at which the last child of [containerTag]
/// (`ul`/`ol`/`blockquote`) starts, within [lines], which has already been
/// narrowed down to the container's own lines.
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

/// The start line of a paragraph (or of an element that has no tag): the line
/// right after the nearest preceding blank line, or right after the line
/// holding a block marker (heading, list, blockquote, fence).
///
/// Even when several blank lines follow at the end (this shape occurs partway
/// through the `\n\n` that separates blocks arriving one character at a time),
/// we first move to the last non-blank line with [_lastNonBlankIndex] and only
/// then look for the boundary — otherwise "the preceding line" immediately hits
/// a blank line and the search stops without going back a single line.
int _lastParagraphStartHeuristic(List<String> lines) {
  var start = _lastNonBlankIndex(lines);
  while (start > 0 && !_looksLikeBlockBoundary(lines[start - 1])) {
    start--;
  }
  return start;
}

/// Whether [line] is a boundary that ends a paragraph (a blank line, or a line
/// holding a block marker).
bool _looksLikeBlockBoundary(String line) =>
    line.trim().isEmpty || _startsWithBlockMarker(line);

/// The index of the last non-blank line looking back from the end of [lines] (0
/// if every line is blank).
int _lastNonBlankIndex(List<String> lines) {
  var i = lines.length - 1;
  while (i > 0 && lines[i].trim().isEmpty) {
    i--;
  }
  return i;
}

/// The start line of a list (separating the container as a whole from another
/// block that precedes it): go back as long as each preceding line is a blank
/// line, an indented continuation line, or a marker line of this list **of the
/// same kind**. If the line we went back to is a blank line, that much (the
/// blank line before the list) is not included (the range is kept minimal).
///
/// [strip] transforms each line before the comparison (for lists inside a
/// blockquote: strip the `>` before looking at indentation and markers; the
/// default passes the line through).
///
/// When a marker line is reached whose marker kind ([_listMarkerKind]: the
/// bullet character, or the separator character of an ordered list) differs from
/// that of the last line, going back stops even across a blank line ([Q2]: at a
/// point where the kind changes, as in `- a\n- b\n\n1. c\n1. d`, the parser also
/// makes separate `ul`/`ol` elements, so estimating across that point as one
/// list makes `nodes.length` 2, the estimate misses and it drops into the
/// fallback brute force).
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

/// Whether [line] (with [_lastListContainerStartHeuristic]'s [strip] already
/// applied) counts as a continuation of a list of kind [refKind]: a blank line
/// or an indented continuation line counts as a continuation regardless of
/// kind. A list marker line counts as a continuation only when its marker kind
/// matches [refKind] (or when [refKind] is still null, that is, no kind has been
/// encountered yet).
bool _looksLikeListContinuation(String line, int? refKind) {
  if (line.trim().isEmpty) return true;
  if (_indentOf(line) > 0) return true;
  final kind = _listMarkerKind(line);
  return kind != null && (refKind == null || kind == refKind);
}

/// The kind of list marker on [line] (for a bullet list, the character code of
/// the marker; for an ordered list, the character code of the separator
/// character, `.` or `)`). Null if the line is not a marker line.
/// [_lastListContainerStartHeuristic] uses this to decide, across a blank line,
/// whether a line continues the same list, by checking that the marker kind has
/// not changed (when the kind changes it becomes a separate list in CommonMark
/// as well, so the blank line is not crossed).
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
      (trimmed.codeUnitAt(i + 1) != _space &&
          trimmed.codeUnitAt(i + 1) != _tab)) {
    return null;
  }
  return marker;
}

/// The start line of the last item (`li`) of a list: within [lines] (the list's
/// own lines), the last of the marker lines whose indentation matches that of
/// the first line.
int? _lastListItemStartHeuristic(List<String> lines) {
  final baseIndent = _indentOf(lines.first);
  for (var i = lines.length - 1; i >= 0; i--) {
    if (_indentOf(lines[i]) == baseIndent && _looksLikeListMarker(lines[i])) {
      return i;
    }
  }
  return null;
}

/// The start line of a blockquote (the container as a whole): go back to the
/// first of the consecutive `>` lines. Multiple trailing blank lines are skipped
/// first with [_lastNonBlankIndex] (for the same reason as in
/// [_lastParagraphStartHeuristic]).
int _lastBlockquoteStartHeuristic(List<String> lines) {
  var start = _lastNonBlankIndex(lines);
  while (start > 0 && _startsWithBlockquoteMarker(lines[start - 1])) {
    start--;
  }
  return start;
}

/// The start line of the last child block of a blockquote: the same boundary
/// check as for a paragraph (a blank line, or a line holding a block marker) is
/// applied to the contents with the `>` stripped off. Multiple trailing blank
/// lines are handled the same way as in [_lastParagraphStartHeuristic].
///
/// If the last line (blank lines aside) is a list marker once the `>` is
/// stripped, the last child is a list (`ul`/`ol`), so instead of the paragraph
/// boundary check the work is delegated to [_lastListContainerStartHeuristic]
/// (which strips the `>` before comparing) ([Q1]: because the paragraph
/// boundary check regards a list marker line itself as a "boundary", the
/// stripped remainder would immediately hit a list marker line and could not go
/// back a single line, which dropped every long list inside a blockquote into
/// the fallback brute force).
int _lastBlockquoteChildStartHeuristic(List<String> lines) {
  final anchor = _lastNonBlankIndex(lines);
  final strippedAnchor = _stripBlockquotePrefix(lines[anchor]);
  // If the stripped contents are a list marker, or are empty (as in a `>` that
  // continues a blockquote with no contents), this may be the continuation of a
  // list, so the work is delegated to [_lastListContainerStartHeuristic]. Even
  // when it turns out not to be a list (for example an empty blockquote
  // continuation after a paragraph), that candidate simply fails to match in
  // [_minimalTrailingLinesForChild]'s comparison and safely falls back to the
  // capped brute force, so delegating too eagerly does no harm.
  if (_listMarkerKind(strippedAnchor) != null ||
      strippedAnchor.trim().isEmpty) {
    return _lastListContainerStartHeuristic(
      lines,
      strip: _stripBlockquotePrefix,
    );
  }
  var start = anchor;
  while (start > 0 &&
      !_looksLikeBlockBoundary(_stripBlockquotePrefix(lines[start - 1]))) {
    start--;
  }
  return start;
}

/// The contents of [line] with the leading `>` (and the single space
/// immediately after it) stripped off. If it does not start with `>` it is
/// returned as-is.
String _stripBlockquotePrefix(String line) {
  if (!_startsWithBlockquoteMarker(line)) return line;
  final trimmedLeft = line.trimLeft();
  final afterMarker = trimmedLeft.substring(1);
  return afterMarker.startsWith(' ') ? afterMarker.substring(1) : afterMarker;
}

/// The number of leading indentation characters (spaces and tabs) of [line].
int _indentOf(String line) => line.length - line.trimLeft().length;

/// Performs delimiter closing and the closing of partial links on the lines of
/// the last non-fence run, once the trailing line-level holdbacks have been
/// applied.
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

// ── Partial links ──

/// Turns a partial link `[label` / `[label](url` into plain text containing
/// just the label.
///
/// The `[` of the image notation `![alt](url` (the one preceded by `!`) is out
/// of scope — it is always left untouched. Because the rendering fidelity stage
/// ([_applyRenderingFidelity]) that runs before this preprocessing has already
/// escaped `![` to `\!\[`, this branch is not normally reached, but it is kept
/// as a safeguard for paths the escaping does not reach. A closed link
/// `[label](url)` is left untouched as-is (the parser turns it into a link).
/// The inside of an inline code span passes through together with the code span
/// delimiters, and `[` `]` `(` `)` there are not interpreted as link
/// delimiters.
String _closePartialLinks(String text) {
  final buffer = StringBuffer();
  var i = 0;
  while (i < text.length) {
    if (text.codeUnitAt(i) == _backquote) {
      final openEnd = _runEnd(text, i, _backquote);
      final closeEnd = _codeSpanCloseEnd(text, i, openEnd - i);
      if (closeEnd == null) {
        // An unclosed code span: the whole remainder is inside it, so write it
        // out as-is and finish.
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
      // Cut off partway through the label: drop the [ and keep just the label.
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
          // The URL is cut off before the newline: drop only the URL part and,
          // instead of discarding what comes after the newline, keep scanning
          // as usual (so that characters that arrived on the next line are not
          // erased).
          buffer.write(label);
          i = newlineInUrl;
          continue;
        }
        // The string ends without even a newline: keep just the label.
        buffer.write(label);
        return buffer.toString();
      }
      // A closed link: write it out untouched.
      buffer.write(text.substring(i, urlEnd + 1));
      i = urlEnd + 1;
      continue;
    }

    if (afterLabel == text.length) {
      // The closing bracket has arrived but the string ends before the ( does:
      // turn it into plain text containing just the label (never showing a raw
      // [ ] even for an instant).
      buffer.write(label);
      return buffer.toString();
    }

    // The `[label]` shape (no URL; what follows is some character other than
    // an opening parenthesis) is out of scope for this slice, so it is left
    // untouched.
    buffer.write(text.substring(i, labelEnd + 1));
    i = labelEnd + 1;
  }
  return buffer.toString();
}

/// Searches from [start] for the position where [target] occurs, skipping over
/// escapes. Returns -1 if there is none.
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

/// Searches from [start] (the beginning of the URL) for the `)` that ends the
/// link destination. A matched pair of `(` `)` inside the URL (`Foo_(bar)` and
/// the like) is not counted as the closing parenthesis (the pairing of `(` and
/// `)` is counted). The search is limited to within the same line (crossing a
/// newline is treated as not finding it). Null if it is not found.
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

/// Returns the position at which the code span of length [openLength] that
/// starts at [openStart] in [text] (the beginning of the run of `` ` ``) closes
/// (the index just after the closing run). Null if it does not close (a
/// backslash has no meaning for code span delimiters).
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

// ── Delimiter closing for the last block ──

/// Closes the unclosed `**` `*` `__` `_` `` ` `` left at the end of [blockText]
/// (the raw string of the last block itself).
///
/// Finding the candidates is delegated to [_scanDelimiterTokens] (the
/// can-open/can-close decision exactly as in CommonMark's flanking rules), but
/// **whether a candidate is accepted is confirmed by the parser**: starting from
/// the innermost candidate, exactly one closing delimiter is added, the text is
/// re-parsed, and only those for which the number of `strong`/`em`/`code`
/// elements actually increased are kept. If it does not increase, the loop stops
/// there (candidates further out are meaningless anyway unless the inner one
/// closes). A trailing opening delimiter whose contents so far are only
/// whitespace is dropped without any need to confirm (and if the outer one left
/// empty by that drop also has no contents, it is dropped in turn).
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
    // A run that canClose but has no matching opening delimiter is left as-is
    // (it passes through).
  }
  if (stack.isEmpty) return blockText;

  var result = blockText;
  while (stack.isNotEmpty && _isAllLineWhitespace(result, stack.last.end)) {
    final candidate = stack.removeLast();
    result =
        result.substring(0, candidate.start) + result.substring(candidate.end);
  }
  if (stack.isEmpty) return result;

  var acceptedCount = _emphasisLikeElementCount(_parse(result));
  while (stack.isNotEmpty) {
    final opener = stack.last;
    final insertAt = _closerInsertionPoint(result);
    final candidate =
        result.substring(0, insertAt) +
        opener.marker +
        result.substring(insertAt);
    final candidateNodes = _parse(candidate);
    final candidateCount = _emphasisLikeElementCount(candidateNodes);
    // An increase in the count alone is not enough to accept it: reject the
    // shape where only part of the closing delimiter we added is consumed by an
    // element and the rest trails behind as raw delimiter characters (only 1 of
    // the 3 characters of `***` used to close an `em` while the other 2 are
    // left floating, and so on. This preprocessing's run-length matching cannot
    // reproduce CommonMark's run splitting, so we actually render and check),
    // and likewise the shape where the delimiter we added merely paired up with
    // a different (unrelated) opening delimiter and pushed the count up. This is
    // checked by whether the delimiter character itself is left raw right after
    // where we added it (whether the end of the AST's text ends with the closing
    // delimiter character) ([Q4]). The AST's [Node.textContent] is used
    // (rendering to HTML and stripping tags with a regular expression would,
    // because of `encodeHtml: false`, wrongly strip a raw `<` in the body as if
    // it were a tag).
    final leftoverRawMarker = candidateNodes
        .map((node) => node.textContent)
        .join()
        .trimRight()
        .endsWith(String.fromCharCode(opener.char));
    if (candidateCount <= acceptedCount || leftoverRawMarker) {
      break; // Not consumed: close nothing beyond this.
    }
    result = candidate;
    acceptedCount = candidateCount;
    stack.removeLast();
  }
  return result;
}

/// The total number of `strong`/`em`/`code` elements appearing in [nodes]
/// (counted recursively).
int _emphasisLikeElementCount(List<Node> nodes) {
  var count = 0;
  void visit(Node node) {
    if (node is Element) {
      if (node.tag == 'strong' || node.tag == 'em' || node.tag == 'code') {
        count++;
      }
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

/// Whether everything from [start] on in [text] is only whitespace (spaces,
/// tabs, newlines), or nothing has arrived at all.
bool _isAllLineWhitespace(String text, int start) {
  for (var i = start; i < text.length; i++) {
    if (!_isUnicodeWhitespace(text.codeUnitAt(i))) return false;
  }
  return true;
}

/// The position just before the trailing whitespace (spaces, tabs, newlines)
/// and any blockquote continuation with no contents (`\n>` `\n> `).
///
/// A blockquote continuation with no contents is skipped over as well because
/// placing the closing delimiter there would put it after the `>` (at the end of
/// `> quote **bold\n>`, for example), where the closing delimiter would not be
/// right-flanking and would stay visible as a raw delimiter — the closing
/// delimiter is placed immediately after the last character that actually has
/// contents.
int _closerInsertionPoint(String text) {
  var i = text.length;
  while (i > 0) {
    final unit = text.codeUnitAt(i - 1);
    if (_isUnicodeWhitespace(unit)) {
      i--;
      continue;
    }
    if (unit == _greaterThan &&
        _isEmptyBlockquoteContinuationMarker(text, i - 1)) {
      i--;
      continue;
    }
    break;
  }
  return i;
}

/// Whether [index] (the position of a `>`) is the `>` of a "blockquote
/// continuation with no contents": the character before it is a newline (or it
/// is the start of the string), and immediately after [index] comes whitespace,
/// a newline, or the end of the string (no blockquote contents have arrived
/// after the `>`).
bool _isEmptyBlockquoteContinuationMarker(String text, int index) {
  if (index > 0 && text.codeUnitAt(index - 1) != _newline) return false;
  final after = index + 1;
  if (after >= text.length) return true;
  final unit = text.codeUnitAt(after);
  return unit == _space || unit == _tab || unit == _newline;
}

/// A single run of opening/closing delimiters that [_closeTrailingDelimiters]
/// works on.
///
/// Only a run that [canOpen] is pushed onto the stack, and a run that [canClose]
/// pops the matching opening delimiter (CommonMark's can-open / can-close
/// decision).
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

  /// The run of delimiter characters itself (`**` `*` `__` `_` `` ` ``).
  String get marker => String.fromCharCode(char) * length;

  /// A token with the same contents whose position is shifted by [offset] (used
  /// to map a link label back into the parent's coordinate system).
  _DelimiterToken shift(int offset) => _DelimiterToken(
    char,
    start + offset,
    end + offset,
    canOpen: canOpen,
    canClose: canClose,
  );
}

/// Collects, in order of occurrence, the runs of `**` `*` `__` `_` `` ` `` that
/// count as opening/closing delimiters.
///
/// Left out of scope are: the inside of a code span (up to the run of backticks
/// of the same length that closes it), the inside of the `](…)` of a closed
/// (completed) link, a bullet list marker at the start of a line
/// (`* ` `- ` `+ `), and a word-internal `_` (alphanumeric on both sides). For
/// `*`/`_`, can-open and can-close are decided exactly as in CommonMark's
/// flanking rules:
/// - `*`: can-open = left-flanking, can-close = right-flanking
/// - `_`: can-open = left-flanking and (not right-flanking or preceded by
///   punctuation), can-close = right-flanking and (not left-flanking or
///   followed by punctuation)
///
/// A run with punctuation both before and after it (a shape such as `(*)`; see
/// [_isFlankedByPunctuationOnBothSides]) is excluded from the can-open decision
/// only (it is not applied to can-close). For a run whose next character has not
/// arrived yet (at the end), the left-flanking decision is deferred and it is
/// regarded as can-open. [initialAtLineStart] is whether the start of [text] is
/// really the start of a line (it is false when the label of a closed link is
/// scanned recursively).
///
/// Whether the candidates found here can really be closed is confirmed by
/// [_closeTrailingDelimiters], which actually parses — this function only lists
/// the candidates, it does not decide whether they are accepted.
List<_DelimiterToken> _scanDelimiterTokens(
  String text, {
  bool initialAtLineStart = true,
}) {
  final tokens = <_DelimiterToken>[];
  var i = 0;
  var atLineStart = initialAtLineStart;
  while (i < text.length) {
    final ch = text.codeUnitAt(i);
    if (ch == _backquote) {
      final openEnd = _runEnd(text, i, _backquote);
      final openLength = openEnd - i;
      tokens.add(
        _DelimiterToken(_backquote, i, openEnd, canOpen: true, canClose: false),
      );
      final closeEnd = _codeSpanCloseEnd(text, i, openLength);
      if (closeEnd == null) {
        // Not closed: everything after this is inside the code span, so stop
        // scanning.
        break;
      }
      tokens.add(
        _DelimiterToken(
          _backquote,
          closeEnd - openLength,
          closeEnd,
          canOpen: false,
          canClose: true,
        ),
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
          _scanDelimiterTokens(
            text.substring(labelStart, labelEnd),
            initialAtLineStart: false,
          ).map((t) => t.shift(labelStart)),
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
      // An unclosed `](` (such as the URL left over after escaping an image):
      // from here on we are partway through a link destination, so it is not
      // scanned for emphasis delimiter candidates (so that a `_` inside the URL
      // and the like are not picked up).
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
        // A bullet list marker (`* ` `- ` `+ `): not counted as an opening
        // delimiter.
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
          // A word-internal `_` (for example the first one in my_var): made
          // neither an opening nor a closing delimiter.
          i = end;
          continue;
        }
      }
      final leftFlanking = _isLeftFlanking(text, i, end);
      final rightFlanking = _isRightFlanking(text, i, end);
      final bool canOpen;
      final bool canClose;
      if (ch == _asterisk) {
        canOpen =
            leftFlanking && !_isFlankedByPunctuationOnBothSides(text, i, end);
        canClose = rightFlanking;
      } else {
        final precededByPunctuation =
            i > 0 && _isUnicodePunctuation(text.codeUnitAt(i - 1));
        final followedByPunctuation =
            end < text.length && _isUnicodePunctuation(text.codeUnitAt(end));
        // For a run at the end of the string (no character at all has arrived
        // after it), the right-flanking "word-internal `_`" exclusion rule is
        // not applied and the run is treated as an opening delimiter with no
        // contents (if there is no matching opening delimiter,
        // [_closeTrailingDelimiters] drops it). Otherwise, for example, the
        // trailing `_` of `と __太字_` would be neither can-open nor can-close,
        // would pass through without becoming a token, and the parser would
        // consume just one of them, ending up with something like
        // `_<em>太字</em>`.
        final atTextEnd = _isAllLineWhitespace(text, end);
        canOpen =
            atTextEnd ||
            (leftFlanking &&
                (!rightFlanking || precededByPunctuation) &&
                !_isFlankedByPunctuationOnBothSides(text, i, end));
        canClose = rightFlanking && (!leftFlanking || followedByPunctuation);
      }
      if (canOpen || canClose) {
        tokens.add(
          _DelimiterToken(ch, i, end, canOpen: canOpen, canClose: canClose),
        );
      }
      i = end;
      continue;
    }
    i++;
  }
  return tokens;
}

/// Detects a closed (completed) link `[label](url)` starting at [start] (the
/// `[`). If one is found, returns (label start, label end, just after the
/// closing parenthesis); otherwise null. It does not matter whether this is
/// image notation (a `[` immediately after a `!`) — whether it is treated as a
/// link at render time is a separate matter, and as something to leave out of
/// the scan it is treated the same as an ordinary link.
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

/// A simplified version of whether the run of delimiters in [start, end) is
/// CommonMark left-flanking (can become an opening delimiter). When the next
/// character has not arrived yet (at the end), or only whitespace has arrived,
/// it is regarded as flanking, in order to preserve the existing behavior of
/// provisionally treating not-yet-closed notation as an opening delimiter (a
/// trailing opening delimiter whose contents are only whitespace is dropped
/// rather than closed).
bool _isLeftFlanking(String text, int start, int end) {
  if (_isAllLineWhitespace(text, end)) return true;
  final next = text.codeUnitAt(end);
  if (_isUnicodeWhitespace(next)) return false;
  if (!_isUnicodePunctuation(next)) return true;
  final prev = start > 0 ? text.codeUnitAt(start - 1) : null;
  return prev == null ||
      _isUnicodeWhitespace(prev) ||
      _isUnicodePunctuation(prev);
}

/// A simplified version of whether the run of delimiters in [start, end) is
/// CommonMark right-flanking (can become a closing delimiter). The start of a
/// block (no preceding character) is treated the same as whitespace at the
/// start of a line, that is, as not flanking.
bool _isRightFlanking(String text, int start, int end) {
  if (start <= 0) return false;
  final prev = text.codeUnitAt(start - 1);
  if (_isUnicodeWhitespace(prev)) return false;
  if (!_isUnicodePunctuation(prev)) return true;
  final next = end < text.length ? text.codeUnitAt(end) : null;
  return next == null ||
      _isUnicodeWhitespace(next) ||
      _isUnicodePunctuation(next);
}

/// Whether both the character before and the character after the run of
/// delimiters in [start, end) are punctuation (a shape such as `(*)` or `"*"`.
/// Rule 2b of CommonMark's left-flanking / right-flanking both accept this
/// shape as flanking, but it is a shape where the characters are used as plain
/// delimiters rather than as a not-yet-closed emphasis, so it is left out of
/// the opening delimiter candidates. It does not apply when either side is
/// missing (the start or the end of the string)).
bool _isFlankedByPunctuationOnBothSides(String text, int start, int end) {
  if (start <= 0 || end >= text.length) return false;
  return _isUnicodePunctuation(text.codeUnitAt(start - 1)) &&
      _isUnicodePunctuation(text.codeUnitAt(end));
}

/// Whether [codeUnit] is CommonMark Unicode whitespace
/// ([DelimiterRun.unicodeWhitespace] is used as-is. In addition to ASCII spaces
/// and newlines it also covers the ideographic space U+3000 and U+00A0 —
/// narrowing this to ASCII by hand would place a closing delimiter immediately
/// after an ideographic space, which disagrees with the parser's right-flanking
/// decision).
bool _isUnicodeWhitespace(int codeUnit) =>
    DelimiterRun.unicodeWhitespace.contains(String.fromCharCode(codeUnit));

/// Whether [codeUnit] is CommonMark Unicode punctuation
/// ([DelimiterRun.unicodePunctuationPattern] is used as-is. It is defined in
/// `markdown-7.3.1`'s `lib/src/inline_syntaxes/delimiter_syntax.dart` and
/// exposed from `package:markdown/markdown.dart`. A hand-written check covering
/// only ASCII punctuation would miss Japanese punctuation such as
/// `、。「」（）・！？：`, and would then diverge from the parser's flanking
/// decision).
bool _isUnicodePunctuation(int codeUnit) => DelimiterRun
    .unicodePunctuationPattern
    .hasMatch(String.fromCharCode(codeUnit));

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
