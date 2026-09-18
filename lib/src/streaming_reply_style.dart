import 'package:flutter/widgets.dart';

/// Look-and-feel values for the reply Markdown, shared by [StreamingReply],
/// [RevealedMarkdown], [ThinkingFrame], and (via [StreamingReplyController])
/// the reveal timing.
///
/// Defaults match the current sample. Values used only by the sample screen
/// (page background/padding, replay button, reply bubble) and by the fake
/// supply (chunk timing) are not here — they live as local constants in
/// `reply_page.dart` and `fake_reply_source.dart`.
///
/// Not `const`-constructible: the constructor validates every value (in both
/// debug and release) and throws [ArgumentError] for a non-positive
/// duration, a non-positive or non-finite diameter/height, a non-positive or
/// non-finite `fontSize`/`height` on one of the 11 per-role [TextStyle]s
/// (only when set — an unset one is inherited instead, so it is not
/// validated), a negative or non-finite margin/spacing/radius/border-width/
/// indent, or a waiting-dot opacity outside 0–1 (or a min above the max).
/// Zero margins and 0/1 opacities are valid.
///
/// Typography is passed as 11 per-role [TextStyle]s (body, `h2`-tier and
/// `h3`-tier headings, link, blockquote, inline code, code block, table and
/// table header, thinking text, and the thinking frame's headline row)
/// instead of separate color/size/weight fields, and each is kept exactly as
/// passed — none is pre-merged with the others. [RevealedMarkdown] and
/// [ThinkingFrame] merge the role that applies onto a base style at build
/// time (the surrounding `DefaultTextStyle`, or for headings/blockquote/
/// link/inline code, the running style built up while descending through
/// the Markdown tree) through this class's `resolve*` methods, so any
/// attribute a role's `TextStyle` does not set is inherited from that base
/// instead. If the merge still leaves `color` null, it is filled with that
/// role's own default color — a revealing character draws its progress as
/// the alpha of its style's color, so a null one could never make an
/// appearance.
///
/// The time fields split into two groups by where they are read from. The
/// clock's 6 values ([revealInterval], [fadeDuration], [catchUpBudget],
/// [fastForwardBudget], [minRevealInterval], [thinkingCollapseDuration]) are
/// read from `controller.style` — they only take effect when passed to
/// [StreamingReplyController]; the same-named fields on a
/// [StreamingReply]/[RevealedMarkdown]/[ThinkingFrame] `style` are a separate
/// instance and are never read. The Widget's 4 values
/// ([thinkingShimmerDuration], [waitingDotDuration], [waitingDotStagger],
/// [thinkingCollapseCurve]) are
/// read from the nearest [StreamingReplyStyleScope] instead. Pass the same
/// values to both places (or share one instance) to keep them in sync.
class StreamingReplyStyle {
  StreamingReplyStyle({
    // Colors.
    this.codeBlockBackground = const Color(0xFF23272F),
    this.quoteBorderColor = const Color(0xFFD6D9E0),
    this.tableBorderColor = const Color(0xFFE1E3E8),
    this.tableHeaderBackground = const Color(0xFFF4F5F8),
    this.thinkingFrameBorderColor = const Color(0xFFD7DAE0),
    this.thinkingShimmerBaseColor = const Color(0xFFA9AEB6),
    this.thinkingShimmerHighlightColor = const Color(0xFF3F4650),
    this.waitingDotColor = const Color(0xFFB4B9C1),
    // Time, clock side (read from controller.style; see class doc).
    this.revealInterval = const Duration(milliseconds: 25),
    this.fadeDuration = const Duration(milliseconds: 300),
    this.catchUpBudget = const Duration(milliseconds: 600),
    this.fastForwardBudget = const Duration(milliseconds: 400),
    this.minRevealInterval = const Duration(milliseconds: 16),
    this.thinkingCollapseDuration = const Duration(milliseconds: 300),
    // Time, Widget side (read from the nearest StreamingReplyStyleScope; see
    // class doc).
    this.thinkingShimmerDuration = const Duration(milliseconds: 1600),
    this.waitingDotDuration = const Duration(milliseconds: 1400),
    this.waitingDotStagger = const Duration(milliseconds: 200),
    this.thinkingCollapseCurve = Curves.fastOutSlowIn,
    // TextStyle (per-role typography; see class doc for the merge rules).
    this.bodyTextStyle = _defaultBodyTextStyle,
    this.h2TextStyle = _defaultH2TextStyle,
    this.h3TextStyle = _defaultH3TextStyle,
    this.linkTextStyle = _defaultLinkTextStyle,
    this.quoteTextStyle = _defaultQuoteTextStyle,
    this.inlineCodeTextStyle = _defaultInlineCodeTextStyle,
    this.codeBlockTextStyle = _defaultCodeBlockTextStyle,
    this.tableTextStyle = _defaultTableTextStyle,
    this.tableHeaderTextStyle = _defaultTableHeaderTextStyle,
    this.thinkingTextStyle = _defaultThinkingTextStyle,
    this.thinkingHeadTextStyle = _defaultThinkingHeadTextStyle,
    // Block spacing.
    this.blockSpacing = 11,
    this.h2SpacingBottom = 9,
    this.h3SpacingBottom = 7,
    this.listItemSpacing = 3,
    this.listIndent = 19.6,
    // Code block.
    this.codeBlockBorderRadius = 8,
    this.codeBlockPadding = const EdgeInsets.symmetric(
      horizontal: 12,
      vertical: 10,
    ),
    // Table.
    this.tableBorderWidth = 1,
    this.tableCellPadding = const EdgeInsets.symmetric(
      horizontal: 9,
      vertical: 5,
    ),
    // Blockquote.
    this.quoteBorderWidth = 3,
    this.quoteIndent = 11,
    // Thinking frame.
    this.thinkingFrameBorderWidth = 2,
    this.thinkingFrameIndent = 10,
    this.thinkingFrameSpacingBottom = 10,
    // Waiting dots.
    this.waitingDotDiameter = 7,
    this.waitingDotGap = 5,
    this.waitingDotsHeight = 20,
    this.waitingDotMinOpacity = 0.22,
    this.waitingDotMaxOpacity = 0.9,
  }) {
    _requireDuration(revealInterval, 'revealInterval');
    _requireDuration(fadeDuration, 'fadeDuration');
    _requireDuration(catchUpBudget, 'catchUpBudget');
    _requireDuration(fastForwardBudget, 'fastForwardBudget');
    _requireDuration(minRevealInterval, 'minRevealInterval');
    if (minRevealInterval > revealInterval) {
      throw ArgumentError(
        'minRevealInterval ($minRevealInterval) must not exceed '
        'revealInterval ($revealInterval)',
      );
    }
    _requireDuration(thinkingCollapseDuration, 'thinkingCollapseDuration');
    _requireDuration(thinkingShimmerDuration, 'thinkingShimmerDuration');
    _requireDuration(waitingDotDuration, 'waitingDotDuration');
    _requireDuration(waitingDotStagger, 'waitingDotStagger');

    _requireTextStyleMetrics(bodyTextStyle, 'bodyTextStyle');
    _requireTextStyleMetrics(h2TextStyle, 'h2TextStyle');
    _requireTextStyleMetrics(h3TextStyle, 'h3TextStyle');
    _requireTextStyleMetrics(linkTextStyle, 'linkTextStyle');
    _requireTextStyleMetrics(quoteTextStyle, 'quoteTextStyle');
    _requireTextStyleMetrics(inlineCodeTextStyle, 'inlineCodeTextStyle');
    _requireTextStyleMetrics(codeBlockTextStyle, 'codeBlockTextStyle');
    _requireTextStyleMetrics(tableTextStyle, 'tableTextStyle');
    _requireTextStyleMetrics(tableHeaderTextStyle, 'tableHeaderTextStyle');
    _requireTextStyleMetrics(thinkingTextStyle, 'thinkingTextStyle');
    _requireTextStyleMetrics(thinkingHeadTextStyle, 'thinkingHeadTextStyle');

    _requirePositive(waitingDotDiameter, 'waitingDotDiameter');
    _requirePositive(waitingDotsHeight, 'waitingDotsHeight');

    _requireNonNegative(blockSpacing, 'blockSpacing');
    _requireNonNegative(h2SpacingBottom, 'h2SpacingBottom');
    _requireNonNegative(h3SpacingBottom, 'h3SpacingBottom');
    _requireNonNegative(listItemSpacing, 'listItemSpacing');
    _requireNonNegative(listIndent, 'listIndent');
    _requireNonNegative(codeBlockBorderRadius, 'codeBlockBorderRadius');
    _requireNonNegative(tableBorderWidth, 'tableBorderWidth');
    _requireNonNegative(quoteBorderWidth, 'quoteBorderWidth');
    _requireNonNegative(quoteIndent, 'quoteIndent');
    _requireNonNegative(thinkingFrameBorderWidth, 'thinkingFrameBorderWidth');
    _requireNonNegative(thinkingFrameIndent, 'thinkingFrameIndent');
    _requireNonNegative(
      thinkingFrameSpacingBottom,
      'thinkingFrameSpacingBottom',
    );
    _requireNonNegative(waitingDotGap, 'waitingDotGap');

    _requireInsets(codeBlockPadding, 'codeBlockPadding');
    _requireInsets(tableCellPadding, 'tableCellPadding');

    _requireOpacity(waitingDotMinOpacity, 'waitingDotMinOpacity');
    _requireOpacity(waitingDotMaxOpacity, 'waitingDotMaxOpacity');
    if (waitingDotMinOpacity > waitingDotMaxOpacity) {
      throw ArgumentError(
        'waitingDotMinOpacity ($waitingDotMinOpacity) must not exceed '
        'waitingDotMaxOpacity ($waitingDotMaxOpacity)',
      );
    }
  }

  // ── Colors ──

  final Color codeBlockBackground;
  final Color quoteBorderColor;
  final Color tableBorderColor;
  final Color tableHeaderBackground;
  final Color thinkingFrameBorderColor;
  final Color thinkingShimmerBaseColor;
  final Color thinkingShimmerHighlightColor;
  final Color waitingDotColor;

  // ── Time, clock side (read from controller.style; see class doc) ──

  /// Base interval between characters starting to reveal (40 chars/sec).
  final Duration revealInterval;

  /// Time for one character's opacity to go from 0 to 1.
  final Duration fadeDuration;

  /// Budget to clear a backlog once catch-up kicks in. If this is shorter
  /// than [revealInterval], the catch-up threshold (`catchUpBudget ÷
  /// revealInterval`) rounds down to 0, so every arriving chunk becomes a
  /// catch-up target.
  final Duration catchUpBudget;

  /// Budget to reveal the remaining characters once streaming completes.
  final Duration fastForwardBudget;

  /// The fastest interval catch-up and fast-forward may shrink to (one
  /// character per frame). Neither ever reveals characters faster than this,
  /// however large the backlog is — the backlog may stay above the catch-up
  /// threshold instead of always clearing within [catchUpBudget] /
  /// [fastForwardBudget]. Must not exceed [revealInterval] (equal is
  /// allowed).
  final Duration minRevealInterval;

  /// Time for the thinking frame's body to collapse/expand.
  final Duration thinkingCollapseDuration;

  // ── Time, Widget side (read from the nearest StreamingReplyStyleScope;
  // see class doc) ──

  /// Time for the thinking headline's shimmer to complete one pass.
  final Duration thinkingShimmerDuration;

  /// Time for one waiting dot's opacity to go trough-peak-trough.
  final Duration waitingDotDuration;

  /// Delay between the 1st, 2nd, and 3rd waiting dot's cycle.
  final Duration waitingDotStagger;

  /// Curve for the thinking frame's body collapse/expand
  /// ([thinkingCollapseDuration] sets its duration; see the time-fields
  /// split above).
  final Curve thinkingCollapseCurve;

  // ── TextStyle (per-role typography; see class doc for the merge rules) ──

  /// Body paragraph text. Merges onto the surrounding `DefaultTextStyle`
  /// ([resolveBodyTextStyle]).
  final TextStyle bodyTextStyle;

  /// `#`/`##` heading text. Merges onto the running style (body or
  /// blockquote; [resolveHeadingTextStyle]).
  final TextStyle h2TextStyle;

  /// `###`–`######` heading text. Merges onto the running style
  /// ([resolveHeadingTextStyle]).
  final TextStyle h3TextStyle;

  /// Link text. Merges onto the running style ([resolveLinkTextStyle]).
  final TextStyle linkTextStyle;

  /// Blockquote text. Merges onto the running style
  /// ([resolveQuoteTextStyle]).
  final TextStyle quoteTextStyle;

  /// Inline code (`` `x` ``) text. Merges onto the running style
  /// ([resolveInlineCodeTextStyle]).
  final TextStyle inlineCodeTextStyle;

  /// Code block (fenced) text. Merges onto the surrounding
  /// `DefaultTextStyle` ([resolveCodeBlockTextStyle]).
  final TextStyle codeBlockTextStyle;

  /// Table cell text. Merges onto the surrounding `DefaultTextStyle`
  /// ([resolveTableTextStyle]).
  final TextStyle tableTextStyle;

  /// Table header row text. Merges onto the surrounding `DefaultTextStyle`
  /// ([resolveTableHeaderTextStyle]).
  final TextStyle tableHeaderTextStyle;

  /// Thinking text. Merges onto the surrounding `DefaultTextStyle`
  /// ([resolveThinkingTextStyle]).
  final TextStyle thinkingTextStyle;

  /// Thinking frame's headline row text. Merges onto the surrounding
  /// `DefaultTextStyle` ([resolveThinkingHeadTextStyle]).
  final TextStyle thinkingHeadTextStyle;

  // ── Block spacing ──

  final double blockSpacing;
  final double h2SpacingBottom;
  final double h3SpacingBottom;
  final double listItemSpacing;
  final double listIndent;

  // ── Code block ──

  final double codeBlockBorderRadius;
  final EdgeInsets codeBlockPadding;

  // ── Table ──

  final double tableBorderWidth;
  final EdgeInsets tableCellPadding;

  // ── Blockquote ──

  final double quoteBorderWidth;
  final double quoteIndent;

  // ── Thinking frame ──

  final double thinkingFrameBorderWidth;
  final double thinkingFrameIndent;
  final double thinkingFrameSpacingBottom;

  // ── Waiting dots ──

  final double waitingDotDiameter;
  final double waitingDotGap;
  final double waitingDotsHeight;
  final double waitingDotMinOpacity;
  final double waitingDotMaxOpacity;

  // ── Defaults for the 11 TextStyle roles (also this style's own default
  // color, used to fill a merge that leaves color null; see class doc) ──

  static const List<String> _monospaceFontFamilyFallback = [
    'SFMono-Regular',
    'Consolas',
    'monospace',
  ];

  static const TextStyle _defaultBodyTextStyle = TextStyle(
    color: Color(0xFF1D2026),
    fontSize: 14,
    height: 1.75,
  );

  static const TextStyle _defaultH2TextStyle = TextStyle(
    fontSize: 16,
    height: 1.55,
    fontWeight: FontWeight.w700,
  );

  static const TextStyle _defaultH3TextStyle = TextStyle(
    fontSize: 14.5,
    height: 1.55,
    fontWeight: FontWeight.w700,
  );

  static const TextStyle _defaultLinkTextStyle = TextStyle(
    color: Color(0xFF2F62C9),
    decoration: TextDecoration.underline,
  );

  static const TextStyle _defaultQuoteTextStyle = TextStyle(
    color: Color(0xFF5B6069),
  );

  static const TextStyle _defaultInlineCodeTextStyle = TextStyle(
    color: Color(0xFF2C3340),
    fontSize: 12.5,
    fontFamily: 'Menlo',
    fontFamilyFallback: _monospaceFontFamilyFallback,
    backgroundColor: Color(0xFFEFF0F3),
  );

  static const TextStyle _defaultCodeBlockTextStyle = TextStyle(
    color: Color(0xFFE3E8F0),
    fontSize: 12,
    height: 1.62,
    fontFamily: 'Menlo',
    fontFamilyFallback: _monospaceFontFamilyFallback,
  );

  static const TextStyle _defaultTableTextStyle = TextStyle(
    color: Color(0xFF1D2026),
    fontSize: 12.5,
    height: 1.55,
  );

  static const TextStyle _defaultTableHeaderTextStyle = TextStyle(
    color: Color(0xFF1D2026),
    fontSize: 12.5,
    height: 1.55,
    fontWeight: FontWeight.w700,
  );

  static const TextStyle _defaultThinkingTextStyle = TextStyle(
    color: Color(0xFF8B9099),
    fontSize: 12.5,
    height: 1.7,
  );

  static const TextStyle _defaultThinkingHeadTextStyle = TextStyle(
    color: Color(0xFF8B9099),
    fontSize: 12,
    height: 1.7,
  );

  /// Merges [role] onto [base], then — only if that still leaves `color`
  /// null — fills it with [roleDefault]'s own color (see class doc).
  static TextStyle _resolve(
    TextStyle base,
    TextStyle role,
    TextStyle roleDefault,
  ) {
    final merged = base.merge(role);
    return merged.color == null
        ? merged.copyWith(color: roleDefault.color)
        : merged;
  }

  /// Resolves [bodyTextStyle] by merging it onto [ambient] (the surrounding
  /// `DefaultTextStyle`).
  TextStyle resolveBodyTextStyle(TextStyle ambient) =>
      _resolve(ambient, bodyTextStyle, _defaultBodyTextStyle);

  /// Resolves the heading style for [level] (`h1`-`h6`) by merging
  /// [h2TextStyle]/[h3TextStyle] onto [current] (the running style — body or
  /// blockquote — so a heading inherits its surrounding color).
  TextStyle resolveHeadingTextStyle(int level, TextStyle current) =>
      current.merge(level <= 2 ? h2TextStyle : h3TextStyle);

  /// Resolves [linkTextStyle] by merging it onto [current] (the running
  /// style).
  TextStyle resolveLinkTextStyle(TextStyle current) =>
      _resolve(current, linkTextStyle, _defaultLinkTextStyle);

  /// Resolves [quoteTextStyle] by merging it onto [current] (the running
  /// style).
  TextStyle resolveQuoteTextStyle(TextStyle current) =>
      _resolve(current, quoteTextStyle, _defaultQuoteTextStyle);

  /// Resolves [inlineCodeTextStyle] by merging it onto [current] (the
  /// running style).
  TextStyle resolveInlineCodeTextStyle(TextStyle current) =>
      _resolve(current, inlineCodeTextStyle, _defaultInlineCodeTextStyle);

  /// Resolves [codeBlockTextStyle] by merging it onto [ambient] (the
  /// surrounding `DefaultTextStyle`).
  TextStyle resolveCodeBlockTextStyle(TextStyle ambient) =>
      _resolve(ambient, codeBlockTextStyle, _defaultCodeBlockTextStyle);

  /// Resolves [tableTextStyle] by merging it onto [ambient] (the surrounding
  /// `DefaultTextStyle`).
  TextStyle resolveTableTextStyle(TextStyle ambient) =>
      _resolve(ambient, tableTextStyle, _defaultTableTextStyle);

  /// Resolves [tableHeaderTextStyle] by merging it onto [ambient] (the
  /// surrounding `DefaultTextStyle`).
  TextStyle resolveTableHeaderTextStyle(TextStyle ambient) =>
      _resolve(ambient, tableHeaderTextStyle, _defaultTableHeaderTextStyle);

  /// Resolves [thinkingTextStyle] by merging it onto [ambient] (the
  /// surrounding `DefaultTextStyle`).
  TextStyle resolveThinkingTextStyle(TextStyle ambient) =>
      _resolve(ambient, thinkingTextStyle, _defaultThinkingTextStyle);

  /// Resolves [thinkingHeadTextStyle] by merging it onto [ambient] (the
  /// surrounding `DefaultTextStyle`).
  TextStyle resolveThinkingHeadTextStyle(TextStyle ambient) =>
      _resolve(ambient, thinkingHeadTextStyle, _defaultThinkingHeadTextStyle);
}

void _requireDuration(Duration value, String name) {
  if (value <= Duration.zero) {
    throw ArgumentError.value(value, name, 'must be a positive duration');
  }
}

void _requirePositive(double value, String name) {
  if (!value.isFinite || value <= 0) {
    throw ArgumentError.value(value, name, 'must be a positive, finite number');
  }
}

void _requireNonNegative(double value, String name) {
  if (!value.isFinite || value < 0) {
    throw ArgumentError.value(
      value,
      name,
      'must be a non-negative, finite number',
    );
  }
}

void _requireInsets(EdgeInsets value, String name) {
  _requireNonNegative(value.left, '$name.left');
  _requireNonNegative(value.top, '$name.top');
  _requireNonNegative(value.right, '$name.right');
  _requireNonNegative(value.bottom, '$name.bottom');
}

void _requireOpacity(double value, String name) {
  if (!value.isFinite || value < 0 || value > 1) {
    throw ArgumentError.value(value, name, 'must be between 0 and 1');
  }
}

/// Validates a [TextStyle]'s own `fontSize`/`height` when the role's
/// `TextStyle` sets one (an unset attribute is inherited at merge time, not
/// validated here).
void _requireTextStyleMetrics(TextStyle style, String name) {
  final fontSize = style.fontSize;
  if (fontSize != null && (!fontSize.isFinite || fontSize <= 0)) {
    throw ArgumentError.value(
      fontSize,
      '$name.fontSize',
      'must be a positive, finite number',
    );
  }
  final height = style.height;
  if (height != null && (!height.isFinite || height <= 0)) {
    throw ArgumentError.value(
      height,
      '$name.height',
      'must be a positive, finite number',
    );
  }
}

/// Propagates a [StreamingReplyStyle] to descendants (block widgets, waiting
/// dots, the thinking shimmer) without threading it through every function
/// signature.
///
/// [StreamingReply], [RevealedMarkdown], and [ThinkingFrame] each install one
/// of these above their subtree, resolving their own `style` argument
/// against the nearest ancestor scope (falling back to a default
/// [StreamingReplyStyle] if none is installed, so each also works stand-alone
/// — e.g. in a test that renders it directly).
class StreamingReplyStyleScope extends InheritedWidget {
  const StreamingReplyStyleScope({
    super.key,
    required this.style,
    required super.child,
  });

  final StreamingReplyStyle style;

  static final StreamingReplyStyle _fallback = StreamingReplyStyle();

  /// The nearest ancestor [StreamingReplyStyle], or a default one if no
  /// scope is installed above [context].
  static StreamingReplyStyle of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<StreamingReplyStyleScope>();
    return scope?.style ?? _fallback;
  }

  @override
  bool updateShouldNotify(StreamingReplyStyleScope oldWidget) =>
      oldWidget.style != style;
}
