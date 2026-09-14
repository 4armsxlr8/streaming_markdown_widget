import 'package:flutter/material.dart';

import 'reply_page.dart';

/// Gemini API key from `--dart-define=GEMINI_API_KEY=...` (spec: build-time
/// only, never stored on device). Empty disables the real supply.
const _geminiApiKey = String.fromEnvironment('GEMINI_API_KEY');

/// Gemini model name from `--dart-define=GEMINI_MODEL=...`.
const _geminiModel = String.fromEnvironment(
  'GEMINI_MODEL',
  defaultValue: 'gemini-3.8-flash',
);

/// The sample's root widget.
class StreamingMarkdownWidgetApp extends StatelessWidget {
  const StreamingMarkdownWidgetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'streaming_markdown_widget',
      home: ReplyPage(apiKey: _geminiApiKey, model: _geminiModel),
    );
  }
}
