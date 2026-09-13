import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:markdown/markdown.dart';
import 'package:streaming_markdown_widget/src/partial_markdown.dart';

/// 前処理 + parse の結果を HTML にして覗くためのヘルパ (AC-23〜AC-27)。
///
/// 前処理が返す文字列そのものは実装の自由度を残すため直接は見ず、
/// `partial_markdown_test.dart` と同じく [HtmlRenderer] の HTML で比べる。
/// Widget も Ticker も要らない純 Dart。

/// 出現位置までの Markdown を前処理 + parse し、HTML 文字列にする。
///
/// ブロックの間に改行が入るので前後の空白は落とす。
String renderReplyHtml(String partial, {bool complete = false}) =>
    HtmlRenderer().render(parseReplyMarkdown(partial, complete: complete)).trim();

/// 前処理を通さず、plan が明示登録した構文だけの素の [Document] に通して
/// HTML 文字列にする (AC-27 の「前処理なし」の比較対象)。
///
/// [parseReplyMarkdown] と同じ構文の並びを、同じ理由 (リンク参照定義の状態を
/// 持ち越さない) で呼び出しごとに作り直す。
String renderRawHtml(String markdown) => HtmlRenderer()
    .render(
      Document(
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
      ).parse(markdown),
    )
    .trim();

/// 可視文字列: HTML からタグを剥ぎ、空白 (改行・スペース) も落としたもの。
///
/// 空白を落とすのは、[HtmlRenderer] がブロックの区切りや中身の空のブロック
/// (`#` だけ届いた見出し・`-` だけ届いた箇条書きなど) にも改行を吐くため。
/// 空白を残すと、可視文字が 1 つも増えていない prefix の間でも「次の prefix の
/// 可視文字列の先頭部分になっている」性質が改行の増減だけで破れてしまう。
/// 記号が残っていないかの検査には空白を保つ [proseTextOf] を使う。
String visibleTextOf(String html) =>
    _stripTags(html).replaceAll(RegExp(r'\s+'), '');

/// 記号の検査に使う文字列: コードブロック (`<pre>`) とコードスパン (`<code>`)
/// の中身を丸ごと除いてからタグを剥いだもの。空白はそのまま残す。
///
/// 空白を残すのは、落とすと `- - -` のような離れた記号が `---` にくっついて
/// 偽の検出になるため。コードの中身を除くのは AC-26 の但し書き
/// (「コードブロック `<pre>` の中身と、コードスパン `<code>` の中身は
/// 検査から除く」) のとおり。
String proseTextOf(String html) => _stripTags(
  html
      .replaceAll(RegExp(r'<pre>.*?</pre>', dotAll: true), '')
      .replaceAll(RegExp(r'<code[^>]*>.*?</code>', dotAll: true), ''),
);

/// 可視文字列に残ってはいけない生の記号 (AC-26)。
const List<String> rawSymbols = ['**', '`', '|', '---', '[', ']('];

/// [text] を書記素 1 つずつ増やした prefix の列 (1 文字目から全文まで)。
List<String> graphemePrefixes(String text) {
  final chars = text.characters.toList(growable: false);
  final prefixes = <String>[];
  final buffer = StringBuffer();
  for (final char in chars) {
    buffer.write(char);
    prefixes.add(buffer.toString());
  }
  return prefixes;
}

/// [prefixes] を順に前処理 + parse し、「prefix n の可視文字列が prefix n+1 の
/// 可視文字列の先頭部分になっている」性質が破れた箇所を人が読める行にして返す。
///
/// 破れは「表示済みの文字が消えた」「並びが入れ替わった」のどちらでも起きる。
/// 1 箇所ごとに `expect` すると最初の 1 件で止まって残りが見えないので、
/// 全件を集めて返す (呼び出し側が `isEmpty` を主張する)。
List<String> visibleGrowthViolations(List<String> prefixes) {
  final violations = <String>[];
  String? previous;
  for (var i = 0; i < prefixes.length; i++) {
    final visible = visibleTextOf(renderReplyHtml(prefixes[i]));
    if (previous != null && !visible.startsWith(previous)) {
      violations.add(
        'prefix #$i (…${_tail(prefixes[i])}) : '
        '前の可視文字列 (…${_tail(previous)}) が先頭部分でなくなった '
        '→ 今の可視文字列 (…${_tail(visible)})',
      );
    }
    previous = visible;
  }
  return violations;
}

/// [prefixes] を順に前処理 + parse し、可視文字列 (コードの中身は除く) に
/// [rawSymbols] のいずれかが残った箇所を人が読める行にして返す。
///
/// [skipSymbol] が true を返す (prefix, 記号) の組は見逃す
/// (散文の中の `|` のように、届き方によっては現れて当然の記号のため)。
List<String> rawSymbolViolations(
  List<String> prefixes, {
  bool Function(int index, String symbol)? skipSymbol,
}) {
  final violations = <String>[];
  for (var i = 0; i < prefixes.length; i++) {
    final prose = proseTextOf(renderReplyHtml(prefixes[i]));
    for (final symbol in rawSymbols) {
      if (!prose.contains(symbol)) continue;
      if (skipSymbol != null && skipSymbol(i, symbol)) continue;
      violations.add(
        'prefix #$i (…${_tail(prefixes[i])}) : 生の $symbol が残った '
        '→ 可視文字列 (…${_tail(prose)})',
      );
    }
  }
  return violations;
}

/// 長い文字列を報告に乗せるための末尾 40 文字。改行は見やすさのため `⏎` に置く。
String _tail(String text) {
  final oneLine = text.replaceAll('\n', '⏎');
  return oneLine.length <= 40 ? oneLine : oneLine.substring(oneLine.length - 40);
}

String _stripTags(String html) => html.replaceAll(RegExp(r'<[^>]*>'), '');
