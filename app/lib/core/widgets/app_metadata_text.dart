import 'package:flutter/material.dart';

/// Render independently meaningful metadata as a wrapping layout, not a sentence
/// separated by punctuation. API payloads retain their original text contract.
class AppMetadataText extends StatelessWidget {
  final String data;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool? softWrap;

  const AppMetadataText(
    this.data, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.softWrap,
  });

  @override
  Widget build(BuildContext context) {
    final items = metadataItems(data);
    if (items.length < 2) {
      return Text(
        items.isEmpty ? '' : items.single,
        style: style,
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: overflow,
        softWrap: softWrap,
      );
    }
    return Semantics(
      label: items.join(', '),
      excludeSemantics: true,
      child: Wrap(
        spacing: 12,
        runSpacing: 6,
        alignment: textAlign == TextAlign.center
            ? WrapAlignment.center
            : textAlign == TextAlign.end || textAlign == TextAlign.right
            ? WrapAlignment.end
            : WrapAlignment.start,
        children: [
          for (final item in items) Text(item, style: style, softWrap: true),
        ],
      ),
    );
  }
}

List<String> metadataItems(String value) => value
    .split(RegExp(r'\s*•\s*|\s+·\s+'))
    .map((item) => item.trim())
    .where((item) => item.isNotEmpty)
    .toList(growable: false);
