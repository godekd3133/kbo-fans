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
            errorBuilder: (_, _, _) => ColoredBox(color: AppColors.cardSub),
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

class AppArtworkLayer extends StatelessWidget {
  final String assetName;
  final Alignment alignment;
  final double opacity;
  final BoxFit fit;
  final Gradient? overlay;

  const AppArtworkLayer({
    super.key,
    required this.assetName,
    this.alignment = Alignment.center,
    this.opacity = 0.22,
    this.fit = BoxFit.cover,
    this.overlay,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Opacity(
          opacity: opacity,
          child: Image.asset(
            assetName,
            fit: fit,
            alignment: alignment,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, _, _) => ColoredBox(color: AppColors.cardSub),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient:
                overlay ??
                LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  stops: const [0, 0.54, 1],
                  colors: [
                    AppColors.background.withValues(alpha: 0.74),
                    AppColors.background.withValues(alpha: 0.38),
                    AppColors.background.withValues(alpha: 0.86),
                  ],
                ),
          ),
        ),
      ],
    );
  }
}

class AppArtworkBackdrop extends StatelessWidget {
  final String assetName;
  final Widget child;
  final Alignment alignment;
  final EdgeInsetsGeometry padding;
  final BorderRadiusGeometry borderRadius;
  final double opacity;
  final Gradient? overlay;

  const AppArtworkBackdrop({
    super.key,
    required this.assetName,
    required this.child,
    this.alignment = Alignment.center,
    this.padding = EdgeInsets.zero,
    this.borderRadius = BorderRadius.zero,
    this.opacity = 0.22,
    this.overlay,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: Stack(
        children: [
          Positioned.fill(
            child: AppArtworkLayer(
              assetName: assetName,
              alignment: alignment,
              opacity: opacity,
              overlay: overlay,
            ),
          ),
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}
