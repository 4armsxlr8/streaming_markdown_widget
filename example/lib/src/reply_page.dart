import 'dart:math';

import 'package:flutter/material.dart';
import 'package:streaming_markdown_widget/streaming_markdown_widget.dart';

import 'fake_reply_source.dart';
import 'gemini_reply_source.dart';
import 'keys.dart';
import 'sample_reply.dart';

/// The page background color.
const _pageBackground = Color(0xFFF1F2F4);

/// Padding of the reply's vertical scroll area (`.demo3-body`'s
/// `padding: 10px 16px 24px`).
const _pagePadding = EdgeInsets.fromLTRB(16, 10, 16, 24);

/// Gap between the reply and the replay button (`.demo3-retry-btn`'s
/// `margin: 14px auto 0`).
const _actionsSpacingTop = 14.0;

/// Top switch pill (`.demo3-topbar` / `.demo3-segment`).
const _topbarPadding = EdgeInsets.fromLTRB(16, 14, 16, 4);
const _segmentBackground = Color(0xFFE2E4E9);
const _segmentBorderRadius = 999.0;
const _segmentPadding = EdgeInsets.all(2);

/// Switch button look (`.demo3-segment-btn` / `.demo3-segment-btn--active`).
const _segmentButtonPadding = EdgeInsets.symmetric(horizontal: 12, vertical: 5);
const _segmentFontSize = 12.0;
const _segmentTextColor = Color(0xFF5C626C);
const _segmentActiveBackground = Color(0xFFFFFFFF);
const _segmentActiveTextColor = Color(0xFF1D2026);
const _segmentActiveShadow = BoxShadow(
  color: Color(0x1F000000), // rgba(0, 0, 0, .12)
  offset: Offset(0, 1),
  blurRadius: 2,
);

/// No-key reason line shown under the switch. The mock never draws this
/// state, so this reuses the thinking-line token (`.demo3-thinking-line`:
/// font-size 12, color #9099A6) as the closest existing informational-text
/// style (deviation — no direct mock reference).
const _noKeyReasonPadding = EdgeInsets.fromLTRB(16, 0, 16, 8);
const _noKeyReasonTextColor = Color(0xFF9099A6);
const _noKeyReasonFontSize = 12.0;

/// Style shared by the two pale lines [_ReplyFlow] adds in place of the
/// mock — the not-sent-yet guidance line and the sent-question line. Reuses
/// [_NoKeyReason]'s tone (deviation — no mock reference for either line).
const _paleLineTextStyle = TextStyle(
  color: _noKeyReasonTextColor,
  fontSize: _noKeyReasonFontSize,
);

/// Gap between the sent-question line and the reply below it (no mock
/// reference — same kind of deviation as [_errorSpacingTop]).
const _questionLineSpacingBottom = 6.0;

/// Bottom-fixed input bar (`.demo3-inputbar`).
const _inputBarPadding = EdgeInsets.symmetric(horizontal: 14, vertical: 10);
const _inputBarBackground = Color(0xFFFFFFFF);
const _inputBarBorderColor = Color(0xFFE3E5E9);
const _inputBarBorderWidth = 1.0;
const _inputBarGap = 8.0;

/// Question field (`.demo3-input` / `.demo3-input--placeholder`). Background
/// reuses [_pageBackground] (both are `#F1F2F4` in the mock).
const _questionFieldPadding = EdgeInsets.symmetric(horizontal: 14, vertical: 9);
const _questionFieldBorderRadius = 999.0;
const _questionFieldFontSize = 13.5;
const _questionFieldTextColor = Color(0xFF1D2026);
const _questionFieldHintColor = Color(0xFF9099A6);

/// Send button (`.demo3-send-btn` / `.demo3-send-btn--active`).
const _sendButtonSize = 34.0;
const _sendButtonInactiveBackground = Color(0xFFDDE0E6);
const _sendButtonActiveBackground = Color(0xFF3A3F47);
const _sendButtonIconColor = Color(0xFFFFFFFF);
const _sendButtonIconSize = 14.0;

/// Error line under the reply. Not drawn in the mock (deviation — no direct
/// reference); a plain red note, distinct from the gray informational tone
/// used elsewhere, so it still reads as an error.
const _errorSpacingTop = 8.0;
const _errorTextColor = Color(0xFFB3261E);
const _errorFontSize = 12.0;
const _errorTextStyle = TextStyle(
  color: _errorTextColor,
  fontSize: _errorFontSize,
);

const _replayButtonBackground = Color(0xFFFFFFFF);

/// Border and text color of `.demo3-retry-btn`.
const _replayButtonBorderColor = Color(0xFFDDE0E6);
const _replayButtonBorderWidth = 1.0;

/// The button's corner radius (`border-radius: 999px` = a fully rounded
/// pill shape).
const _replayButtonBorderRadius = 999.0;

const _replayButtonTextColor = Color(0xFF3A3F47);
const _replayButtonFontSize = 12.5;

const _replayButtonPadding = EdgeInsets.symmetric(horizontal: 18, vertical: 8);

const _replayButtonTextStyle = TextStyle(
  color: _replayButtonTextColor,
  fontSize: _replayButtonFontSize,
  fontWeight: FontWeight.w600,
);

/// The example app's screen: the fake / real (Gemini) switch at the top, the
/// reply (with no bubble), and an input field plus send button pinned to the
/// bottom edge of the screen.
///
/// The fake supply ([FakeReplySource]) starts running automatically the
/// moment the app launches. If [apiKey] is empty, the real (Gemini) supply
/// cannot be selected and a one-line reason is shown under the switch. If a
/// key is present it can be selected, and the question in the input field is
/// sent once to [realReplyStream] (or, when it is omitted,
/// [geminiReplyStream]) and the reply's Stream is run through
/// [StreamingReplyController.attach]. Errors are received through [attach]'s
/// `onError` and shown as one line under the reply. Every send advances the
/// generation ([_generation]) and rebuilds [_ReplyFlow] by Key, so even while
/// receiving, the old supply and Controller are disposed in that build phase
/// (for both the real and the fake supply). Replay re-sends the previous
/// question for the real supply, and re-runs the fake supply for the fake
/// one. No history is kept: sending clears the input field and shows the
/// question as one pale line above the reply, and while a real reply is
/// still being received both buttons are disabled instead of re-sending.
///
/// So that a vertically long reply can still be read, only the reply area
/// scrolls vertically. The package itself does not auto-follow the tail;
/// this screen jumps the scroll position back to the top each time a new
/// reply starts flowing (send or replay), same as opening any fresh reply.
class ReplyPage extends StatefulWidget {
  const ReplyPage({
    super.key,
    this.thinking = sampleThinking,
    this.reply = sampleReply,
    this.random,
    this.apiKey = '',
    this.model = 'gemini-3.8-flash',
    this.realReplyStream,
  });

  /// The thinking text to supply (fake supply only).
  final String thinking;

  /// The reply to supply (fake supply only).
  final String reply;

  /// The supply's [Random] (when omitted, this is left to
  /// [FakeReplySource]'s default; fake supply only). Pass it when a manual
  /// check or a test needs the supply's chunk boundaries and intervals to be
  /// fixed.
  final Random? random;

  /// Gemini API key. Empty disables the real supply (spec: build-time only,
  /// via `--dart-define`; never stored on device, never shown on screen).
  final String apiKey;

  /// Gemini model name, used when [realReplyStream] is not overridden.
  final String model;

  /// Real supply factory (question → Stream of [Chunk]). Defaults to
  /// [geminiReplyStream] with [apiKey] / [model]; tests substitute a fake
  /// [Stream] here instead of calling the real Gemini API.
  final Stream<Chunk> Function(String question)? realReplyStream;

  @override
  State<ReplyPage> createState() => _ReplyPageState();
}

class _ReplyPageState extends State<ReplyPage> {
  /// The generation, incremented on every replay and every send. It is used
  /// as [_ReplyFlow]'s Key — when the Key changes, Flutter discards the old
  /// Element entirely before building a new one ([_ReplyFlowState.dispose],
  /// then [_ReplyFlowState.initState]), so the old supply and the old
  /// Controller are disposed together as a unit rather than swapped field by
  /// field (the real supply's [attach] subscription is released along the
  /// same path, since [StreamingReplyController.dispose] cancels it) — a tick
  /// landing in the gap before that dispose runs still reaches the old
  /// Controller, which is harmless either way: while still mounted it is
  /// simply still alive, and a call arriving after [dispose] is ignored
  /// rather than thrown (see [StreamingReplyController.dispose]). The Key is
  /// still what makes the supply and the Controller change together.
  int _generation = 0;

  /// The vertical scroll position of the whole page. Jumped back to the top
  /// each time a new reply starts flowing ([_start]).
  final ScrollController _scrollController = ScrollController();

  /// The text in the input field at the bottom edge.
  final TextEditingController _questionController = TextEditingController();

  /// The selected supply: true = real (Gemini), false = fake. It always
  /// starts on the fake supply, even when [apiKey] is empty.
  bool _useRealSupply = false;

  /// The question last sent to the real supply (used when replay re-sends
  /// it).
  String? _lastQuestion;

  /// The real supply for the current generation (null while the fake supply
  /// is selected, or if nothing has been sent yet).
  Stream<Chunk>? _realStream;

  /// True while a real-supply request is in flight. Set by [_start] the
  /// moment a real Stream is created; cleared once [_ReplyFlow] reports,
  /// through [_setReceiving], that its Controller has completed (or
  /// errored — [StreamingReplyController.attach] completes on error too).
  /// The fake supply never sets this.
  bool _receiving = false;

  bool get _hasApiKey => widget.apiKey.isNotEmpty;

  Stream<Chunk> _startRealStream(String question) =>
      widget.realReplyStream?.call(question) ??
      geminiReplyStream(question, apiKey: widget.apiKey, model: widget.model);

  /// A tap on the switch. Without a key, it does not switch to the real
  /// supply. Advances the generation so [_ReplyFlow] is rebuilt by Key — the
  /// switch would otherwise not reach a flow that is already running (merely
  /// changing [_useRealSupply] rebuilds [_ReplyFlow] with a different
  /// `realStream` argument, but its already-created State ignores that;
  /// nothing actually observes it after `initState`). Clears [_realStream]:
  /// a plain switch never has a fresh answer to show, and a Stream from an
  /// earlier generation may already be attached (Streams like the one
  /// [geminiReplyStream] returns can only be listened to once) — [_ReplyFlow]
  /// treats real-selected-but-no-stream as "nothing sent yet" rather than
  /// starting the fake supply under the real supply's name.
  void _selectSupply(bool useReal) {
    if (useReal && !_hasApiKey) return;
    if (useReal == _useRealSupply) return;
    setState(() {
      _useRealSupply = useReal;
      _realStream = null;
      _receiving = false;
      _generation++;
    });
  }

  /// Send ([question] is the text from the input field) or replay
  /// ([question] is null, meaning "resend"). For the fake supply, [question]
  /// is not looked at at all — either way it just re-runs the fake supply.
  /// For the real supply, it resends `question ?? _lastQuestion`; if that is
  /// null or blank, it does nothing — there is nothing real to (re)send yet,
  /// and a blank question is never sent. Either way, on an actual (re)send it
  /// advances the generation, rebuilds [_ReplyFlow], and jumps the reading
  /// position back to the top (the package itself never scrolls).
  void _start(String? question) {
    if (!_useRealSupply) {
      setState(() => _generation++);
      _jumpToTop();
      return;
    }
    final effective = question ?? _lastQuestion;
    if (effective == null || effective.trim().isEmpty) return;
    setState(() {
      _lastQuestion = effective;
      _realStream = _startRealStream(effective);
      _receiving = true;
      _generation++;
    });
    // Only an explicit send (not a replay, where `question` is null) empties
    // the field — replay keeps whatever the user may have typed since.
    if (question != null) _questionController.clear();
    _jumpToTop();
  }

  /// Jumps [Keys.replyScroll] back to the top, if it is attached.
  void _jumpToTop() {
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  /// Passed to [_ReplyFlow] as `onReceivingChanged`: called with `false` once
  /// the real supply's Controller reports it is done receiving (Stream
  /// closed or errored).
  void _setReceiving(bool value) {
    if (_receiving == value) return;
    setState(() => _receiving = value);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _questionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBackground,
      // Wrapped in a SafeArea so that the switch and the reply do not slip
      // under the status bar or the notch (this Scaffold has no AppBar, so
      // the top inset is not left free automatically). The background color
      // is painted by the Scaffold itself, so it reaches beyond the
      // SafeArea.
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SupplySwitch(
              useReal: _useRealSupply,
              hasApiKey: _hasApiKey,
              onSelectFake: () => _selectSupply(false),
              onSelectReal: () => _selectSupply(true),
            ),
            if (!_hasApiKey) const _NoKeyReason(),
            Expanded(
              child: SingleChildScrollView(
                key: Keys.replyScroll,
                controller: _scrollController,
                padding: _pagePadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ReplyFlow(
                      key: ValueKey(_generation),
                      thinking: widget.thinking,
                      reply: widget.reply,
                      random: widget.random,
                      useReal: _useRealSupply,
                      realStream: _useRealSupply ? _realStream : null,
                      question: _lastQuestion,
                      onReceivingChanged: _setReceiving,
                    ),
                    const SizedBox(height: _actionsSpacingTop),
                    Center(
                      child: _ReplayButton(
                        onTap: () => _start(null),
                        receiving: _receiving,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Kept inside the body rather than in `bottomNavigationBar`: the
            // Scaffold shrinks its body above the keyboard but leaves the
            // bottom bar underneath it, which hid the question while typing.
            _QuestionInputBar(
              controller: _questionController,
              onSend: () => _start(_questionController.text),
              receiving: _receiving,
            ),
          ],
        ),
      ),
    );
  }
}

/// Supply Chunk to a [StreamingReplyController]: either the fake supply
/// ([FakeReplySource], when [useReal] is false) or a real supply
/// ([realStream]) attached via [StreamingReplyController.attach] (when
/// [useReal] is true and [realStream] is non-null — real-selected-but-null
/// starts no supply at all). Owns exactly one [StreamingReplyController]
/// (and, in the fake case, one [FakeReplySource]); both are disposed together
/// when this widget is disposed (which also cancels the real supply's
/// subscription, per [StreamingReplyController.dispose]).
class _ReplyFlow extends StatefulWidget {
  const _ReplyFlow({
    super.key,
    required this.thinking,
    required this.reply,
    this.random,
    required this.useReal,
    this.realStream,
    this.question,
    this.onReceivingChanged,
  });

  /// The thinking text to supply (used only when [useReal] is false).
  final String thinking;

  /// The reply to supply (used only when [useReal] is false).
  final String reply;

  /// The supply's [Random] ([ReplyPage.random] passed straight through; fake
  /// supply only).
  final Random? random;

  /// Whether this generation is the real supply (true) or the fake supply
  /// (false).
  final bool useReal;

  /// The real supply for this generation (only meaningful when [useReal] is
  /// true). Null when nothing has been sent yet for the real supply — in
  /// that case no supply is started at all (not even the fake one): the flow
  /// stays in its pristine, pre-receiving state until a real question is
  /// sent.
  final Stream<Chunk>? realStream;

  /// The question last sent to the real supply ([ReplyPageState._lastQuestion]
  /// passed straight through). Shown as a pale line above the reply once
  /// [realStream] is non-null; ignored otherwise (fake supply, or
  /// real-selected-but-nothing-sent-yet).
  final String? question;

  /// Called with `false` once this generation's Controller reports it is
  /// done receiving (Stream closed or errored). Only ever fires when
  /// [useReal] is true and [realStream] is non-null.
  final ValueChanged<bool>? onReceivingChanged;

  @override
  State<_ReplyFlow> createState() => _ReplyFlowState();
}

class _ReplyFlowState extends State<_ReplyFlow> {
  late final StreamingReplyController _controller;
  FakeReplySource? _source;

  /// The error received through [StreamingReplyController.attach]'s
  /// `onError` (only possible with the real supply).
  Object? _error;

  @override
  void initState() {
    super.initState();
    _controller = StreamingReplyController();
    if (widget.useReal) {
      final realStream = widget.realStream;
      // Nothing sent yet for the real supply: stay pristine rather than
      // start the fake supply under the real supply's name.
      if (realStream != null) {
        _controller.addListener(_handleControllerChange);
        _controller.attach(
          realStream,
          onError: (error, stackTrace) => setState(() => _error = error),
        );
      }
    } else {
      _source = FakeReplySource(
        controller: _controller,
        thinking: widget.thinking,
        reply: widget.reply,
        random: widget.random,
      )..start();
    }
  }

  /// Reports completion (Stream closed or errored — both set
  /// [StreamingReplyController.isComplete]) back to [ReplyPage] through
  /// [_ReplyFlow.onReceivingChanged]. Fires on every notification while
  /// attached, not just the one where it flips; the parent's
  /// [ReplyPageState._setReceiving] already no-ops on a repeat value.
  void _handleControllerChange() {
    if (_controller.isComplete) widget.onReceivingChanged?.call(false);
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerChange);
    _source?.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Real supply selected but nothing sent yet: show the guidance line in
    // place of StreamingReply instead of an idling (empty) one.
    if (widget.useReal && widget.realStream == null) {
      return const Text(_guidanceLineText, style: _paleLineTextStyle);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.useReal && widget.question != null) ...[
          Text(widget.question!, style: _paleLineTextStyle),
          const SizedBox(height: _questionLineSpacingBottom),
        ],
        StreamingReply(
          controller: _controller,
          thinkingTitle: '考え中…',
          thoughtForSeconds: (seconds) => '$seconds 秒考えました',
        ),
        if (_error != null) ...[
          const SizedBox(height: _errorSpacingTop),
          Text('エラー: $_error', style: _errorTextStyle),
        ],
      ],
    );
  }
}

/// Guidance line shown by [_ReplyFlowState] in place of the reply while the
/// real supply is selected but nothing has been sent yet.
const _guidanceLineText = '質問を入力して送ってください';

/// Top switch between fake and real supply (`.demo3-topbar` / `.demo3-segment`
/// / `.demo3-segment-btn`).
class _SupplySwitch extends StatelessWidget {
  const _SupplySwitch({
    required this.useReal,
    required this.hasApiKey,
    required this.onSelectFake,
    required this.onSelectReal,
  });

  final bool useReal;
  final bool hasApiKey;
  final VoidCallback onSelectFake;
  final VoidCallback onSelectReal;

  static const _fakeLabel = '作り物';
  static const _realLabel = '本物 (Gemini)';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: _topbarPadding,
      child: Container(
        padding: _segmentPadding,
        decoration: BoxDecoration(
          color: _segmentBackground,
          borderRadius: BorderRadius.circular(_segmentBorderRadius),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SegmentButton(
              label: _fakeLabel,
              active: !useReal,
              onTap: onSelectFake,
            ),
            _SegmentButton(
              label: _realLabel,
              active: useReal,
              disabled: !hasApiKey,
              onTap: onSelectReal,
            ),
          ],
        ),
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  const _SegmentButton({
    required this.label,
    required this.active,
    required this.onTap,
    this.disabled = false,
  });

  final String label;
  final bool active;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: disabled ? null : onTap,
      child: Container(
        padding: _segmentButtonPadding,
        decoration: active
            ? BoxDecoration(
                color: _segmentActiveBackground,
                borderRadius: BorderRadius.circular(_segmentBorderRadius),
                boxShadow: const [_segmentActiveShadow],
              )
            : null,
        child: Text(
          label,
          style: TextStyle(
            color: (active ? _segmentActiveTextColor : _segmentTextColor)
                .withValues(alpha: disabled ? 0.5 : 1),
            fontSize: _segmentFontSize,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// Reason line shown under the switch when [ReplyPage.apiKey] is empty.
class _NoKeyReason extends StatelessWidget {
  const _NoKeyReason();

  static const _text = 'API キーが無いため本物は選べません';

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: _noKeyReasonPadding,
      child: Text(
        _text,
        style: TextStyle(
          color: _noKeyReasonTextColor,
          fontSize: _noKeyReasonFontSize,
        ),
      ),
    );
  }
}

/// Bottom-fixed question input + send button (`.demo3-inputbar` /
/// `.demo3-input` / `.demo3-send-btn`).
class _QuestionInputBar extends StatelessWidget {
  const _QuestionInputBar({
    required this.controller,
    required this.onSend,
    this.receiving = false,
  });

  final TextEditingController controller;
  final VoidCallback onSend;

  /// True while a real-supply request is in flight — disables the send
  /// button. The field itself stays editable; only sending is blocked.
  final bool receiving;

  static const _hint = '質問を入力';
  static const _sendLabel = '送る';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: _inputBarPadding,
      decoration: const BoxDecoration(
        color: _inputBarBackground,
        border: Border(
          top: BorderSide(
            color: _inputBarBorderColor,
            width: _inputBarBorderWidth,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              style: const TextStyle(
                color: _questionFieldTextColor,
                fontSize: _questionFieldFontSize,
              ),
              decoration: InputDecoration(
                hintText: _hint,
                hintStyle: const TextStyle(
                  color: _questionFieldHintColor,
                  fontSize: _questionFieldFontSize,
                ),
                filled: true,
                fillColor: _pageBackground,
                isDense: true,
                contentPadding: _questionFieldPadding,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(
                    _questionFieldBorderRadius,
                  ),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: _inputBarGap),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              final active = value.text.trim().isNotEmpty && !receiving;
              return Semantics(
                label: _sendLabel,
                button: true,
                enabled: !receiving,
                // The "→" glyph below has its own auto-generated semantics
                // label; without this, it merges into ours as "送る\n→"
                // instead of the exact "送る" `find.bySemanticsLabel` needs.
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: receiving ? null : onSend,
                  child: Container(
                    width: _sendButtonSize,
                    height: _sendButtonSize,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: active
                          ? _sendButtonActiveBackground
                          : _sendButtonInactiveBackground,
                      shape: BoxShape.circle,
                    ),
                    child: const Text(
                      '→',
                      style: TextStyle(
                        color: _sendButtonIconColor,
                        fontSize: _sendButtonIconSize,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// The replay button.
class _ReplayButton extends StatelessWidget {
  const _ReplayButton({required this.onTap, this.receiving = false});

  final VoidCallback onTap;

  /// True while a real-supply request is in flight — disables this button
  /// (mirrors [_QuestionInputBar.receiving]).
  final bool receiving;

  /// The button's label.
  static const _label = '最初から流す';

  @override
  Widget build(BuildContext context) {
    // Wrapped like the send button (Semantics carrying label/button/enabled,
    // excludeSemantics true) so `getSemantics` reads enabled state off this
    // node — the Key now lives on the Semantics widget rather than the
    // GestureDetector, since that is the node `find.byKey` must resolve to.
    return Semantics(
      key: Keys.replayButton,
      label: _label,
      button: true,
      enabled: !receiving,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: receiving ? null : onTap,
        child: Opacity(
          // No mock reference for the disabled look; dims like other
          // disabled controls in this file (e.g. _SegmentButton).
          opacity: receiving ? 0.5 : 1,
          child: Container(
            padding: _replayButtonPadding,
            decoration: BoxDecoration(
              color: _replayButtonBackground,
              border: Border.all(
                color: _replayButtonBorderColor,
                width: _replayButtonBorderWidth,
              ),
              borderRadius: BorderRadius.circular(_replayButtonBorderRadius),
            ),
            child: const Text(_label, style: _replayButtonTextStyle),
          ),
        ),
      ),
    );
  }
}
