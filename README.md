# streaming_markdown_widget

![Demo](doc/demo.gif)

A Flutter package that reveals streaming Markdown one character at a time while keeping it formatted, with a collapsible thinking frame above the reply. Built for AI chat screens where the reply arrives a few characters at a time and still has to render as headings, lists, code blocks, and tables while it's receiving.

## Installation

Local reference:

```yaml
dependencies:
  streaming_markdown_widget:
    path: /path/to/streaming_markdown_widget
```

pub.dev reference:

```yaml
dependencies:
  streaming_markdown_widget: ^0.1.0
```

## Usage

Create a `StreamingReplyController` and pass it to `StreamingReply`. The controller drives both the thinking frame and the reply below it.

```dart
final controller = StreamingReplyController();

StreamingReply(controller: controller)
```

Dispose the controller when you're done with it (typically in `State.dispose`):

```dart
@override
void dispose() {
  controller.dispose();
  super.dispose();
}
```

## Delivering chunks

Feed the controller by hand with `addChunk` and finish with `complete`:

```dart
controller.addChunk(const Chunk('...', kind: ChunkKind.thinking));
controller.addChunk(const Chunk('## Answer\n\nHello'));
controller.complete();
```

Or connect a `Stream<Chunk>` with `attach`, which calls `addChunk` for every event and `complete` when the stream ends:

```dart
controller.attach(
  replyStream,
  onError: (error, stackTrace) {
    // complete() has already been called; show `error` however you like.
  },
);
```

A controller accepts only one `attach` call (a second one throws `StateError`); calling `addChunk` by hand afterward still works. To stream a reply again, create a new `StreamingReplyController` — a completed or attached one is done.

## Connecting a real API

The package only consumes `Stream<Chunk>`; how you produce it is up to you. `example/lib/src/gemini_reply_source.dart`'s `geminiReplyStream` is the reference shape: it posts to Gemini's `streamGenerateContent` SSE endpoint and turns every part of the response into a `Chunk`, tagging thought parts as `ChunkKind.thinking` and the rest as `ChunkKind.reply`. Anthropic and OpenAI's streaming endpoints fit the same shape — convert each provider's stream events into `Chunk`s and hand the resulting `Stream<Chunk>` to `attach`.

## Using the parts separately

`RevealedMarkdown` (the revealed text) and `ThinkingFrame` (the collapsible frame) both read a `StreamingReplyController` directly, so either works standalone without `StreamingReply`:

```dart
RevealedMarkdown(controller: controller, kind: ChunkKind.reply)
```

```dart
ThinkingFrame(controller: controller)
```

Share one controller between them to build your own layout in place of `StreamingReply`.

## Replacing block widgets

Pass `blockBuilders` to `RevealedMarkdown` to replace how one or more block kinds are drawn; kinds you don't list keep the default widget:

```dart
RevealedMarkdown(
  controller: controller,
  kind: ChunkKind.reply,
  blockBuilders: {
    MarkdownBlockKind.codeBlock: (context, block) => MyCodeBlock(
      text: block.text,
      language: block.language,
    ),
  },
)
```

The `MarkdownBlock` your builder receives carries the block's revealed text (`text`) and which of its characters are still mid-reveal (`revealing`, with each character's position and opacity) — plus kind-specific fields such as `level`, `spans`, `items`, or `headerCells`. To match the default fade-in exactly, run your own `TextSpan` through `applyReveal(span, block.revealing)` before drawing it.

For a bullet/numbered list or a table, `block.revealing`'s positions run over the whole block (every item, or every cell), not just the one item/cell your builder draws. Work out that item's/cell's own `start` (a list item carries it as `MarkdownBlockListItem.start`; a table cell's is the summed `inlineSpansLength` of every earlier cell, header row first) and `length` (`inlineSpansLength` of its own spans), then narrow `block.revealing` to that range with `revealingSlice(block.revealing, start: start, length: length)` before passing the result to `applyReveal`.

## Closing partial Markdown

`closePartialMarkdown` is the standalone preprocessing step `RevealedMarkdown` uses internally: given a partially-received Markdown string, it closes whatever notation is left open (unclosed `**`, an open code fence, an in-progress table row) so the result parses cleanly.

```dart
closePartialMarkdown('some **bold te'); // 'some **bold te**'
closePartialMarkdown(fullText, complete: true);
```

Pass `complete: true` once receiving has finished, for the same text you'd otherwise pass with the default `complete: false`.

## Thinking frame text and seconds

`thinkingTitle` (shown while thinking is streaming) and `thoughtForSeconds` (builds the headline once it's done, given the measured seconds) are both settable on `StreamingReply` and `ThinkingFrame`:

```dart
StreamingReply(
  controller: controller,
  thinkingTitle: 'Thinking…',
  thoughtForSeconds: (seconds) => 'Thought for ${seconds}s',
)
```

Leaving `thoughtForSeconds` unset keeps showing `thinkingTitle` even after thinking ends. To override the measured value shown to `thoughtForSeconds` (for example, to keep a demo deterministic), set `controller.thinkingSecondsOverride`; set it back to `null` to return to the measured value.

## Accessibility

The text a screen reader gets for the reply and for the thinking frame is always the full text received so far, including characters that haven't visually revealed yet — so accessibility isn't limited by how far the animation has progressed. The thinking frame's headline row is exposed as a button and toggles the frame (line ⇄ full while thinking, collapsed ⇄ full afterward) via the same semantics action a tap uses. Nothing is marked as a live region, so nothing is announced automatically while receiving.

## Style

`StreamingReplyStyle` holds every look-and-feel and timing value. It's not `const`-constructible — the constructor validates every value and throws `ArgumentError` on an invalid one (see [Invalid values](#invalid-values)).

Pass it in two places: to `StreamingReplyController(style:)` for the reveal timing (`revealInterval`, `fadeDuration`, `catchUpBudget`, `fastForwardBudget`, `minRevealInterval`, `thinkingCollapseDuration`), and to `StreamingReply`/`RevealedMarkdown`/`ThinkingFrame`'s `style:` for everything else (colors, typography, spacing, shimmer/waiting-dot timing, the thinking frame's collapse curve (`thinkingCollapseCurve`)). These are two separate instances — the time values shown on screen (the fade-in speed, the thinking frame's collapse animation, and so on) are read from the instance passed to the controller (`controller.style`); the same-named time fields on the Widget-side `style` are ignored. Pass the same values to both (or share one instance) so the two stay in sync.

```dart
final style = StreamingReplyStyle(revealInterval: Duration(milliseconds: 20));

final controller = StreamingReplyController(style: style);
StreamingReply(controller: controller, style: style);
```

Typography is passed as 11 per-role `TextStyle`s instead of separate size/weight/color fields — `bodyTextStyle`, `h2TextStyle`, `h3TextStyle`, `linkTextStyle`, `quoteTextStyle`, `inlineCodeTextStyle`, `codeBlockTextStyle`, `tableTextStyle`, `tableHeaderTextStyle`, `thinkingTextStyle`, `thinkingHeadTextStyle`. Each is kept exactly as passed (no attribute you leave unset is filled in ahead of time) and is merged at build time onto a base style — the app's own `DefaultTextStyle` for body/thinking/code block/table/thinking-headline text, or the running style built up while descending the Markdown tree for headings/blockquote/link/inline code (so a heading inside a blockquote inherits the blockquote's color, for instance). Any attribute a role's `TextStyle` does not set — font family, letter spacing, weight, and so on — is inherited from that base instead of falling back to a package default. If the merge still leaves `color` null, it is filled with that role's own default color (a revealing character draws its progress as the alpha of its style's color, so a null one could never make an appearance).

```dart
StreamingReply(
  controller: controller,
  style: StreamingReplyStyle(
    bodyTextStyle: Theme.of(context).textTheme.bodyMedium!,
  ),
);
```

The package does not know about Material — copy over a `TextTheme` value like this at the call site rather than passing `Theme.of(context).textTheme` itself.

## Invalid values

`StreamingReplyStyle` throws `ArgumentError` at construction time for:

- a non-positive `revealInterval` / `fadeDuration` / `catchUpBudget` / `fastForwardBudget` / `minRevealInterval` / `thinkingCollapseDuration` / `thinkingShimmerDuration` / `waitingDotDuration` / `waitingDotStagger`, or a `minRevealInterval` longer than `revealInterval`
- a non-positive or non-finite `fontSize` or `height` set on one of the 11 per-role `TextStyle`s (an unset one is inherited at merge time instead, so it is not validated)
- a non-positive or non-finite diameter or height (e.g. `waitingDotDiameter`, `waitingDotsHeight`)
- a negative or non-finite margin, spacing, radius, border width, or indent (e.g. `blockSpacing`, `codeBlockBorderRadius`, `quoteBorderWidth`)
- `waitingDotMinOpacity` / `waitingDotMaxOpacity` outside 0–1, or `waitingDotMinOpacity` above `waitingDotMaxOpacity`

Zero margins and 0/1 opacities are valid.

## Running the example

```sh
flutter run -d "iPhone 16" --dart-define-from-file=.env.local
```

Both values are for local development only — never distribute a build with a key baked in. Prefer `--dart-define-from-file=.env.local` (a gitignored file, `GEMINI_API_KEY=...` and optionally `GEMINI_MODEL=...` on their own lines) over an inline `--dart-define=GEMINI_API_KEY=...`, which stays in your shell history. Without a key, sending shows your typed question in the bubble with the fake supply's sample reply; replaying plays the sample question and reply again from the start. A key can also be entered at runtime through the AppBar's key icon — that copy lives in memory only (never written to disk, cleared when the app closes) and never shown on screen; clearing it there switches sending back to the fake supply. With a key set, sending goes once to Gemini and replay resends the last question; if Gemini's `finishReason` ever comes back as anything other than `STOP` (a safety block, `MAX_TOKENS`, …), the reply ends with whatever arrived and the screen shows an error line instead.

## Limitations

- The package does not scroll; if you want to follow the tail, do it in your own scroll view.
- Not formatted (rendered as literal characters): math, images, footnotes, strikethrough, task lists, and raw HTML.
- No syntax highlighting or copy button on code blocks, no tapping links, no text selection.
- iOS and Android only — not verified on macOS or web.
- No dark theme (`StreamingReplyStyle` is a single fixed palette).
- No chat bubble — that's example/screen-level styling, not part of the package.
