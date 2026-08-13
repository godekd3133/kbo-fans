import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_motion.dart';

enum RecordsAreaSection { standings, records }

class RecordsAreaSwitcher extends StatelessWidget {
  final RecordsAreaSection selected;
  final ValueChanged<RecordsAreaSection>? onSelected;

  const RecordsAreaSwitcher({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Container(
      key: const ValueKey('records-area-switcher'),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.divider),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _RecordsAreaTab(
                section: RecordsAreaSection.standings,
                label: '순위표',
                selected: selected == RecordsAreaSection.standings,
                onTap: onSelected,
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: _RecordsAreaTab(
                section: RecordsAreaSection.records,
                label: '선수 기록',
                selected: selected == RecordsAreaSection.records,
                onTap: onSelected,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordsAreaTab extends StatelessWidget {
  final RecordsAreaSection section;
  final String label;
  final bool selected;
  final ValueChanged<RecordsAreaSection>? onTap;

  const _RecordsAreaTab({
    required this.section,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    return AppPressable(
      key: ValueKey('records-area-tab-${section.name}'),
      semanticLabel: label,
      semanticHint: selected ? '현재 화면' : '$label 화면으로 이동',
      semanticSelected: selected,
      onTap: selected || onTap == null ? null : () => onTap!(section),
      child: AnimatedContainer(
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? colors.live.withValues(alpha: 0.16)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: selected
                ? colors.live.withValues(alpha: 0.72)
                : Colors.transparent,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          maxLines: 2,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: selected ? colors.textPrimary : colors.textSecondary,
            fontSize: 13,
            height: 1.15,
            fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
