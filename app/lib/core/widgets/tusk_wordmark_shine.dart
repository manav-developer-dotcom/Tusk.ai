import 'package:flutter/material.dart';

/// Cinematic cold-launch wordmark shine for Tusk.
///
/// Reads exactly 'TUSK' in bold capitals on a pure black background.
/// A brilliant platinum-white specular beam sweeps from left to right
/// over one second, then the text settles into pure clean white.
/// Respects reduced-motion system preferences.
class TuskWordmarkShine extends StatefulWidget {
  final VoidCallback? onComplete;
  final bool animate;
  final double fontSize;

  const TuskWordmarkShine({
    super.key,
    this.onComplete,
    this.animate = true,
    this.fontSize = 44,
  });

  @override
  State<TuskWordmarkShine> createState() => _TuskWordmarkShineState();
}

class _TuskWordmarkShineState extends State<TuskWordmarkShine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  // Shine beam position: travels from far left (-1.5) to far right (2.5)
  late final Animation<double> _shinePos;

  // Text fades from near-invisible to pure white after the shine
  late final Animation<double> _textOpacity;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );

    // Shine sweeps across the text — starts before the left edge, ends past right
    _shinePos = Tween<double>(begin: -1.5, end: 2.5).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 1.0, curve: Curves.easeInOut),
      ),
    );

    // Text opacity: starts at 0.12 (nearly invisible), rises to 1.0 as shine passes
    _textOpacity = Tween<double>(begin: 0.12, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.35, 0.95, curve: Curves.easeOut),
      ),
    );

    if (widget.animate) {
      // Tiny delay so first frame renders cleanly before animation begins
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _controller.forward().then((_) {
            if (mounted && widget.onComplete != null) {
              widget.onComplete!();
            }
          });
        }
      });
    } else {
      if (widget.onComplete != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onComplete!();
        });
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    final textStyle = TextStyle(
      fontSize: widget.fontSize,
      fontWeight: FontWeight.w900,
      letterSpacing: widget.fontSize * 0.08, // ~8% of font size for elegance
      color: Colors.white,
    );

    // Static render for reduced-motion or non-animated mode
    if (reduceMotion || !widget.animate) {
      return Text('TUSK', style: textStyle);
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final pos = _shinePos.value;
        final opacity = _textOpacity.value;

        // The shine beam width relative to the text (0.0–1.0 coordinate space)
        const beamHalfWidth = 0.18;

        // Gradient stops for the beam — clamped to [0,1] bounds
        final s0 = (pos - beamHalfWidth * 2.0).clamp(0.0, 1.0);
        final s1 = (pos - beamHalfWidth).clamp(0.0, 1.0);
        final s2 = pos.clamp(0.0, 1.0); // Peak brightness
        final s3 = (pos + beamHalfWidth).clamp(0.0, 1.0);
        final s4 = (pos + beamHalfWidth * 2.0).clamp(0.0, 1.0);

        return Opacity(
          opacity: opacity,
          child: ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (bounds) {
              return LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: const [
                  Color(0xFF1A1A1A), // Near-black base
                  Color(0xFF5A5A5A), // Mid chrome approach
                  Color(0xFFFFFFFF), // Brilliant platinum peak
                  Color(0xFF5A5A5A), // Mid chrome fall-off
                  Color(0xFF1A1A1A), // Near-black tail
                ],
                stops: [s0, s1, s2, s3, s4],
              ).createShader(bounds);
            },
            child: Text('TUSK', style: textStyle),
          ),
        );
      },
    );
  }
}

/// Full-screen cinematic splash that plays the TUSK wordmark reveal once
/// on cold launch, then calls [onComplete] to hand control to the app.
///
/// All timing is driven by [AnimationController]s (ticker-based), making it
/// fully compatible with Flutter's [pumpAndSettle] in tests.
class TuskSplashReveal extends StatefulWidget {
  final VoidCallback onComplete;

  const TuskSplashReveal({super.key, required this.onComplete});

  @override
  State<TuskSplashReveal> createState() => _TuskSplashRevealState();
}

class _TuskSplashRevealState extends State<TuskSplashReveal>
    with TickerProviderStateMixin {
  /// Short hold after the shine finishes (200ms delay driven by a ticker)
  late final AnimationController _hold;

  /// Fade-out animation: 1.0 → 0.0 over 300ms
  late final AnimationController _fadeOut;

  @override
  void initState() {
    super.initState();

    _hold = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    // Start at 1.0 (visible); reverse() drives it to 0.0 (invisible)
    _fadeOut = AnimationController(
      vsync: this,
      value: 1.0,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void dispose() {
    _hold.dispose();
    _fadeOut.dispose();
    super.dispose();
  }

  /// Called by [TuskWordmarkShine] when its 1.1-second sweep finishes.
  void _onShineComplete() {
    if (!mounted) return;
    // Hold for 200ms, then fade out, then notify parent — all ticker-driven
    _hold.forward().then((_) {
      if (!mounted) return;
      _fadeOut.reverse().then((_) {
        if (mounted) widget.onComplete();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    if (reduceMotion) {
      // Accessibility: skip animation, transition immediately next frame
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onComplete();
      });
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text(
            'TUSK',
            style: TextStyle(
              fontSize: 52,
              fontWeight: FontWeight.w900,
              letterSpacing: 4.0,
              color: Colors.white,
            ),
          ),
        ),
      );
    }

    return AnimatedBuilder(
      animation: _fadeOut,
      builder: (context, child) => Opacity(
        opacity: _fadeOut.value,
        child: child,
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: TuskWordmarkShine(
            fontSize: 52,
            animate: true,
            onComplete: _onShineComplete,
          ),
        ),
      ),
    );
  }
}
