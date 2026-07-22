import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

/// Rendered Markdown preview — headings, lists, links, code blocks, etc.
/// shown as formatted output instead of raw ## / ** syntax.
class MarkdownPreviewScreen extends StatelessWidget {
  final String content;
  final String title;

  const MarkdownPreviewScreen({super.key, required this.content, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Preview: $title', overflow: TextOverflow.ellipsis)),
      body: SafeArea(
        child: Markdown(
          data: content,
          selectable: true,
          padding: const EdgeInsets.all(16),
        ),
      ),
    );
  }
}
