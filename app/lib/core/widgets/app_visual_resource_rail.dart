import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class AppVisualResourceRail extends StatelessWidget {
  final List<String> assets;
  final double height;
  final EdgeInsetsGeometry padding;
  final String semanticLabel;

  const AppVisualResourceRail({
    super.key,
    required this.assets,
    this.height = 54,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
    this.semanticLabel = '야구 비주얼 리소스',
  });

  @override
  Widget build(BuildContext context) {
    if (assets.isEmpty) {
      return const SizedBox.shrink();
    }

    final itemWidth = height * 16 / 9;
    return Semantics(
      label: semanticLabel,
      child: SizedBox(
        height: height,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: padding,
          physics: const BouncingScrollPhysics(),
          itemCount: assets.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            return ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: itemWidth,
                decoration: BoxDecoration(
                  color: AppColors.card,
                  border: Border.all(color: AppColors.divider),
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.asset(
                  assets[index],
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.low,
                  errorBuilder: (_, _, _) =>
                      const ColoredBox(color: AppColors.cardSub),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
