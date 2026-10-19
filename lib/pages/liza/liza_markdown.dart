// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: показ Markdown в ответах Лизы: заголовки, списки, цитаты, таблицы, ссылки,
// код с подсветкой и кнопкой «копировать». Лёгкая собственная реализация на пакете markdown.

import 'package:dvchat/utils/code_highlight_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:highlight/highlight.dart' show Node, highlight;
import 'package:markdown/markdown.dart' as md;
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

class LizaMarkdown extends StatefulWidget {
  final String data;
  final TextStyle? style;
  const LizaMarkdown({super.key, required this.data, this.style});

  @override
  State<LizaMarkdown> createState() => _LizaMarkdownState();
}

class _LizaMarkdownState extends State<LizaMarkdown> {
  final List<TapGestureRecognizer> _recognizers = [];

  static const Set<String> _blockTags = {
    'p',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'pre',
    'ul',
    'ol',
    'blockquote',
    'hr',
    'table',
  };

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final theme = Theme.of(context);
    final base = widget.style ?? theme.textTheme.bodyLarge ?? const TextStyle();
    final nodes = md.Document(
      extensionSet: md.ExtensionSet.gitHubFlavored,
      encodeHtml: false,
    ).parseLines(widget.data.replaceAll('\r\n', '\n').split('\n'));
    final blocks = _blocks(nodes, base, theme);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < blocks.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          blocks[i],
        ],
      ],
    );
  }

  List<Widget> _blocks(List<md.Node> nodes, TextStyle style, ThemeData theme) {
    final out = <Widget>[];
    final inline = <md.Node>[];

    void flush() {
      if (inline.isEmpty) return;
      final spans = _spans(List.of(inline), style, theme);
      inline.clear();
      if (spans.isNotEmpty) {
        out.add(Text.rich(TextSpan(children: spans), style: style));
      }
    }

    for (final node in nodes) {
      if (node is md.Element && _blockTags.contains(node.tag)) {
        flush();
        out.add(_block(node, style, theme));
      } else {
        inline.add(node);
      }
    }
    flush();
    return out;
  }

  Widget _block(md.Element e, TextStyle style, ThemeData theme) {
    final tag = e.tag;
    final kids = e.children ?? const <md.Node>[];
    if (tag == 'p') {
      return Text.rich(
        TextSpan(children: _spans(kids, style, theme)),
        style: style,
      );
    }
    if (tag.length == 2 && tag.startsWith('h')) {
      final scale = switch (tag) {
        'h1' => 1.5,
        'h2' => 1.35,
        'h3' => 1.2,
        'h4' => 1.1,
        _ => 1.0,
      };
      final headStyle = style.copyWith(
        fontWeight: FontWeight.bold,
        fontSize: (style.fontSize ?? 16) * scale,
      );
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text.rich(
          TextSpan(children: _spans(kids, headStyle, theme)),
          style: headStyle,
        ),
      );
    }
    if (tag == 'pre') {
      md.Element? codeElement;
      for (final c in kids) {
        if (c is md.Element && c.tag == 'code') {
          codeElement = c;
          break;
        }
      }
      String? language;
      final cls = codeElement?.attributes['class'];
      if (cls != null && cls.startsWith('language-')) {
        language = cls.substring(9).toLowerCase();
      }
      final code = (codeElement ?? e).textContent.trimRight();
      return _CodeBlock(code: code, language: language);
    }
    if (tag == 'ul' || tag == 'ol') {
      return _list(e, tag == 'ol', style, theme);
    }
    if (tag == 'blockquote') {
      return Container(
        padding: const EdgeInsets.only(left: 10),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: theme.colorScheme.primary, width: 3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: _blocks(
            kids,
            style.copyWith(color: theme.colorScheme.outline),
            theme,
          ),
        ),
      );
    }
    if (tag == 'hr') return const Divider(height: 16);
    if (tag == 'table') return _table(e, style, theme);
    return Text.rich(
      TextSpan(children: _spans(kids, style, theme)),
      style: style,
    );
  }

  Widget _list(md.Element e, bool ordered, TextStyle style, ThemeData theme) {
    final items = (e.children ?? const <md.Node>[])
        .whereType<md.Element>()
        .where((c) => c.tag == 'li')
        .toList();
    final start = int.tryParse(e.attributes['start'] ?? '') ?? 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: ordered ? 28 : 18,
                  child: Text(ordered ? '${start + i}.' : '•', style: style),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: _blocks(
                      items[i].children ?? const <md.Node>[],
                      style,
                      theme,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _table(md.Element e, TextStyle style, ThemeData theme) {
    final rows = <List<md.Element>>[];
    for (final section
        in (e.children ?? const <md.Node>[]).whereType<md.Element>()) {
      for (final tr
          in (section.children ?? const <md.Node>[]).whereType<md.Element>()) {
        if (tr.tag != 'tr') continue;
        rows.add(
          (tr.children ?? const <md.Node>[]).whereType<md.Element>().toList(),
        );
      }
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    final columns = rows
        .map((r) => r.length)
        .fold<int>(0, (a, b) => a > b ? a : b);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        border: TableBorder.all(color: theme.colorScheme.outlineVariant),
        children: [
          for (final row in rows)
            TableRow(
              children: [
                for (var i = 0; i < columns; i++)
                  if (i < row.length)
                    Padding(
                      padding: const EdgeInsets.all(6),
                      child: Text.rich(
                        TextSpan(
                          children: _spans(
                            row[i].children ?? const <md.Node>[],
                            row[i].tag == 'th'
                                ? style.copyWith(fontWeight: FontWeight.bold)
                                : style,
                            theme,
                          ),
                        ),
                        style: style,
                      ),
                    )
                  else
                    const SizedBox.shrink(),
              ],
            ),
        ],
      ),
    );
  }

  List<InlineSpan> _spans(
    List<md.Node> nodes,
    TextStyle style,
    ThemeData theme,
  ) {
    final out = <InlineSpan>[];
    for (final node in nodes) {
      if (node is md.Text) {
        out.add(TextSpan(text: node.text));
        continue;
      }
      if (node is! md.Element) continue;
      final kids = node.children ?? const <md.Node>[];
      switch (node.tag) {
        case 'strong':
        case 'b':
          out.add(
            TextSpan(
              children: _spans(kids, style, theme),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          );
        case 'em':
        case 'i':
          out.add(
            TextSpan(
              children: _spans(kids, style, theme),
              style: const TextStyle(fontStyle: FontStyle.italic),
            ),
          );
        case 'del':
        case 's':
          out.add(
            TextSpan(
              children: _spans(kids, style, theme),
              style: const TextStyle(decoration: TextDecoration.lineThrough),
            ),
          );
        case 'code':
          out.add(
            TextSpan(
              text: node.textContent,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: (style.fontSize ?? 16) * 0.92,
                backgroundColor: theme.colorScheme.onSurface.withValues(
                  alpha: 0.1,
                ),
              ),
            ),
          );
        case 'a':
          {
            final href = node.attributes['href'];
            final uri = href == null ? null : Uri.tryParse(href);
            TapGestureRecognizer? recognizer;
            if (uri != null &&
                (uri.scheme == 'http' ||
                    uri.scheme == 'https' ||
                    uri.scheme == 'mailto')) {
              recognizer = TapGestureRecognizer()
                ..onTap = () =>
                    launchUrl(uri, mode: LaunchMode.externalApplication);
              _recognizers.add(recognizer);
            }
            out.add(
              TextSpan(
                children: _spans(kids, style, theme),
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  decoration: TextDecoration.underline,
                ),
                recognizer: recognizer,
              ),
            );
          }
        case 'br':
          out.add(const TextSpan(text: '\n'));
        case 'img':
          out.add(TextSpan(text: node.attributes['alt'] ?? ''));
        case 'input':
          out.add(
            TextSpan(
              text: node.attributes.containsKey('checked') ? '☑ ' : '☐ ',
            ),
          );
        default:
          out.addAll(_spans(kids, style, theme));
      }
    }
    return out;
  }
}

class _CodeBlock extends StatelessWidget {
  final String code;
  final String? language;
  const _CodeBlock({required this.code, this.language});

  static List<TextSpan> _convert(List<Node> nodes) {
    final spans = <TextSpan>[];
    for (final node in nodes) {
      final style = node.className == null
          ? null
          : atomOneDarkTheme[node.className];
      final children = node.children;
      if (node.value != null) {
        spans.add(TextSpan(text: node.value, style: style));
      } else if (children != null) {
        spans.add(TextSpan(children: _convert(children), style: style));
      }
    }
    return spans;
  }

  List<TextSpan> _spans() {
    final lang = language;
    if (lang != null && lang.isNotEmpty) {
      try {
        final nodes = highlight.parse(code, language: lang).nodes;
        if (nodes != null) return _convert(nodes);
      } catch (_) {}
    }
    return [TextSpan(text: code)];
  }

  @override
  Widget build(BuildContext context) {
    final lang = language;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: atomOneBackgroundColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 2, 4, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    (lang == null || lang.isEmpty) ? 'код' : lang,
                    style: const TextStyle(
                      color: Color(0xff5c6370),
                      fontSize: 12,
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Копировать',
                  icon: const Icon(
                    Icons.copy,
                    size: 16,
                    color: hightlightTextColor,
                  ),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: code));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Скопировано'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Text.rich(
              TextSpan(
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  color: hightlightTextColor,
                ),
                children: _spans(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
