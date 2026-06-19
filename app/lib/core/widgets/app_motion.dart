import 'dart:math' as math;

import 'package:flutter/material.dart';

class AppMotionSwitcher extends StatelessWidget {
  final Widget child;
  final Duration duration;
  final Duration reverseDuration;
  final Offset beginOffset;
  final double beginScale;
  final Alignment alignment;

  const AppMotionSwitcher({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 360),
    this.reverseDuration = const Duration(milliseconds: 260),
    this.beginOffset = const Offset(0, 0.032),
    this.beginScale = 0.975,
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
      switchInCurve: Curves.easeOutQuart,
      switchOutCurve: Curves.easeInOutCubic,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          alignment: alignment,
          children: [...previousChildren, ?currentChild],
        );
      },
      transitionBuilder: (child, animation) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutQuart,
          reverseCurve: Curves.easeInOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: beginScale, end: 1).animate(curved),
            child: SlideTransition(
              position: Tween<Offset>(
                begin: beginOffset,
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
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
  final double beginScale;

  const AppMotionListItem({
    super.key,
    required this.index,
    required this.child,
    this.beginYOffset = 22,
    this.beginScale = 0.972,
  });

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) {
      return child;
    }

    final extraMs = math.min(index, 10) * 34;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: 320 + extraMs),
      curve: Curves.easeOutQuart,
      builder: (context, value, child) {
        final opacity = value.clamp(0.0, 1.0).toDouble();
        return Opacity(
          opacity: opacity,
          child: Transform.scale(
            scale: beginScale + ((1 - beginScale) * value),
            child: Transform.translate(
              offset: Offset(0, (1 - value) * beginYOffset),
              child: child,
            ),
          ),
        );
      },
      child: child,
    );
  }
}

class AppPressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final HitTestBehavior behavior;
  final double pressedScale;
  final double pressedOpacity;
  final Duration duration;

  const AppPressable({
    super.key,
    required this.child,
    this.onTap,
    this.behavior = HitTestBehavior.opaque,
    this.pressedScale = 0.972,
    this.pressedOpacity = 0.92,
    this.duration = const Duration(milliseconds: 190),
  });

  @override
  State<AppPressable> createState() => _AppPressableState();
}

class _AppPressableState extends State<AppPressable> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) {
      return;
    }
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations || widget.onTap == null) {
      return GestureDetector(
        behavior: widget.behavior,
        onTap: widget.onTap,
        child: widget.child,
      );
    }

    return GestureDetector(
      behavior: widget.behavior,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: widget.onTap,
      child: AnimatedScale(
        duration: widget.duration,
        curve: Curves.easeOutQuart,
        scale: _pressed ? widget.pressedScale : 1,
        child: AnimatedOpacity(
          duration: widget.duration,
          curve: Curves.easeOutQuart,
          opacity: _pressed ? widget.pressedOpacity : 1,
          child: widget.child,
        ),
      ),
    );
  }
}

class AppMotionValue extends StatelessWidget {
  final Object? value;
  final Widget child;
  final Offset beginOffset;
  final double beginScale;

  const AppMotionValue({
    super.key,
    required this.value,
    required this.child,
    this.beginOffset = const Offset(0, -0.18),
    this.beginScale = 0.965,
  });

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) {
      return child;
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 340),
      reverseDuration: const Duration(milliseconds: 240),
      switchInCurve: Curves.easeOutQuart,
      switchOutCurve: Curves.easeInOutCubic,
      transitionBuilder: (child, animation) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutQuart,
          reverseCurve: Curves.easeInOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: beginScale, end: 1).animate(curved),
            child: SlideTransition(
              position: Tween<Offset>(
                begin: beginOffset,
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          ),
        );
      },
      child: KeyedSubtree(key: ValueKey<Object?>(value), child: child),
    );
  }
}
