import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart';
import 'package:streaming_markdown_widget/src/partial_markdown.dart';

/// 書きかけの記法を閉じる前処理と、その結果の parse のテスト
/// (AC-7, AC-8, AC-9, AC-10, AC-12)。
///
/// spec の受け入れ基準では seam が「返答の Widget」だが、これらの AC が言う
/// 「`**` の文字は無い」「生の `|` `---` は無い」は、パーサーに渡す前に
/// 書きかけの記法を閉じる前処理が決める。そこでここでは前処理を通した parse の
/// 結果 (AST) を主張し、AST から Widget への描画 (TextSpan・不透明度) は
/// 後続のスライスの widget test に置く。
///
/// 前処理が返す文字列そのものは実装の自由度を残すため直接は主張せず、
/// [parseReplyMarkdown] の AST を [HtmlRenderer] で HTML にして比べる。
/// 「生の記号が無い」ことは HTML に `**` `|` `[` が含まれないことで主張する。
/// Widget も Ticker も要らない純 Dart のテストとして書く。
void main() {
  /// 出現位置までの Markdown を前処理 + parse し、HTML 文字列にする。
  ///
  /// ブロックの間に改行が入るので前後の空白は落とす。
  String renderHtml(String partial) =>
      HtmlRenderer().render(parseReplyMarkdown(partial)).trim();

  /// 表の見出し行 (3 列)。
  const tableHeaderLine = '| 方法 | 効果 | 手間 |';

  /// 見出し行と同じ 3 列そろった区切り行。
  const tableDelimiterLine = '|---|---|---|';

  /// 閉じた本体 1 行 (行末の `|` とその後の改行まで届いている)。
  const tableClosedBodyLine = '| a | b | c |';

  /// 書きかけの本体 2 行目 (行末の `|` がまだ届いていない)。
  const tablePartialBodyLine = '| d | e';

  /// 見出し行だけの表 (`<tbody>` に行が無い)。
  const tableWithHeaderOnlyHtml = '''<table>
<thead>
<tr>
<th>方法</th>
<th>効果</th>
<th>手間</th>
</tr>
</thead>
</table>''';

  /// 見出し + 閉じた本体 1 行の表。
  const tableWithOneRowHtml = '''<table>
<thead>
<tr>
<th>方法</th>
<th>効果</th>
<th>手間</th>
</tr>
</thead>
<tbody>
<tr>
<td>a</td>
<td>b</td>
<td>c</td>
</tr>
</tbody>
</table>''';

  test('AC-7 **画面 まで届くと、閉じる記号が来る前から「画面」が太字になり、生の ** は出ない', () {
    expect(
      renderHtml('**画面'),
      '<p><strong>画面</strong></p>',
      reason: '閉じていない ** を前処理が閉じる (パーサーは素の文字として残すので前処理の責務)',
    );
  });

  test('AC-7 **画面** まで届くと、「画面」が太字のまま変わらない', () {
    expect(
      renderHtml('**画面**'),
      '<p><strong>画面</strong></p>',
      reason: '閉じた ** は前処理が触らず、書きかけの段階と同じ描かれ方になる',
    );
  });

  test('AC-8 ```dart と 1 行目まで届くと、閉じていなくてもコードブロックになり、生の ``` は出ない', () {
    final html = renderHtml('```dart\nListView.builder(');

    expect(
      html,
      contains('<pre><code class="language-dart">'),
      reason: '閉じていないフェンスはそのまま渡し、パーサーが末尾までコードブロックにする',
    );
    expect(html, contains('ListView.builder('), reason: '1 行目の中身がコードブロックに入る');
    expect(html, isNot(contains('`')), reason: 'フェンスの記号が文字として残らない');
  });

  test('AC-9 [公式ド まで届くと、ラベルだけの素の文字になり、生の [ は出ない', () {
    expect(
      renderHtml('[公式ド'),
      '<p>公式ド</p>',
      reason: '書きかけのリンクはラベルだけの素の文字にする (パーサーが残す [ を前処理が落とす)',
    );
  });

  test('AC-9 [公式ドキュメント](https://do まで届くと、ラベルだけの素の文字になり、生の [ ]( は出ない', () {
    expect(
      renderHtml('[公式ドキュメント](https://do'),
      '<p>公式ドキュメント</p>',
      reason: '書きかけの URL は見えず、ラベルだけが素の文字として残る',
    );
  });

  test('AC-9 閉じ括弧まで届くとリンクになる', () {
    expect(
      renderHtml('[公式ドキュメント](https://docs.flutter.dev/perf/best-practices)'),
      '<p><a href="https://docs.flutter.dev/perf/best-practices">公式ドキュメント</a></p>',
      reason: '閉じたリンクは前処理が触らず、パーサーがリンクにする',
    );
  });

  test('AC-10 表の見出し行だけ届いた段階では表が無く、生の | も出ない', () {
    expect(
      renderHtml(tableHeaderLine),
      isEmpty,
      reason: '区切り行が同じ列数そろって届くまでは見出し行ごと落とす '
          '(そのまま渡すと 7.3.1 は生の | を含む段落にする)',
    );
  });

  test('AC-10 区切り行が同じ列数そろうと、見出し行だけの表になる', () {
    expect(
      renderHtml('$tableHeaderLine\n$tableDelimiterLine'),
      tableWithHeaderOnlyHtml,
      reason: '見出し行が表として現れ、本体の行 (<tbody>) はまだ無い',
    );
  });

  test('AC-10 本体 1 行が閉じると、見出し + 1 行の表になる', () {
    expect(
      renderHtml('$tableHeaderLine\n$tableDelimiterLine\n$tableClosedBodyLine\n'),
      tableWithOneRowHtml,
      reason: '行末の | とその後の改行が届いて閉じた本体行は残す',
    );
  });

  test('AC-10 本体 2 行目が書きかけの間は、見出し + 1 行のまま増えない', () {
    expect(
      renderHtml(
        '$tableHeaderLine\n$tableDelimiterLine\n$tableClosedBodyLine\n$tablePartialBodyLine',
      ),
      tableWithOneRowHtml,
      reason: '閉じていない末尾の行は落とす (そのまま渡すと 7.3.1 は d と e を空セルで埋めた行にする)。'
          'd と e は現れず、行数も増えない',
    );
  });

  test('AC-12 塊の境界で ** が割れて * だけ届いた段階では、例外にならず生の * も出ない', () {
    // 例外が飛べばこの行で落ちる。
    final html = renderHtml('*');

    expect(
      html,
      isEmpty,
      reason: '中身がまだ 1 文字も届いていない末尾の開き記号は閉じるのではなく落とす '
          '(そのまま渡すと 7.3.1 は中身の無い箇条書きの点にする)',
    );
  });

  test('AC-12 **画 まで届くと、1 文字でも太字になる', () {
    expect(
      renderHtml('**画'),
      '<p><strong>画</strong></p>',
      reason: '中身が 1 文字届いた時点で開き記号を閉じる',
    );
  });
}
