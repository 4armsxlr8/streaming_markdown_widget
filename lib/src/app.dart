import 'package:flutter/material.dart';

import 'reply_page.dart';

/// サンプルのルート Widget。
class StreamingMarkdownWidgetApp extends StatelessWidget {
  const StreamingMarkdownWidgetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'streaming_markdown_widget',
      home: ReplyPage(),
    );
  }
}
