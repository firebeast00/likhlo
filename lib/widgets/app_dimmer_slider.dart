import 'package:flutter/material.dart';

/// Give Android one laid-out slider node rather than exporting the Slider's
/// empty focus child. Keep touch, keyboard and screen-reader adjustment.
class AppDimmerSlider extends StatefulWidget {
  final double value;
  final Color color;
  final String label;
  final ValueChanged<double> onChanged;

  const AppDimmerSlider({
    super.key,
    required this.value,
    required this.color,
    required this.label,
    required this.onChanged,
  });

  @override
  State<AppDimmerSlider> createState() => _AppDimmerSliderState();
}

class _AppDimmerSliderState extends State<AppDimmerSlider> {
  static const maximum = 0.75;
  static const step = maximum * 0.05;
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_focusChanged);
  }

  void _focusChanged() => setState(() {});

  @override
  void dispose() {
    _focusNode.removeListener(_focusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.value.clamp(0.0, maximum).toDouble();
    final higher = (value + step).clamp(0.0, maximum).toDouble();
    final lower = (value - step).clamp(0.0, maximum).toDouble();
    String percent(double amount) => '${(amount * 100).round()}%';

    return Semantics(
      container: true,
      excludeSemantics: true,
      slider: true,
      focusable: true,
      focused: _focusNode.hasFocus,
      label: widget.label,
      value: percent(value),
      increasedValue: percent(higher),
      decreasedValue: percent(lower),
      onIncrease: value < maximum ? () => widget.onChanged(higher) : null,
      onDecrease: value > 0 ? () => widget.onChanged(lower) : null,
      onFocus: _focusNode.requestFocus,
      child: Slider(
        focusNode: _focusNode,
        value: value,
        min: 0,
        max: maximum,
        activeColor: widget.color,
        inactiveColor: widget.color.withValues(alpha: 0.2),
        onChanged: widget.onChanged,
      ),
    );
  }
}
