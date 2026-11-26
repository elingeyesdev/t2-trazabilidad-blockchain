import 'package:flutter/material.dart';

/// Entrada breve de un elemento: aparece y sube unos píxeles.
///
/// Con [index] los elementos de una lista entran en cascada. Es una sola
/// animación finita (sin temporizadores ni bucles), así que no bloquea
/// `pumpAndSettle` ni gasta batería. Respeta "quitar animaciones".
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.index = 0,
    this.offset = 14,
  });

  final Widget child;

  /// Posición en la cascada. Se limita a 6 para que nada tarde en aparecer.
  final int index;
  final double offset;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  static const _step = 45;
  static const _base = 260;

  late final int _delay = widget.index.clamp(0, 6) * _step;
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: _base + _delay),
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: Interval(_delay / (_base + _delay), 1, curve: Curves.easeOutCubic),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _curve,
    child: widget.child,
    builder: (context, child) => Opacity(
      opacity: _curve.value,
      child: Transform.translate(
        offset: Offset(0, (1 - _curve.value) * widget.offset),
        child: child,
      ),
    ),
  );
}

/// Aparece con un pequeño "pop" (de 85 % a 100 %). Para íconos de estado.
class PopIn extends StatelessWidget {
  const PopIn({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: .85, end: 1),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutBack,
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: ((t - .85) / .15).clamp(0.0, 1.0),
        child: Transform.scale(scale: t, child: child),
      ),
    );
  }
}
