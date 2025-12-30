import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class SlideInAnimation extends StatefulWidget {
  final Widget child;
  final int index;
  const SlideInAnimation({super.key, required this.child, required this.index});

  @override
  State<SlideInAnimation> createState() => _SlideInAnimationState();
}

class _SlideInAnimationState extends State<SlideInAnimation> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _offsetAnim;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    Future.delayed(Duration(milliseconds: widget.index * 30), () {
      if (mounted) _controller.forward();
    });
    _offsetAnim = Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutQuad));
    _fadeAnim = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
  }

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(opacity: _fadeAnim, child: SlideTransition(position: _offsetAnim, child: widget.child));
  }
}

class RollingNumber extends StatelessWidget {
  final double value;
  final TextStyle style;
  final String prefix;

  const RollingNumber({super.key, required this.value, required this.style, this.prefix = ''});

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.decimalPattern('en_us');
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value),
      duration: const Duration(milliseconds: 1500),
      curve: Curves.easeOutExpo,
      builder: (context, val, child) {
        return Text("$prefix${fmt.format(val.toInt())}", style: style);
      },
    );
  }
}