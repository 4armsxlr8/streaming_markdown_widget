import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streaming_markdown_widget/streaming_markdown_widget.dart';

/// example のテストから出現の様子を読むためのヘルパ。
///
/// パッケージ側の `test/helpers/reveal.dart` と同じ道具立てだが、こちらは
/// 公開入口 (`package:streaming_markdown_widget/streaming_markdown_widget.dart`)
/// だけを import する — example は `src/` を import できない
/// (`implementation_imports` の lint)。`RevealTicker` は公開されていないので
/// `pumpRevealedMarkdown` は持たない (画面ごと pump するテストしか無いため
/// 要らない)。

/// 実機の 1 フレーム相当の刻み。
///
/// 描画は「前のフレームの可視文字列との共通接頭辞より後ろ」を今描かれた文字と
/// して出現開始時刻を付けるので、時間は必ずこの刻みで進める。大きな pump を
/// 1 回だけ打つと、間のフレームで描かれるはずだった文字がまとめて「今描かれた
/// 文字」になり、出現の開始時刻がずれる。
const Duration frameInterval = Duration(milliseconds: 16);

/// [total] の時間を [frameInterval] 刻みで進める。
Future<void> pumpFrames(WidgetTester tester, Duration total) async {
  for (var elapsed = Duration.zero; elapsed < total; elapsed += frameInterval) {
    await tester.pump(frameInterval);
  }
}

/// [condition] が満たされるまで [frameInterval] 刻みで進める。
///
/// [budget] を使い切っても満たされなければ [reason] を添えて失敗する。時間は
/// 供給の Timer と返答の Widget が回す Ticker 越しにしか進まないので、待つ側は
/// `pumpAndSettle` ではなくこれを使う (待機の点と見出し行の光が回り続けるので
/// `pumpAndSettle` は終わらない)。
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  required Duration budget,
  required String reason,
}) async {
  for (
    var elapsed = Duration.zero;
    elapsed < budget;
    elapsed += frameInterval
  ) {
    await tester.pump(frameInterval);
    if (condition()) return;
  }
  fail('${budget.inMilliseconds}ms 進めても条件が満たされなかった: $reason');
}

/// 返答の文字 (返答の区分の [RevealedMarkdown])。
final Finder replyText = find.byWidgetPredicate(
  (widget) => widget is RevealedMarkdown && widget.kind == ChunkKind.reply,
);

/// 思考の文 (思考の区分の [RevealedMarkdown])。
final Finder thinkingText = find.byWidgetPredicate(
  (widget) => widget is RevealedMarkdown && widget.kind == ChunkKind.thinking,
);

/// 描かれた [TextSpan] 1 つ。style は親から受け継いだぶんを合成済み。
class RevealedSpan {
  const RevealedSpan({
    required this.text,
    required this.style,
    required this.recognizer,
  });

  /// この span の文字。
  final String text;

  /// 親から受け継いだ style を合成した、この span に効いている style。
  final TextStyle? style;

  /// この span に付いたタップ処理 (親から受け継いだものを含む)。
  final GestureRecognizer? recognizer;

  /// 不透明度 = style の色のアルファ。
  ///
  /// 色を置いていない span は既定の文字色をそのまま使うので 1 (不透明) とする。
  double get opacity => style?.color?.a ?? 1.0;

  @override
  String toString() => 'RevealedSpan("$text", opacity: $opacity)';
}

/// [within] (既定は [RevealedMarkdown] の中) に描かれた span を並び順に集める。
List<RevealedSpan> revealedSpans(WidgetTester tester, {Finder? within}) {
  final richTexts = find.descendant(
    of: within ?? find.byType(RevealedMarkdown),
    matching: find.byType(RichText),
  );
  final spans = <RevealedSpan>[];
  for (final richText in tester.widgetList<RichText>(richTexts)) {
    _collectSpans(richText.text, null, null, spans);
  }
  return spans;
}

/// 描かれている可視文字列 (span の文字を並び順につないだもの)。
String visibleText(WidgetTester tester, {Finder? within}) =>
    revealedSpans(tester, within: within).map((span) => span.text).join();

void _collectSpans(
  InlineSpan span,
  TextStyle? inheritedStyle,
  GestureRecognizer? inheritedRecognizer,
  List<RevealedSpan> out,
) {
  if (span is! TextSpan) return;
  final style = inheritedStyle == null
      ? span.style
      : (span.style == null
            ? inheritedStyle
            : inheritedStyle.merge(span.style));
  final recognizer = span.recognizer ?? inheritedRecognizer;
  final text = span.text;
  if (text != null && text.isNotEmpty) {
    out.add(RevealedSpan(text: text, style: style, recognizer: recognizer));
  }
  for (final child in span.children ?? const <InlineSpan>[]) {
    _collectSpans(child, style, recognizer, out);
  }
}
