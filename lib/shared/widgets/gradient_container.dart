import 'package:flutter/material.dart';

/// Container with gradient background for highlighting important content
class GradientContainer extends StatelessWidget {
  const GradientContainer({
    required this.child,
    required this.colors,
    super.key,
    this.begin = Alignment.topLeft,
    this.end = Alignment.bottomRight,
    this.borderRadius,
  });

  final Widget child;
  final List<Color> colors;
  final AlignmentGeometry begin;
  final AlignmentGeometry end;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: begin,
          end: end,
        ),
        borderRadius: borderRadius,
      ),
      child: child,
    );
  }
}
