/*
 * A small themed message pill that floats in the top right corner and fades away.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import 'package:flutter/material.dart';

/// Shows [text] in a dark rounded pill in the top right corner, just under the clock. It fades in, stays, fades out and
/// removes itself after about [duration] (2 seconds by default). It never takes focus or blocks input.
///
/// Pass an [OverlayState] you captured before awaiting anything, so it stays valid after a dialog closes.
void showPillToast(
  OverlayState overlay,
  String text, {
  IconData icon = Icons.check_circle_outline,
  Color? iconColor,
  Color accent = const Color(0xFF7C4DFF),
  Duration duration = const Duration(seconds: 2),
}) {
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _PillToast(
      text: text,
      icon: icon,
      iconColor: iconColor ?? accent,
      accent: accent,
      duration: duration,
      onDone: () => entry.remove(),
    ),
  );
  overlay.insert(entry);
}

class _PillToast extends StatefulWidget {
  final String text;
  final IconData icon;
  final Color iconColor;
  final Color accent;
  final Duration duration;
  final VoidCallback onDone;

  const _PillToast({
    required this.text,
    required this.icon,
    required this.iconColor,
    required this.accent,
    required this.duration,
    required this.onDone,
  });

  @override
  State<_PillToast> createState() => _PillToastState();
}

class _PillToastState extends State<_PillToast>
    with SingleTickerProviderStateMixin {
  static const _fadeIn = Duration(milliseconds: 180);
  static const _fadeOut = Duration(milliseconds: 250);

  // One animation drives everything (fade in, hold, fade out), so no separate timer is needed.
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: widget.duration);
  late final Animation<double> _opacity = TweenSequence<double>([
    TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: _fadeIn.inMilliseconds.toDouble()),
    TweenSequenceItem(
      tween: ConstantTween(1.0),
      weight: (widget.duration - _fadeIn - _fadeOut)
          .inMilliseconds
          .clamp(1, 1 << 30)
          .toDouble(),
    ),
    TweenSequenceItem(
        tween:
            Tween(begin: 1.0, end: 0.0).chain(CurveTween(curve: Curves.easeIn)),
        weight: _fadeOut.inMilliseconds.toDouble()),
  ]).animate(_controller);

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) widget.onDone();
    });
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context)
        .textTheme
        .bodyMedium
        ?.copyWith(color: Colors.white, fontWeight: FontWeight.w600);

    return Positioned.fill(
      child: IgnorePointer(
        child: Align(
          alignment: Alignment.topRight,
          // Right of the screen, a little below the status bar clock so it never covers it.
          child: Padding(
            padding: const EdgeInsets.only(top: 76, right: 28),
            child: FadeTransition(
              opacity: _opacity,
              child: ScaleTransition(
                alignment: Alignment.topRight,
                scale: Tween<double>(begin: 0.94, end: 1.0).animate(_opacity),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Material(
                    type: MaterialType.transparency,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 22, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF111111).withOpacity(0.92),
                        borderRadius: BorderRadius.circular(32),
                        border: Border.all(
                            color: widget.accent.withOpacity(0.55), width: 1.5),
                        boxShadow: [
                          BoxShadow(
                              color: widget.accent.withOpacity(0.35),
                              blurRadius: 18,
                              spreadRadius: 1),
                          const BoxShadow(
                              color: Colors.black54, blurRadius: 12),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(widget.icon, size: 22, color: widget.iconColor),
                          const SizedBox(width: 10),
                          Flexible(
                              child: Text(widget.text,
                                  style: textStyle,
                                  textAlign: TextAlign.center)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
