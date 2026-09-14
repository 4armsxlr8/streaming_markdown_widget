import 'package:flutter/rendering.dart' show OverflowBoxFit;
import 'package:flutter/widgets.dart';

import 'keys.dart';
import 'revealed_markdown.dart';
import 'streaming_reply_controller.dart';
import 'streaming_reply_style.dart';
import 'thinking_shimmer.dart';

/// The thinking frame: a headline row and a body.
///
/// While the thinking is still arriving, the headline row is a shimmering
/// "Thinking…" ([ThinkingShimmer]); once it ends, "Thought for n seconds". The
/// body draws the thinking text with [RevealedMarkdown] (`kind: thinking`,
/// notation not formatted) and changes its height with [AnimatedSize]
/// (`controller.style.thinkingCollapseDuration`, not the widget-side
/// [style]'s — see the time-fields split in the [StreamingReplyStyle] class
/// doc) according to the state
/// [StreamingReplyController.thinkingFrame] reports (one line / full /
/// collapsed). In the one-line state it shows the latest
/// line (the last one) and cuts off everything before it at the top. A tap
/// anywhere on the frame (headline row + body) calls
/// [StreamingReplyController.toggleThinkingFrame], switching one line ⇄ full
/// (while thinking) / collapsed ⇄ full (after it has been collapsed).
class ThinkingFrame extends StatelessWidget {
  const ThinkingFrame({
    super.key,
    required this.controller,
    this.style,
    this.thinkingTitle = '…',
    this.thoughtForSeconds,
  });

  /// Entry point for the thinking frame's state.
  final StreamingReplyController controller;

  /// Look-and-feel values (the defaults when omitted). Passed down through an
  /// InheritedWidget ([StreamingReplyStyleScope]).
  final StreamingReplyStyle? style;

  /// Headline shown while thinking is streaming, and still shown afterward
  /// if [thoughtForSeconds] is null.
  final String thinkingTitle;

  /// Builds the headline shown once thinking has finished, given the
  /// measured (or overridden) [StreamingReplyController.thinkingSeconds].
  /// Null keeps showing [thinkingTitle] even after thinking ends.
  final String Function(int seconds)? thoughtForSeconds;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => _buildFrame(context),
  );

  /// Assembles one frame from [controller]'s state (called from the
  /// [AnimatedBuilder]'s builder — so that even placed on its own it rebuilds
  /// on a change in [controller], such as the thinking frame's state or the
  /// second count being settled. Harmless if it ends up doubled with the outer
  /// `AnimatedBuilder` on the composed Widget ([StreamingReply]) side).
  Widget _buildFrame(BuildContext context) {
    final effectiveStyle = style ?? StreamingReplyStyleScope.of(context);
    final ambient = DefaultTextStyle.of(context).style;
    final resolvedThinkingHeadTextStyle = effectiveStyle
        .resolveThinkingHeadTextStyle(ambient);
    final state = controller.thinkingFrame;
    final isThinking = controller.isThinking;
    final isExpanded = state == ThinkingFrameState.full;

    // While thinkingSeconds is not settled yet, keep showing "Thinking…"
    // instead of putting out a made-up 0 seconds (settling it has to wait for
    // controller.tick to resolve the arrivals. If complete() is called while
    // framesPaused, for instance, the collapse ([thinkingFrame] becoming
    // collapsed) can finish first and the second count only be settled
    // afterwards).
    final thinkingSeconds = controller.thinkingSeconds;
    final thoughtForSeconds = this.thoughtForSeconds;
    final title =
        isThinking || thinkingSeconds == null || thoughtForSeconds == null
        ? thinkingTitle
        : thoughtForSeconds(thinkingSeconds);

    // The height of one line of thinking text. Multiplied by the OS text size
    // setting (textScaler) — without that, at any setting other than 100% the
    // one-line display is cut shorter than the height of the characters.
    final resolvedThinkingTextStyle = effectiveStyle.resolveThinkingTextStyle(
      ambient,
    );
    final oneLineHeight =
        MediaQuery.textScalerOf(
          context,
        ).scale(resolvedThinkingTextStyle.fontSize ?? 14) *
        (resolvedThinkingTextStyle.height ?? 1.0);

    final double maxBodyHeight;
    if (isExpanded) {
      maxBodyHeight = double.infinity;
    } else if (state == ThinkingFrameState.line) {
      maxBodyHeight = oneLineHeight;
    } else {
      maxBodyHeight = 0;
    }

    return StreamingReplyStyleScope(
      style: effectiveStyle,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: controller.toggleThinkingFrame,
        // The screen-reader button is put up on the headline row
        // (Keys.thinkingFrameHead) only — the whole frame carries the same
        // onTap, so without excluding it here there would be two tappable
        // targets side by side (VoiceOver focus would land on it twice).
        excludeFromSemantics: true,
        child: Container(
          key: Keys.thinkingFrame,
          padding: EdgeInsets.only(left: effectiveStyle.thinkingFrameIndent),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: effectiveStyle.thinkingFrameBorderColor,
                width: effectiveStyle.thinkingFrameBorderWidth,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Make this operable as a button from the screen reader (tap to
              // expand or collapse). The GestureDetector's own semantics are
              // excluded (excludeFromSemantics) and this Semantics is put up
              // with button:true instead — without the exclusion, the
              // GestureDetector's own tap node (which has no isButton) is
              // found first and it never becomes a button.
              Semantics(
                button: true,
                onTap: controller.toggleThinkingFrame,
                child: GestureDetector(
                  key: Keys.thinkingFrameHead,
                  behavior: HitTestBehavior.opaque,
                  excludeFromSemantics: true,
                  onTap: controller.toggleThinkingFrame,
                  child: Row(
                    children: [
                      Flexible(
                        child: isThinking
                            ? ThinkingShimmer(
                                textKey: Keys.thinkingFrameTitle,
                                text: title,
                                style: resolvedThinkingHeadTextStyle,
                              )
                            : Text(
                                title,
                                key: Keys.thinkingFrameTitle,
                                style: resolvedThinkingHeadTextStyle,
                              ),
                      ),
                    ],
                  ),
                ),
              ),
              AnimatedSize(
                key: Keys.thinkingFrameBody,
                // The controller's own style, not effectiveStyle — see the
                // class doc and StreamingReplyController.style.
                duration: controller.style.thinkingCollapseDuration,
                curve: Curves.fastOutSlowIn,
                alignment: Alignment.topLeft,
                child: ConstrainedBox(
                  // A finite maxHeight cuts the body off at that height (the
                  // OverflowBox aligns the latest line to the bottom edge
                  // with bottomLeft, and the ClipRect keeps the top from
                  // spilling out); an infinite one follows the child's
                  // natural height, so the whole text is visible. The
                  // contents (RevealedMarkdown) are handed
                  // minHeight:0/maxHeight:infinity so that they are always
                  // measured at their natural (multi-line) height regardless
                  // of this box's height — only the height of the body's box
                  // is cut down, while RevealedMarkdown itself, which holds
                  // the reveal state, keeps the same shape across one
                  // line/full/collapsed.
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
      ),
    );
  }
}
