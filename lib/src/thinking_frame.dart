import 'package:flutter/rendering.dart' show OverflowBoxFit;
import 'package:flutter/widgets.dart';

import 'keys.dart';
import 'reply_theme.dart';
import 'revealed_markdown.dart';
import 'streaming_reply_controller.dart';
import 'thinking_shimmer.dart';

/// 思考の枠: 見出し行と本文。
///
/// 見出し行は、思考が流れている間は光る「考え中…」([ThinkingShimmer])、終わると
/// 「n 秒考えました」。本文は思考の文を
/// [RevealedMarkdown] (`kind: thinking`, 記法は整形しない) で描き、
/// [StreamingReplyController.thinkingFrame] が示す状態 (1 行 / 全部 / 畳み) に
/// 応じて高さを [AnimatedSize] (300ms) で変える。1 行のときは最新の行 (末尾) を
/// 見せ、それより前は上に切り詰める。枠全体 (見出し行 + 本文) のタップで
/// [StreamingReplyController.toggleThinkingFrame] を呼び、1 行 ⇄ 全部
/// (思考中) / 畳み ⇄ 全部 (畳んだ後) を切り替える。
class ThinkingFrame extends StatelessWidget {
  const ThinkingFrame({super.key, required this.controller});

  /// 思考の枠の状態の入り口。
  final StreamingReplyController controller;

  /// 思考が流れている間の見出し行の文言 (三点リーダは U+2026)。
  static const _thinkingTitle = '考え中…';

  @override
  Widget build(BuildContext context) {
    final state = controller.thinkingFrame;
    final isThinking = controller.isThinking;
    final isExpanded = state == ThinkingFrameState.full;

    // thinkingSeconds が未確定の間は作り物の 0 秒を出さず「考え中…」を
    // 出し続ける (確定は controller.tick の到着解決を待つ必要がある。例えば
    // framesPaused 中に complete() が呼ばれると、畳み ([thinkingFrame] が
    // collapsed になる) が先に済んで秒数の確定が後追いになることがある)。
    final thinkingSeconds = controller.thinkingSeconds;
    final title = isThinking || thinkingSeconds == null
        ? _thinkingTitle
        : '$thinkingSeconds 秒考えました';

    // 思考の文 1 行の高さ。OS の文字サイズ設定 (textScaler) を掛ける
    // (掛けないと 100% 以外の設定で 1 行の表示が文字の高さより低く切れる)。
    final oneLineHeight =
        MediaQuery.textScalerOf(context).scale(ReplyTheme.thinkingFontSize) *
        ReplyTheme.thinkingHeight;

    final double maxBodyHeight;
    if (isExpanded) {
      maxBodyHeight = double.infinity;
    } else if (state == ThinkingFrameState.line) {
      maxBodyHeight = oneLineHeight;
    } else {
      maxBodyHeight = 0;
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: controller.toggleThinkingFrame,
      child: Container(
        key: Keys.thinkingFrame,
        padding: const EdgeInsets.only(left: ReplyTheme.thinkingFrameIndent),
        decoration: const BoxDecoration(
          border: Border(
            left: BorderSide(
              color: ReplyTheme.thinkingFrameBorderColor,
              width: ReplyTheme.thinkingFrameBorderWidth,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              key: Keys.thinkingFrameHead,
              behavior: HitTestBehavior.opaque,
              onTap: controller.toggleThinkingFrame,
              child: Row(
                children: [
                  Flexible(
                    child: isThinking
                        ? ThinkingShimmer(
                            textKey: Keys.thinkingFrameTitle,
                            text: title,
                            style: ReplyTheme.thinkingHeadTextStyle,
                          )
                        : Text(
                            title,
                            key: Keys.thinkingFrameTitle,
                            style: ReplyTheme.thinkingHeadTextStyle,
                          ),
                  ),
                ],
              ),
            ),
            AnimatedSize(
              key: Keys.thinkingFrameBody,
              duration: ReplyTheme.thinkingCollapseDuration,
              curve: Curves.fastOutSlowIn,
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                // maxHeight が有限なら本文はその高さで打ち切られ (OverflowBox が
                // bottomLeft で最新の行を下端にそろえ、ClipRect が上をはみ出させ
                // ない)、無限大なら子の自然な高さに合わせるので全文が見える。
                // 中身 (RevealedMarkdown) には minHeight:0/maxHeight:infinity を
                // 渡し、この箱の高さに関わらず常に自然な (複数行ぶんの) 高さで
                // 測らせる — 本文の箱の高さだけを切り詰め、出現の状態を持つ
                // RevealedMarkdown 自体は 1 行/全部/畳みの間で同じ形のまま保つ。
                constraints: BoxConstraints(maxHeight: maxBodyHeight),
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.bottomLeft,
                    minHeight: 0,
                    maxHeight: double.infinity,
                    fit: OverflowBoxFit.deferToChild,
                    child: RevealedMarkdown(
                      key: Keys.thinkingText,
                      controller: controller,
                      kind: ChunkKind.thinking,
                      formatted: false,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
