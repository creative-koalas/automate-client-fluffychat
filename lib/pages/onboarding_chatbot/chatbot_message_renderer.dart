import 'package:flutter/material.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

class ChatbotMessageRenderer extends StatelessWidget {
  final String text;
  final Color textColor;
  final double fontSize;
  final TextStyle linkStyle;
  final bool isUser;

  const ChatbotMessageRenderer({
    super.key,
    required this.text,
    required this.textColor,
    this.fontSize = 16.0,
    required this.linkStyle,
    this.isUser = false,
  });

  static const Set<String> allowedHtmlTags = {
    'font', 'del', 's', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'blockquote', 'p', 'a',
    'ul', 'ol', 'sup', 'sub', 'li', 'b', 'i', 'u', 'strong', 'em', 'strike', 'code',
    'hr', 'br', 'div', 'table', 'thead', 'tbody', 'tr', 'th', 'td', 'pre', 'span',
  };

  static const Set<String> blockHtmlTags = {
    'p', 'ul', 'ol', 'pre', 'div', 'table', 'blockquote',
  };

  static const Set<String> fullLineHtmlTag = {
    'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'li',
  };

  List<InlineSpan> _renderWithLineBreaks(dom.NodeList nodes, BuildContext context, {int depth = 1}) {
    final onlyElements = nodes.whereType<dom.Element>().toList();
    return [
      for (var i = 0; i < nodes.length; i++) ...[
        _renderHtml(nodes[i], context, depth: depth + 1),
        if (nodes[i] is dom.Element &&
            onlyElements.indexOf(nodes[i] as dom.Element) < onlyElements.length - 1) ...[
          if (blockHtmlTags.contains((nodes[i] as dom.Element).localName))
            const TextSpan(text: '\n\n'),
          if (fullLineHtmlTag.contains((nodes[i] as dom.Element).localName))
            const TextSpan(text: '\n'),
        ],
      ],
    ];
  }

  Widget _renderTable(dom.Node tableNode, BuildContext context) {
    final rows = <TableRow>[];
    
    // Find all 'tr' elements, searching recursively in thead/tbody if needed or direct children
    final trs = <dom.Element>[];
    
    void findTrs(dom.Node node) {
      if (node is dom.Element && node.localName == 'tr') {
        trs.add(node);
        return; // Don't look inside tr for more trs
      }
      if (node.nodes.isNotEmpty) {
        for (var child in node.nodes) {
          findTrs(child);
        }
      }
    }
    
    findTrs(tableNode);

    for (final tr in trs) {
      final cells = <Widget>[];
      for (final cell in tr.nodes) {
        if (cell is dom.Element && (cell.localName == 'td' || cell.localName == 'th')) {
          final isHeader = cell.localName == 'th';
          cells.add(
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text.rich(
                TextSpan(
                  children: _renderWithLineBreaks(cell.nodes, context),
                  style: TextStyle(
                    fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
                    color: textColor,
                    fontSize: fontSize,
                  ),
                ),
              ),
            ),
          );
        }
      }
      if (cells.isNotEmpty) {
        rows.add(TableRow(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: textColor.withValues(alpha: 0.1))),
            color: rows.length % 2 == 0 ? Colors.transparent : textColor.withValues(alpha: 0.03),
          ),
          children: cells,
        ),);
      }
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: textColor.withValues(alpha: 0.1)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          children: rows,
        ),
      ),
    );
  }

  InlineSpan _renderHtml(dom.Node node, BuildContext context, {int depth = 1}) {
    if (depth >= 100) return const TextSpan();

    if (node is! dom.Element) {
      var text = node.text ?? '';
      if (text == '\n') text = '';
      return LinkifySpan(
        text: text,
        options: const LinkifyOptions(humanize: false),
        linkStyle: linkStyle,
        onOpen: (link) async {
          if (await canLaunchUrl(Uri.parse(link.url))) {
            await launchUrl(Uri.parse(link.url));
          }
        },
      );
    }

    if (!allowedHtmlTags.contains(node.localName)) return const TextSpan();

    switch (node.localName) {
      case 'br':
        return const TextSpan(text: '\n');
      case 'a':
        final href = node.attributes['href'];
        if (href == null) return TextSpan(text: node.text);
        return WidgetSpan(
          child: InkWell(
            onTap: () async {
              if (await canLaunchUrl(Uri.parse(href))) {
                await launchUrl(Uri.parse(href));
              }
            },
            child: Text.rich(
              TextSpan(
                children: _renderWithLineBreaks(node.nodes, context, depth: depth),
                style: linkStyle,
              ),
            ),
          ),
        );
      case 'li':
        return WidgetSpan(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (node.parent?.localName == 'ul')
                Padding(
                  padding: EdgeInsets.only(left: fontSize, right: 4),
                  child: Text('•', style: TextStyle(fontSize: fontSize, color: textColor)),
                ),
              if (node.parent?.localName == 'ol')
                Padding(
                   padding: EdgeInsets.only(left: fontSize, right: 4),
                   child: Text('${(node.parent?.nodes.whereType<dom.Element>().toList().indexOf(node) ?? 0) + 1}.', style: TextStyle(fontSize: fontSize, color: textColor)),
                ),
              Flexible(
                child: Text.rich(
                  TextSpan(
                    children: _renderWithLineBreaks(node.nodes, context, depth: depth),
                    style: TextStyle(fontSize: fontSize, color: textColor),
                  ),
                ),
              ),
            ],
          ),
        );
      case 'blockquote':
        return WidgetSpan(
          child: Container(
            padding: const EdgeInsets.only(left: 8.0),
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: textColor.withValues(alpha: 0.5), width: 4)),
            ),
            child: Text.rich(
              TextSpan(
                children: _renderWithLineBreaks(node.nodes, context, depth: depth),
              ),
              style: TextStyle(fontStyle: FontStyle.italic, fontSize: fontSize, color: textColor),
            ),
          ),
        );
      case 'table':
        return WidgetSpan(
          child: _renderTable(node, context),
        );
      case 'code':
         // Inline code or block code
         final isInline = node.parent?.localName != 'pre';
         final codeText = node.text;
         if (isInline) {
           return WidgetSpan(
             alignment: PlaceholderAlignment.middle,
             child: Container(
               padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
               decoration: BoxDecoration(
                 color: isUser ? Colors.black12 : Colors.grey.withValues(alpha: 0.2),
                 borderRadius: BorderRadius.circular(4),
               ),
               child: Text(
                 codeText,
                 style: TextStyle(
                   fontFamily: 'monospace',
                   fontSize: fontSize * 0.9,
                   color: textColor,
                 ),
               ),
             ),
           );
         } else {
           // Block code
           return WidgetSpan(
             child: Container(
               width: double.infinity,
               margin: const EdgeInsets.symmetric(vertical: 8),
               padding: const EdgeInsets.all(12),
               decoration: BoxDecoration(
                 color: const Color(0xFF2b2b2b), // Dark gray
                 borderRadius: BorderRadius.circular(4), // Slightly rounded
               ),
               child: SingleChildScrollView(
                 scrollDirection: Axis.horizontal,
                 child: Text(
                   codeText.trim(),
                   style: TextStyle(
                     fontFamily: 'monospace',
                     fontSize: fontSize * 0.9,
                     color: const Color(0xFFa9b7c6), // Light gray text
                   ),
                 ),
               ),
             ),
           );
         }
      default:
        return TextSpan(
          style: switch (node.localName) {
            'strong' || 'b' => const TextStyle(fontWeight: FontWeight.bold),
            'em' || 'i' => const TextStyle(fontStyle: FontStyle.italic),
            'u' => const TextStyle(decoration: TextDecoration.underline),
            'del' || 's' => const TextStyle(decoration: TextDecoration.lineThrough),
            'h1' => TextStyle(fontSize: fontSize * 1.5, fontWeight: FontWeight.bold),
            'h2' => TextStyle(fontSize: fontSize * 1.4, fontWeight: FontWeight.bold),
            'h3' => TextStyle(fontSize: fontSize * 1.3, fontWeight: FontWeight.bold),
            _ => null,
          },
          children: _renderWithLineBreaks(node.nodes, context, depth: depth),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Convert Markdown to HTML
    final html = md.markdownToHtml(text);
    final element = parser.parse(html).body ?? dom.Element.html('');
    
    return Text.rich(
      TextSpan(children: _renderWithLineBreaks(element.nodes, context)),
      style: TextStyle(fontSize: fontSize, color: textColor, height: 1.5),
    );
  }
}
