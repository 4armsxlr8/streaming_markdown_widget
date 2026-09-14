import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streaming_markdown_widget/src/reveal_ticker.dart';
import 'package:streaming_markdown_widget/src/revealed_markdown.dart';
import 'package:streaming_markdown_widget/src/streaming_reply_controller.dart';

/// 実機の 1 フレーム相当の刻み。
///
/// 描画は「前のフレームの可視文字列との共通接頭辞より後ろ」を今描かれた文字と
/// して出現開始時刻を付けるので、時間は必ずこの刻みで進める。大きな pump を
/// 1 回だけ打つと、間のフレームで描かれるはずだった文字がまとめて「今描かれた
/// 文字」になり、出現の開始時刻がずれる。
const Duration frameInterval = Duration(milliseconds: 16);

/// [RevealedMarkdown] を [RevealTicker] で包んで pump する。
///
/// 時間を進めるのは [pumpFrames]。`pumpAndSettle` は使わない (後続のスライスで
/// 1.6 秒周期の光が回り続ける Widget が乗るため)。
Future<void> pumpRevealedMarkdown(
  WidgetTester tester,
  StreamingReplyController controller, {
  ChunkKind kind = ChunkKind.reply,
  bool formatted = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: RevealTicker(
            controller: controller,
            child: RevealedMarkdown(
              controller: controller,
              kind: kind,
              formatted: formatted,
            ),
          ),
        ),
      ),
    ),
  );
}

/// [total] の時間を [frameInterval] 刻みで進める。
Future<void> pumpFrames(WidgetTester tester, Duration total) async {
  for (var elapsed = Duration.zero; elapsed < total; elapsed += frameInterval) {
    await tester.pump(frameInterval);
  }
}

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
