import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Forma de la carga: anillo con hoja, o bloques que anticipan el contenido.
enum LoadingShape { spinner, list, detail }

/// Carga con mensaje en texto grande. Con [LoadingShape.list] o
/// [LoadingShape.detail] muestra el esqueleto de lo que va a aparecer.
class AppLoading extends StatelessWidget {
  const AppLoading({
    super.key,
    this.message = 'Cargando...',
    this.shape = LoadingShape.spinner,
  });

  final String message;
  final LoadingShape shape;

  @override
  Widget build(BuildContext context) {
    if (shape != LoadingShape.spinner) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            liveRegion: true,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Text(
                message,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          ),
          Expanded(
            child: ExcludeSemantics(
              child: _Pulse(
                child: ListView(
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  children: shape == LoadingShape.list
                      ? [for (var i = 0; i < 4; i++) const _CardSkeleton()]
                      : const [_DetailSkeleton()],
                ),
              ),
            ),
          ),
        ],
      );
    }
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Semantics(
          liveRegion: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 72,
                height: 72,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const SizedBox.expand(
                      child: CircularProgressIndicator(
                        strokeWidth: 4,
                        strokeCap: StrokeCap.round,
                        color: AppTheme.field,
                        backgroundColor: AppTheme.sprout,
                      ),
                    ),
                    const Icon(
                      Icons.eco_rounded,
                      color: AppTheme.field,
                      size: 32,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Latido suave de opacidad. Dura unos segundos y se detiene (no es un bucle
/// infinito), para no mantener ocupadas las pruebas ni la batería.
// shortcut: 10 latidos y se queda quieto, si la carga dura más se sube el conteo.
class _Pulse extends StatefulWidget {
  const _Pulse({required this.child});
  final Widget child;

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!MediaQuery.disableAnimationsOf(context)) {
      _controller.repeat(reverse: true, count: 10);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween<double>(
      begin: 1,
      end: .55,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut)),
    child: widget.child,
  );
}

class _Bone extends StatelessWidget {
  const _Bone({this.width, required this.height, this.radius = 8});
  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: AppTheme.line.withValues(alpha: .7),
      borderRadius: BorderRadius.circular(radius),
    ),
  );
}

class _CardSkeleton extends StatelessWidget {
  const _CardSkeleton();

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(AppTheme.radius),
      border: Border.all(color: AppTheme.line),
    ),
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _Bone(width: 44, height: 44, radius: 14),
            SizedBox(width: 12),
            Expanded(child: _Bone(height: 22)),
          ],
        ),
        SizedBox(height: 14),
        _Bone(width: 96, height: 26, radius: 13),
        SizedBox(height: 16),
        _Bone(height: 16),
        SizedBox(height: 10),
        _Bone(width: 240, height: 16),
      ],
    ),
  );
}

class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const _Bone(width: 220, height: 30),
      const SizedBox(height: 12),
      const _Bone(width: 110, height: 26, radius: 13),
      const SizedBox(height: 28),
      for (var i = 0; i < 5; i++) ...[
        const Row(
          children: [
            _Bone(width: 42, height: 42, radius: 12),
            SizedBox(width: 14),
            Expanded(child: _Bone(height: 18)),
          ],
        ),
        const SizedBox(height: 22),
      ],
    ],
  );
}
