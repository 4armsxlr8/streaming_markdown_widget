import 'package:flutter_test/flutter_test.dart';

import 'fixtures/sample_reply.dart';
import 'helpers/markdown_html.dart';

/// 書きかけの記法を閉じる前処理の回帰テスト (AC-23, AC-24, AC-25, AC-26, AC-27)。
///
/// `partial_markdown_test.dart` (AC-7〜AC-12) が正常系の代表を 1 点ずつ見るのに
/// 対し、ここは「届き方を 1 文字ずつ全部たどっても崩れない」ことを機械的に
/// 確かめる。主張は 3 つだけ:
///
/// 1. どの prefix でも可視文字列に生の記号 ([rawSymbols]) が残らない
///    (コードブロック `<pre>` とコードスパン `<code>` の中身は除く)
/// 2. どの prefix でも、可視文字列が次の prefix の可視文字列の先頭部分に
///    なっている (= 表示済みの文字が消えたり並びが入れ替わったりしない)
/// 3. 受信完了 (`complete: true`) の結果は、同じ文字列を前処理なしで素の
///    `Document` に通した結果と一致する (前処理が足した記号・落とした文字が
///    残らない)
///
/// seam は spec では「返答の Widget」だが、これらが決まるのはパーサーに渡す前の
/// 前処理なので、`partial_markdown_test.dart` と同じく前処理を通した parse の
/// 結果 (AST を [renderReplyHtml] で HTML にしたもの) を主張する。Widget も
/// Ticker も要らない純 Dart。
void main() {
  // ── AC-23 / AC-24 / AC-25 のフィクスチャ ──

  /// 開き記号の直後に日本語の句読点が来る、書きかけの強調。
  const openQuoteEmphasisPartial = 'これは **「重要';

  /// 同じ強調が閉じたところまで届いた形。
  const openQuoteEmphasisClosed = 'これは **「重要」** です';

  /// 複数行にまたがる強調 (AC-24 / AC-26 の「複数行の強調」)。
  const multiLineEmphasis = '本文は **とても\n重要** です';

  /// 表の見出し行 (3 列) の次の行に `|` 1 文字だけ届いた形。
  const tableHeaderThenPipe = '| 方法 | 効果 | 手間 |\n|';

  // ── AC-26 のフィクスチャ ──

  /// 括弧入り URL のリンク。
  const parenthesizedUrlLink =
      '[Foo](https://ja.wikipedia.org/wiki/Foo_(bar)) を参照';

  /// 散文の中の `|` (表ではない `|` が 1 つある行と、その次の行)。
  const pipeInProse = '列は a | b です\n次の行';

  /// [pipeInProse] の `\n` が初めて届く prefix の番号 (0 始まり)。
  ///
  /// 列(0) は(1) 空白(2) a(3) 空白(4) |(5) 空白(6) b(7) 空白(8) で(9) す(10) ⏎(11)。
  const pipeInProseNewlineIndex = 11;

  /// [pipeInProse] の改行が届く直前まで描かれているべき可視文字列。
  ///
  /// `|` が描かれないこと (AC-26) と「可視文字列が次の prefix の先頭部分に
  /// なっている」ことの両方を満たす形はこれしかない — `|` の前までを描いたまま
  /// `|` から先を保留する。`|` だけ落として `列はabです` を描くと、改行が
  /// 届いて `列はa|bです` になった瞬間に先頭部分でなくなる。行ごと落として
  /// 空にすると、その前の prefix で描いていた `列はa` が消える。
  const pipeInProseBeforeNewline = '列はa';

  /// 改行が届いた時点で一斉に現れる、`|` を含む行の可視文字列。
  const pipeInProseAtNewline = '列はa|bです';

  /// コードスパンの中の画像記法と書きかけのリンク。
  const codeSpanFixture = 'コードは `![alt](url)` と `[x](y` です';

  /// 表とその後に続く段落。
  const tableThenParagraph = '''
| 方法 | 効果 |
|---|---|
| a | b |

表の後の段落です。''';

  // ── AC-23 ──

  test('AC-23 これは **「重要 まで届くと、開き記号の直後の 「 から太字になり、生の ** は出ない', () {
    expect(
      renderReplyHtml(openQuoteEmphasisPartial),
      '<p>これは <strong>「重要</strong></p>',
      reason:
          '開き記号の前は空白なので ** は開き記号として数える。'
          '直後が日本語の句読点 (「) でも太字になり、** の文字は残らない',
    );
  });

  test('AC-23 これは **「重要」** です まで届くと、「重要」が太字のまま変わらない', () {
    expect(
      renderReplyHtml(openQuoteEmphasisClosed),
      '<p>これは <strong>「重要」</strong> です</p>',
      reason: '閉じた ** は前処理が触らず、書きかけの段階と同じ描かれ方になる',
    );
  });

  // ── AC-24 ──

  test(
    'AC-24 複数行にまたがる強調を 1 文字ずつ届けると、どの段階でも生の ** は無く、可視文字列は次の段階の先頭部分になっている',
    () {
      final prefixes = graphemePrefixes(multiLineEmphasis);

      expect(
        [
          ...rawSymbolViolations(prefixes),
          ...visibleGrowthViolations(prefixes),
        ],
        isEmpty,
        reason:
            '改行をまたぐ書きかけの強調でも ** を閉じ、表示済みの文字が消えたり '
            '再出現したりしない (全 ${prefixes.length} prefix を検査。2 つの検査を '
            '1 つの expect にまとめるのは、片方で止まると残りの違反が報告に '
            '出ないため)',
      );
    },
  );

  // ── AC-25 ──

  test('AC-25 表の見出し行の次の行に | 1 文字だけ届いた段階では、表も生の | も「方法」も描かれない', () {
    expect(
      renderReplyHtml(tableHeaderThenPipe),
      isEmpty,
      reason:
          '区切り行が同じ列数そろうまでは見出し行ごと保留する。'
          '次の行が区切り行の書きかけ (| 1 文字) の間も、見出し行を表にしてはいけない',
    );
  });

  // ── AC-26 (全 prefix の機械検査) ──

  // 機械検査にかける同梱の返答は 2 つ — 今の example のサンプル (英語) と、
  // かつての example のサンプル (日本語)。後者は example と同期しない固定の
  // フィクスチャで、3 列の表・複数段落を含むのはこちらだけなので両方を回す。
  const scannedReplies = <String, String>{
    '英語のサンプル': sampleReplyEnglish,
    'かつての日本語のサンプル': sampleReply,
  };

  for (final scanned in scannedReplies.entries) {
    test('AC-26 同梱の返答 (${scanned.key}) を 1 文字ずつ全 prefix で届けても、生の記号が残らない', () {
      final prefixes = graphemePrefixes(scanned.value);

      expect(
        rawSymbolViolations(prefixes),
        isEmpty,
        reason:
            '全 ${prefixes.length} prefix の可視文字列 '
            '(コードブロック・コードスパンの中身は除く) に $rawSymbols は残らない',
      );
    });

    test(
      'AC-26 同梱の返答 (${scanned.key}) を 1 文字ずつ全 prefix で届けても、可視文字列は次の prefix の先頭部分に'
      'なっている',
      () {
        expect(
          visibleGrowthViolations(graphemePrefixes(scanned.value)),
          isEmpty,
          reason: '表示済みの文字が消えたり並びが入れ替わったりしない',
        );
      },
    );
  }

  test(
    'AC-26 日本語の句読点を含む強調を 1 文字ずつ全 prefix で届けても、生の記号が残らず可視文字列は次の prefix の先頭部分になっている',
    () {
      final prefixes = graphemePrefixes(openQuoteEmphasisClosed);

      expect(
        [
          ...rawSymbolViolations(prefixes),
          ...visibleGrowthViolations(prefixes),
        ],
        isEmpty,
        reason:
            '開き記号の直後が日本語の句読点でも、どの段階でも記号は見せず '
            '表示済みの文字も消さない',
      );
    },
  );

  test(
    'AC-26 複数行の強調を 1 文字ずつ全 prefix で届けても、生の記号が残らず可視文字列は次の prefix の先頭部分になっている',
    () {
      final prefixes = graphemePrefixes(multiLineEmphasis);

      expect(
        [
          ...rawSymbolViolations(prefixes),
          ...visibleGrowthViolations(prefixes),
        ],
        isEmpty,
        reason: '改行をまたぐ強調でも、どの段階でも記号は見せず表示済みの文字も消さない',
      );
    },
  );

  test(
    'AC-26 括弧入り URL のリンクを 1 文字ずつ全 prefix で届けても、生の記号が残らず可視文字列は次の prefix の先頭部分になっている',
    () {
      final prefixes = graphemePrefixes(parenthesizedUrlLink);

      expect(
        [
          ...rawSymbolViolations(prefixes),
          ...visibleGrowthViolations(prefixes),
        ],
        isEmpty,
        reason:
            'URL の中の ( ) で書きかけの判定が崩れても、生の [ ]( を見せず '
            'ラベルの表示も消さない',
      );
    },
  );

  test(
    'AC-26 コードスパンの中の画像記法と書きかけのリンクを 1 文字ずつ全 prefix で届けても、生の記号が残らず可視文字列は次の prefix の先頭部分になっている',
    () {
      final prefixes = graphemePrefixes(codeSpanFixture);

      expect(
        [
          ...rawSymbolViolations(prefixes),
          ...visibleGrowthViolations(prefixes),
        ],
        isEmpty,
        reason:
            'コードスパンの中身は記号の検査から除くが、可視文字としては '
            '消えたり増えたりしてはいけない (前処理が足したエスケープの \\ も含む)',
      );
    },
  );

  test(
    'AC-26 表の後に続く段落を 1 文字ずつ全 prefix で届けても、生の記号が残らず可視文字列は次の prefix の先頭部分になっている',
    () {
      final prefixes = graphemePrefixes(tableThenParagraph);

      expect(
        [
          ...rawSymbolViolations(prefixes),
          ...visibleGrowthViolations(prefixes),
        ],
        isEmpty,
        reason:
            '表が閉じた後の段落を保留したり、区切り行の --- を見せたり、'
            '一度描いた見出し行を消したりしない',
      );
    },
  );

  test('AC-26 散文の中の | は、行末の改行が届くまで描かれず、その間も可視文字列は次の prefix の先頭部分になっている', () {
    final prefixes = graphemePrefixes(pipeInProse);

    expect(
      [
        ...rawSymbolViolations(
          prefixes,
          // 改行が届いた後の | は描かれて当然なので見逃す。
          skipSymbol: (index, symbol) =>
              symbol == '|' && index >= pipeInProseNewlineIndex,
        ),
        ...visibleGrowthViolations(prefixes),
      ],
      isEmpty,
      reason:
          '改行が届くまでは表の見出し行の可能性が残るので | を見せず、'
          'かつ | が届いた瞬間に、それまで描いていた「列は a」が消えてもいけない',
    );
  });

  test('AC-26 散文の中の | を含む行は、行末の改行が届いた時点で一斉に現れる', () {
    final prefixes = graphemePrefixes(pipeInProse);

    expect(
      [
        visibleTextOf(renderReplyHtml(prefixes[pipeInProseNewlineIndex - 1])),
        visibleTextOf(renderReplyHtml(prefixes[pipeInProseNewlineIndex])),
      ],
      [pipeInProseBeforeNewline, pipeInProseAtNewline],
      reason:
          '改行が届く直前は | の前までが描かれ、改行が届いて表でないと分かった時点で '
          '| を含む行が一斉に現れる (2 つの段階を 1 つの expect で見て、'
          'どちらが崩れたか報告に両方出す)',
    );
  });

  // ── AC-27 (受信完了は前処理なしと一致する) ──

  for (final completeFixture in const <String>[
    '**a',
    '`b',
    '[c](d',
    '| e |',
    'x**2 の計算\n\n次',
    '`![alt](url)`',
    '計算 [5*8](https://example.com) の結果',
    'value_ です',
  ]) {
    final label = completeFixture.replaceAll('\n', '⏎');
    test(
      'AC-27 $label が complete: true で parse されると、前処理なしの素の Document と同じ結果になる',
      () {
        expect(
          renderReplyHtml(completeFixture, complete: true),
          renderRawHtml(completeFixture),
          reason:
              '受信完了後は書きかけの記法を閉じも落としもしない。'
              '前処理が足した記号・落とした文字が残ってはいけない',
        );
      },
    );
  }
}
