import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/game_status_label.dart';
import '../../data/models/game.dart';

class GameStatusBadge extends StatelessWidget {
  final String label;
  final Color backgroundColor;
  final Color textColor;
  final EdgeInsetsGeometry padding;
  final double fontSize;

  const GameStatusBadge({
    super.key,
    required this.label,
    required this.backgroundColor,
    required this.textColor,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    this.fontSize = 11,
  });

  factory GameStatusBadge.forGame(
    GameStatus status, {
    Key? key,
    String? statusLabel,
    EdgeInsetsGeometry padding = const EdgeInsets.symmetric(
      horizontal: 8,
      vertical: 3,
    ),
    double fontSize = 11,
  }) {
    final label = labelForGameStatus(status, statusLabel: statusLabel);
    final colors = _colorsForStatus(label);
    return GameStatusBadge(
      key: key,
      label: label,
      backgroundColor: colors.$1,
      textColor: colors.$2,
      padding: padding,
      fontSize: fontSize,
    );
  }

  factory GameStatusBadge.forSchedule(
    String status, {
    Key? key,
    String? statusLabel,
    EdgeInsetsGeometry padding = const EdgeInsets.symmetric(
      horizontal: 8,
      vertical: 3,
    ),
    double fontSize = 11,
  }) {
    final label = labelForScheduleStatus(status, statusLabel: statusLabel);
    final colors = _colorsForStatus(label);
    return GameStatusBadge(
      key: key,
      label: label,
      backgroundColor: colors.$1,
      textColor: colors.$2,
      padding: padding,
      fontSize: fontSize,
    );
  }

  static (Color, Color) _colorsForStatus(String label) {
    switch (label) {
      case '경기 중':
        return (AppColors.live.withValues(alpha: 0.16), AppColors.live);
      case '서스펜디드':
        return (
          AppColors.ballYellow.withValues(alpha: 0.16),
          AppColors.ballYellow,
        );
      default:
        if (label.contains('회')) {
          return (AppColors.live.withValues(alpha: 0.16), AppColors.live);
        }
        if (label.contains('취소')) {
          return (
            AppColors.textDisabled.withValues(alpha: 0.18),
            AppColors.textDisabled,
          );
        }
        return (AppColors.cardSub, AppColors.textSecondary);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: fontSize,
          color: textColor,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
