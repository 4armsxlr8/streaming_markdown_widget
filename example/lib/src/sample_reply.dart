/// The default values for the fake reply (the question, thinking, and body
/// text [ReplyPage] runs at launch, and replays whenever the API key is
/// empty).
///
/// Transcribed from the `many` state of mock.html (`#variant=G`), trimmed so
/// [sampleThinking] plus [sampleReply] stays at or under 480 raw characters
/// (AC-27's cap is 500; writing out the mock's English verbatim comes to 612,
/// so the link's URL is shortened and a couple of list/table rows are
/// dropped — the heading and every other block kind are kept).
library;

/// The question shown in the question bubble at launch, and again on
/// replay if nothing has been sent yet. Sending — even without an API
/// key — always puts the typed question in the bubble instead; only the
/// reply comes from the fake supply in that case.
const String sampleQuestion =
    'How do I make a long list scroll smoothly in Flutter?';

/// The fake thinking text. One line, no markup.
const String sampleThinking =
    'Lazy building, fixed row heights, then how to verify in DevTools.';

/// The fake reply. Contains a heading, paragraphs, bold text, inline code,
/// a bullet list, a numbered list, a 2-column table, a code block, a
/// blockquote, and a link.
const String sampleReply = '''
## Smooth long lists

Build **only visible rows** with `ListView.builder`.

- Keep row heights equal
- Use `const` widgets

1. Switch to `ListView.builder`
2. Fix height with `itemExtent`

| Option | Effect |
|---|---|
| `itemExtent` | No measuring |

```dart
ListView.builder(itemExtent: 72)
```

> Equal heights keep scrolling cheap.

See the [perf guide](https://docs.flutter.dev/perf).''';
