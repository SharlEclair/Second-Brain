import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

extension FluidRevealExtension on Widget {
  Widget fluidReveal({
    Duration duration = const Duration(milliseconds: 500),
    double beginY = 0.15,
    Duration delay = Duration.zero,
  }) {
    return this.animate(delay: delay).slideY(
          begin: beginY,
          end: 0,
          curve: Curves.easeOutExpo,
          duration: duration,
        ).fadeIn(
          duration: duration,
          curve: Curves.easeOutExpo,
        );
  }
}
