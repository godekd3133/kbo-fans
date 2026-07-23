import 'package:flutter/material.dart';

class AppPageFrame extends StatelessWidget {
  final Widget child;
  final double? maxWidth;
  final EdgeInsetsGeometry padding;

  const AppPageFrame({
    super.key,
    required this.child,
    this.maxWidth,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final effectiveMaxWidth =
        maxWidth ?? (viewportWidth >= 700 ? 720.0 : 430.0);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: effectiveMaxWidth),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
