import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class AppArtworkCard extends StatelessWidget {
  final String assetName;
  final double height;
  final Alignment alignment;
  final EdgeInsetsGeometry? padding;
  final Widget? child;

  const AppArtworkCard({
    super.key,
    required this.assetName,
    required this.height,
    this.alignment = Alignment.center,
    this.padding,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            assetName,
            fit: BoxFit.cover,
            alignment: alignment,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, _, _) =>
                const ColoredBox(color: AppColors.cardSub),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.background.withValues(alpha: 0.04),
                  AppColors.background.withValues(alpha: 0.42),
                ],
              ),
            ),
          ),
          if (child != null)
            Padding(padding: padding ?? const EdgeInsets.all(14), child: child),
        ],
      ),
    );
  }
}
