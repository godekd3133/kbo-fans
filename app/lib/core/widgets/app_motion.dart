import 'dart:math' as math;

import 'package:flutter/material.dart';

class AppMotionSwitcher extends StatelessWidget {
  final Widget child;
  final Duration duration;
  final Duration reverseDuration;
  final Offset beginOffset;
  final Alignment alignment;

  const AppMotionSwitcher({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 220),
    this.reverseDuration = const Duration(milliseconds: 160),
    this.beginOffset = const Offset(0, 0.025),
    this.alignment = Alignment.topCenter,
  });

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) {
      return child;
    }

    return AnimatedSwitcher(
      duration: duration,
      reverseDuration: reverseDuration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          alignment: alignment,
          children: [...previousChildren, ?currentChild],
        );
      },
      transitionBuilder: (child, animation) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: beginOffset,
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

class AppMotionListItem extends StatelessWidget {
  final int index;
  final Widget child;
  final double beginYOffset;

  const AppMotionListItem({
    super.key,
    required this.index,
    required this.child,
    this.beginYOffset = 10,
  });

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) {
      return child;
    }

    final extraMs = math.min(index, 8) * 24;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: 180 + extraMs),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        final opacity = value.clamp(0.0, 1.0).toDouble();
        return Opacity(
          opacity: opacity,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * beginYOffset),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}
