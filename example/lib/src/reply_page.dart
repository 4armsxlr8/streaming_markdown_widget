import 'dart:math';

import 'package:flutter/material.dart';
import 'package:streaming_markdown_widget/streaming_markdown_widget.dart';

import 'app.dart';
import 'fake_reply_source.dart';
import 'gemini_reply_source.dart';
import 'keys.dart';
import 'sample_reply.dart';

/// The page background, and the AppBar's flat background (mock:
/// `--demo4-page-bg`, `appBarStyle: flat`).
const _pageBackground = Color(0xFFF1F2F4);

/// AppBar title style (`.demo4-title`).
const _appBarTitleStyle = TextStyle(
  color: Color(0xFF1D2026),
  fontSize: 17,
  fontWeight: FontWeight.w600,
);

/// AppBar bottom divider, used instead of a shadow (flat style, `.demo4-appbar`'s
/// `border-bottom: 1px solid #E3E5E9`).
const _appBarBorderColor = Color(0xFFE3E5E9);
const _appBarBorderWidth = 1.0;

/// AppBar icon buttons (`.demo4-iconbtn` / its `svg`).
const _appBarIconColor = Color(0xFF3A3F47);
const _appBarIconSize = 22.0;

/// Padding of the reply's vertical scroll area (`.demo4-scroll`'s
/// `padding: 10px 16px`). The bottom is computed instead of taking the
/// mock's fixed value: it is the input pill's own height
/// ([_inputBarPadding]'s top+bottom plus the taller of [_sendButtonSize] and
/// one scaled line of [_inputTextStyle]) plus [_inputBarBottom], so the
/// reply's tail is never hidden under the pill at any text scale. The
/// device's safe-area inset is not part of it — the body sits inside a
/// [SafeArea], so this whole area already ends above the inset.
EdgeInsets _scrollPadding(BuildContext context) {
  final lineHeight =
      _inputTextStyle.fontSize! * MediaQuery.textScalerOf(context).scale(1);
  final bottom =
      _inputBarPadding.vertical +
      max(_sendButtonSize, lineHeight) +
      _inputBarBottom;
  return EdgeInsets.fromLTRB(16, 10, 16, bottom);
}

/// Gap between the question bubble and the reply/thinking below it. No
/// single mock token covers both cases: `.demo4-thinking`'s `margin-top` is
/// 12px and `.demo4-reply`'s is 10px depending on which one follows the
/// bubble — 12px is reused for both (deviation — no mock reference for the
/// reply-only case).
const _bubbleSpacingBottom = 12.0;

/// Question bubble (`.demo4-bubble`, right-aligned by `.demo4-qrow`).
const _bubbleColor = Color(0xFFDCE3EE);
const _bubbleRadius = 18.0;
const _bubbleMaxWidthFraction = 0.78; // `--demo4-bubble-max: 78%`
const _bubblePadding = EdgeInsets.symmetric(horizontal: 14, vertical: 9);
const _bubbleTextStyle = TextStyle(
  color: Color(0xFF1D2026),
  fontSize: 15,
  height: 1.45,
);

/// Error line under the reply (`.demo4-error`).
const _errorSpacingTop = 12.0;
const _errorTextStyle = TextStyle(color: Color(0xFFB3261E), fontSize: 12);

/// Bottom-fixed floating input pill (`.demo4-inputbar`).
const _inputBarInset = 12.0;
const _inputBarBottom = 16.0;
const _inputBarBackground = Color(0xFFFFFFFF);
const _inputBarRadius = 999.0;
const _inputBarPadding = EdgeInsets.fromLTRB(16, 6, 6, 6);
const _inputBarGap = 8.0;
const _inputBarShadow = [
  BoxShadow(color: Color(0x1A000000), offset: Offset(0, 4), blurRadius: 16),
  BoxShadow(
    color: Color(0x0A000000),
    spreadRadius: 1,
  ), // the CSS's `0 0 0 1` outline
];

/// Question field (`.demo4-input` / `.demo4-input--placeholder`).
const _questionHint = 'Ask anything';
const _inputTextStyle = TextStyle(color: Color(0xFF1D2026), fontSize: 13.5);
const _inputHintStyle = TextStyle(color: Color(0xFF9099A6), fontSize: 13.5);

/// Send button (`.demo4-send` / `.demo4-send--disabled`).
const _sendLabel = 'Send';
const _sendButtonSize = 34.0;
const _sendButtonInactiveBackground = Color(0xFFDDE0E6);
const _sendButtonActiveBackground = Color(0xFF3A3F47);
const _sendButtonIconColor = Color(0xFFFFFFFF);
const _sendButtonIconSize = 14.0;

/// API key dialog text (`.demo4-dialog-title` / `.demo4-field-label` /
/// `.demo4-helper` / `.demo4-btn-text` / `.demo4-btn-filled`). Chrome (radii,
/// shadow, field border) is left to the plain `AlertDialog` this uses,
/// rather than hand-matched to the mock — spec asks for `showDialog` +
/// `AlertDialog`, not a custom-drawn overlay.
const _apiKeyDialogTitle = 'Gemini API key';

/// Both the dialog's key field label and the AppBar key icon's
/// `semanticLabel` — the icon and the field it opens read the same.
const _apiKeyLabel = 'API key';
const _apiKeyDialogNote = 'Kept in memory only. Cleared when the app closes.';
const _apiKeyClearLabel = 'Clear';
const _apiKeyUseLabel = 'Use key';

/// The example app's screen: an AppBar (title, replay, API key), a
/// right-aligned question bubble, the reply (no bubble of its own), and a
/// floating input pill pinned to the bottom edge.
///
/// The fake supply ([FakeReplySource]) starts running automatically the
/// moment the app launches, showing [sampleQuestion] in the bubble. Sending
/// replaces the bubble with the typed question; if the API key (entered
/// through the key icon's dialog, or passed in as [apiKey]) is empty, the
/// send just replays the fake supply — otherwise the question goes once to
/// [realReplyStream] (or, when it is omitted, [geminiReplyStream]) and the
/// reply's Stream is run through [StreamingReplyController.attach]. Errors
/// are received through [attach]'s `onError` and shown as one line under the
/// reply. Every send or replay advances the generation ([_generation]) and
/// rebuilds [_ReplyFlow] by Key, so even while receiving, the old supply and
/// Controller are disposed in that build phase. The bubble always shows the
/// question replay would resend next ([_ReplyPageState._lastQuestion], or
/// [sampleQuestion] until the first send), real supply or fake. Replay
/// resends that question to the real supply if a key is currently set;
/// otherwise it replays the fake supply from the start. While a real reply
/// is being received, both the send and replay controls are disabled
/// instead of starting another one.
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

  /// The Gemini API key's initial value (spec: from `--dart-define`, never
  /// stored on device, never shown on screen). Editable afterward through
  /// the AppBar's key icon; empty disables the real supply.
  final String apiKey;

  /// Gemini model name, used when [realReplyStream] is not overridden.
  final String model;

  /// Real supply factory (question → Stream of [Chunk]). Defaults to
  /// [geminiReplyStream] with the current key / [model]; tests substitute a
  /// fake [Stream] here instead of calling the real Gemini API.
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
  /// each time a new reply starts flowing ([_startFlow]).
  final ScrollController _scrollController = ScrollController();

  /// The text in the input field at the bottom edge.
  final TextEditingController _questionController = TextEditingController();

  /// The current API key (starts as [ReplyPage.apiKey]; editable through the
  /// dialog opened from the AppBar's key icon). Kept only in memory.
  late String _apiKey = widget.apiKey;

  /// The question from the most recent send, real supply or fake — shown in
  /// the bubble, and what replay re-sends. `null` until a send has happened
  /// at least once; the bubble shows [sampleQuestion] while it is `null`.
  String? _lastQuestion;

  /// The real supply for the current generation — non-null exactly when this
  /// generation is using the real supply instead of the fake one.
  Stream<Chunk>? _realStream;

  /// True while a real-supply request is in flight. Set by [_startFlow] the
  /// moment a real Stream is created; cleared once [_ReplyFlow] reports,
  /// through [_setReceiving], that its Controller has completed (or
  /// errored — [StreamingReplyController.attach] completes on error too).
  /// The fake supply never sets this.
  bool _receiving = false;

  bool get _hasApiKey => _apiKey.isNotEmpty;

  Stream<Chunk> _startRealStream(String question) =>
      widget.realReplyStream?.call(question) ??
      geminiReplyStream(question, apiKey: _apiKey, model: widget.model);

  /// Starts a new generation. [sentQuestion] is the text from the input
  /// field for an explicit send, or `null` for a replay (which resends
  /// [_lastQuestion] instead, and — unlike a send — never clears the input
  /// field). The question goes to the real supply when a key is set and
  /// there is a question to send at all; otherwise the fake supply runs.
  void _startFlow(String? sentQuestion) {
    final question = sentQuestion ?? _lastQuestion;
    setState(() {
      if (sentQuestion != null) _lastQuestion = sentQuestion;
      _realStream = (_hasApiKey && question != null)
          ? _startRealStream(question)
          : null;
      _receiving = _realStream != null;
      _generation++;
    });
    if (sentQuestion != null) _questionController.clear();
    _jumpToTop();
  }

  /// The send button / Enter key: sends the input field's text. Empty text
  /// (after trimming) does nothing, and so does a send while a real reply is
  /// still being received (the button is disabled, but the keyboard's send
  /// key reaches this either way).
  void _send() {
    if (_receiving) return;
    final question = _questionController.text.trim();
    if (question.isEmpty) return;
    _startFlow(question);
  }

  /// The AppBar's replay icon: resends [_lastQuestion] to the real supply if
  /// a key is set and a question has been sent at least once before,
  /// otherwise replays the fake supply from the start.
  void _replay() => _startFlow(null);

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

  /// Opens the API key dialog. A non-null result (from "Clear" or "Use key")
  /// replaces [_apiKey]; dismissing the dialog any other way leaves it
  /// unchanged. The dialog pops its field's raw text, so the single trim
  /// happens here, where the key enters state — a blank-only entry therefore
  /// reads as no key at all.
  Future<void> _openApiKeyDialog() async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => _ApiKeyDialog(initialKey: _apiKey),
    );
    if (!mounted || result == null) return;
    setState(() => _apiKey = result.trim());
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
      appBar: AppBar(
        backgroundColor: _pageBackground,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(appTitle, style: _appBarTitleStyle),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(_appBarBorderWidth),
          child: SizedBox(
            height: _appBarBorderWidth,
            width: double.infinity,
            child: ColoredBox(color: _appBarBorderColor),
          ),
        ),
        actions: [
          IconButton(
            key: Keys.replayButton,
            iconSize: _appBarIconSize,
            color: _appBarIconColor,
            onPressed: _receiving ? null : _replay,
            icon: const Icon(Icons.refresh, semanticLabel: 'Replay'),
          ),
          IconButton(
            key: Keys.apiKeyButton,
            iconSize: _appBarIconSize,
            color: _appBarIconColor,
            onPressed: _openApiKeyDialog,
            icon: const Icon(Icons.vpn_key, semanticLabel: _apiKeyLabel),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Stack(
          fit: StackFit.expand,
          children: [
            SingleChildScrollView(
              key: Keys.replyScroll,
              controller: _scrollController,
              padding: _scrollPadding(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _QuestionBubble(text: _lastQuestion ?? sampleQuestion),
                  const SizedBox(height: _bubbleSpacingBottom),
                  _ReplyFlow(
                    key: ValueKey(_generation),
                    thinking: widget.thinking,
                    reply: widget.reply,
                    random: widget.random,
                    realStream: _realStream,
                    apiKey: _apiKey,
                    onReceivingChanged: _setReceiving,
                  ),
                ],
              ),
            ),
            Positioned(
              left: _inputBarInset,
              right: _inputBarInset,
              bottom: _inputBarBottom,
              child: _QuestionInputBar(
                controller: _questionController,
                onSend: _send,
                receiving: _receiving,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Right-aligned question bubble (`.demo4-qrow` / `.demo4-bubble`): shows
/// [sampleQuestion] at launch and stays that way until the first send.
class _QuestionBubble extends StatelessWidget {
  const _QuestionBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: constraints.maxWidth * _bubbleMaxWidthFraction,
            ),
            child: Container(
              padding: _bubblePadding,
              decoration: const BoxDecoration(
                color: _bubbleColor,
                borderRadius: BorderRadius.all(Radius.circular(_bubbleRadius)),
              ),
              child: Text(text, style: _bubbleTextStyle),
            ),
          );
        },
      ),
    );
  }
}

/// Supplies Chunk to a [StreamingReplyController]: the fake supply
/// ([FakeReplySource], when [realStream] is null) or the real supply
/// ([realStream], attached via [StreamingReplyController.attach], when it is
/// non-null). Owns exactly one [StreamingReplyController] (and, in the fake
/// case, one [FakeReplySource]); both are disposed together when this widget
/// is disposed (which also cancels the real supply's subscription, per
/// [StreamingReplyController.dispose]).
class _ReplyFlow extends StatefulWidget {
  const _ReplyFlow({
    super.key,
    required this.thinking,
    required this.reply,
    this.random,
    this.realStream,
    required this.apiKey,
    this.onReceivingChanged,
  });

  /// The thinking text to supply (used only when [realStream] is null).
  final String thinking;

  /// The reply to supply (used only when [realStream] is null).
  final String reply;

  /// The supply's [Random] ([ReplyPage.random] passed straight through; fake
  /// supply only).
  final Random? random;

  /// The real supply for this generation, or null to run the fake supply
  /// instead.
  final Stream<Chunk>? realStream;

  /// The screen's current API key ([_ReplyPageState._apiKey]), used only to
  /// redact it from an error's text before showing that error.
  final String apiKey;

  /// Called with `false` once this generation's Controller reports it is
  /// done receiving (Stream closed or errored). Only ever fires when
  /// [realStream] is non-null.
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

  /// The key this generation's request was sent with — [_ReplyFlow.apiKey]
  /// as it was when the flow was created (snapshotted in [initState], so
  /// that editing the key in the dialog while an old error is still on
  /// screen cannot un-redact it).
  late final String _requestKey;

  @override
  void initState() {
    super.initState();
    _requestKey = widget.apiKey;
    _controller = StreamingReplyController();
    final realStream = widget.realStream;
    if (realStream != null) {
      _controller.addListener(_handleControllerChange);
      _controller.attach(
        realStream,
        onError: (error, stackTrace) => setState(() => _error = error),
      );
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
  /// [_ReplyFlow.onReceivingChanged]. Unsubscribes itself first: a still
  /// fast-forwarding previous generation's Controller keeps ticking (and
  /// notifying) past this generation's build, and without unsubscribing it
  /// would keep reporting "done" on every tick, clearing
  /// [ReplyPageState._receiving] out from under a request the current
  /// generation just started.
  void _handleControllerChange() {
    if (!_controller.isComplete) return;
    _controller.removeListener(_handleControllerChange);
    widget.onReceivingChanged?.call(false);
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        StreamingReply(
          controller: _controller,
          thinkingTitle: 'Thinking…',
          thoughtForSeconds: (seconds) => 'Thought for ${seconds}s',
        ),
        if (_error != null) ...[
          const SizedBox(height: _errorSpacingTop),
          Text(_errorLine(), style: _errorTextStyle),
        ],
      ],
    );
  }

  /// `'Error: '` plus [_error]'s text, with [_requestKey] (if set)
  /// replaced by `***` everywhere it appears — `dart:io`'s header
  /// validation includes the offending header value verbatim in its
  /// `FormatException` message, and the Gemini request sends the key as a
  /// header.
  String _errorLine() {
    var message = '$_error';
    if (_requestKey.isNotEmpty) {
      message = message.replaceAll(_requestKey, '***');
    }
    return 'Error: $message';
  }
}

/// Bottom-fixed floating input pill (`.demo4-inputbar` / `.demo4-input` /
/// `.demo4-send`).
class _QuestionInputBar extends StatelessWidget {
  const _QuestionInputBar({
    required this.controller,
    required this.onSend,
    this.receiving = false,
  });

  final TextEditingController controller;
  final VoidCallback onSend;

  /// True while a real-supply request is in flight — disables the send
  /// button. The field itself stays editable.
  final bool receiving;

  @override
  Widget build(BuildContext context) {
    final onTap = receiving ? null : onSend;
    return Container(
      padding: _inputBarPadding,
      decoration: const BoxDecoration(
        color: _inputBarBackground,
        borderRadius: BorderRadius.all(Radius.circular(_inputBarRadius)),
        boxShadow: _inputBarShadow,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: Keys.questionField,
              controller: controller,
              style: _inputTextStyle,
              textInputAction: TextInputAction.send,
              // `onSend` itself already no-ops while `receiving`
              // (`ReplyPageState._send`), so this needs no separate guard.
              onSubmitted: (_) => onSend(),
              decoration: const InputDecoration(
                hintText: _questionHint,
                hintStyle: _inputHintStyle,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 8),
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(width: _inputBarGap),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              final active = value.text.trim().isNotEmpty && !receiving;
              return Semantics(
                key: Keys.sendButton,
                label: _sendLabel,
                button: true,
                enabled: !receiving,
                // Gives the node its own `SemanticsAction.tap` (same as
                // the replay `IconButton`'s built-in one) — `excludeSemantics`
                // below hides the child `GestureDetector`'s tap from the
                // tree, so without this a screen reader's activate gesture
                // would have nothing to call.
                onTap: onTap,
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onTap,
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
                    child: const Icon(
                      Icons.arrow_upward,
                      color: _sendButtonIconColor,
                      size: _sendButtonIconSize,
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

/// The API key dialog (`showDialog` + `AlertDialog`), opened from the
/// AppBar's key icon. The key lives only in this dialog's own
/// [TextEditingController] for as long as it's open — never written to
/// disk. Returns the field's raw text on "Use key" (trimmed by
/// [_ReplyPageState._openApiKeyDialog]), `''` on "Clear", or `null` if
/// dismissed any other way (leaving [ReplyPage]'s key unchanged).
class _ApiKeyDialog extends StatefulWidget {
  const _ApiKeyDialog({required this.initialKey});

  /// The key to pre-fill the field with (the current [ReplyPage._apiKey]).
  final String initialKey;

  @override
  State<_ApiKeyDialog> createState() => _ApiKeyDialogState();
}

class _ApiKeyDialogState extends State<_ApiKeyDialog> {
  late final _controller = TextEditingController(text: widget.initialKey);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(_apiKeyDialogTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // `obscureText` only hides the glyphs on screen — this field's
          // `TextEditingController` still holds the key as plain text, so
          // `debugDumpApp` / DevTools' widget inspector can still show it.
          // Accepted for the example's scope.
          TextField(
            controller: _controller,
            obscureText: true,
            decoration: const InputDecoration(labelText: _apiKeyLabel),
          ),
          const SizedBox(height: 8),
          const Text(_apiKeyDialogNote),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(''),
          child: const Text(_apiKeyClearLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text(_apiKeyUseLabel),
        ),
      ],
    );
  }
}
