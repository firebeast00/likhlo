import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// ================= SLIDE-IN ANIMATION =================
class SlideInAnimation extends StatefulWidget {
  final Widget child;
  final int index;
  final Duration duration;
  final Duration delayStep;
  final Offset initialOffset;

  const SlideInAnimation({
    super.key,
    required this.child,
    required this.index,
    this.duration = const Duration(milliseconds: 400),
    this.delayStep = const Duration(milliseconds: 30),
    this.initialOffset = const Offset(0, 0.1),
  });

  @override
  State<SlideInAnimation> createState() => _SlideInAnimationState();
}

class _SlideInAnimationState extends State<SlideInAnimation> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _offsetAnim;
  late final Animation<double> _fadeAnim;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);

    // Using easeOutQuart creates a much smoother, premium snapping effect
    _offsetAnim = Tween<Offset>(begin: widget.initialOffset, end: Offset.zero).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutQuart),
    );

    _fadeAnim = CurvedAnimation(parent: _controller, curve: Curves.easeIn);

    // Safely trigger staggered animation with a cancellable timer
    _timer = Timer(widget.delayStep * widget.index, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _timer?.cancel(); // 🛡️ Prevents memory leaks if widget is destroyed early
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnim,
      child: SlideTransition(
        position: _offsetAnim,
        child: widget.child,
      ),
    );
  }
}

// ================= ROLLING NUMBER ANIMATION =================
class RollingNumber extends StatelessWidget {
  final double value;
  final TextStyle? style;
  final String prefix;
  final Duration duration;

  const RollingNumber({
    super.key,
    required this.value,
    this.style,
    this.prefix = '',
    this.duration = const Duration(milliseconds: 1500),
  });

  @override
  Widget build(BuildContext context) {
    // 🚀 Initialize formatter ONCE outside the builder to save CPU cycles
    final fmt = NumberFormat.decimalPattern('en_us');

    return TweenAnimationBuilder<double>(
      // 🛡️ Omitting 'begin' allows it to smoothly transition between new values
      // without resetting to zero every time the parent rebuilds.
      tween: Tween<double>(end: value),
      duration: duration,
      curve: Curves.easeOutExpo, // Creates that fast-to-slow "fintech" counter effect
      builder: (context, val, child) {
        return Text(
          "$prefix${fmt.format(val.toInt())}",
          style: style,
        );
      },
    );
  }
}