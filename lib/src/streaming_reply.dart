import 'package:flutter/widgets.dart';

import 'keys.dart';
import 'reply_theme.dart';
import 'reveal_ticker.dart';
import 'revealed_markdown.dart';
import 'streaming_reply_controller.dart';
import 'thinking_frame.dart';
import 'waiting_dots.dart';

/// 返答の Widget: 思考の枠 + 返答の吹き出し。
///
/// [RevealTicker] で包み、[StreamingReplyController] を直に listen して縦に並べる
/// ([ThinkingFrame] の上に返答の吹き出し)。受信前は白い角丸の吹き出しに待機の点
/// 3 つ ([WaitingDots])。思考の塊が届き始めたら吹き出しを消して [ThinkingFrame] を
/// 出し、返答の最初の塊が届いたら (思考の畳みを待たず) 吹き出しを出す。思考の
/// 塊が 1 つも届かなければ枠を出さず、返答の最初の塊でそのまま吹き出しが現れる。
class StreamingReply extends StatelessWidget {
  const StreamingReply({super.key, required this.controller});

  /// 出現状態と思考の枠の状態の入り口。
  final StreamingReplyController controller;

  @override
  Widget build(BuildContext context) {
    return RevealTicker(
      controller: controller,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final showThinkingFrame = controller.thinkingFrame != ThinkingFrameState.none;
          final showBubble = !showThinkingFrame || controller.reply.receivedCount > 0;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showThinkingFrame) ThinkingFrame(controller: controller),
              if (showThinkingFrame && showBubble)
                const SizedBox(height: ReplyTheme.thinkingFrameSpacingBottom),
              if (showBubble) _ReplyBubble(controller: controller),
            ],
          );
        },
      ),
    );
  }
}

/// 返答の吹き出し。受信前は待機の点、返答の最初の塊が届いたら返答の文字。
class _ReplyBubble extends StatelessWidget {
  const _ReplyBubble({required this.controller});

  final StreamingReplyController controller;

  @override
  Widget build(BuildContext context) {
    final hasReply = controller.reply.receivedCount > 0;
    return Container(
      key: Keys.replyBubble,
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: ReplyTheme.replyBubbleMinHeight),
      padding: ReplyTheme.replyBubblePadding,
      decoration: const BoxDecoration(
        color: ReplyTheme.replyBubbleBackground,
        borderRadius: ReplyTheme.replyBubbleBorderRadius,
        boxShadow: [ReplyTheme.replyBubbleShadow],
      ),
      child: hasReply
          ? RevealedMarkdown(key: Keys.replyText, controller: controller, kind: ChunkKind.reply)
          : const WaitingDots(key: Keys.waitingDots),
    );
  }
}
