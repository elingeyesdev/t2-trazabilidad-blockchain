import 'package:flutter/material.dart';

import '../../models/auth_user.dart';
import '../../navigation/app_module.dart';
import '../../navigation/app_routes.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_empty_state.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.user, required this.onLogout});
  final AuthUser user;
  final VoidCallback onLogout;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  static const _groups = {
    'Trabajo de campo': [
      AppModule.actividades,
      AppModule.lotes,
      AppModule.producciones,
    ],
    'Almacenes e insumos': [
      AppModule.almacenes,
      AppModule.insumos,
      AppModule.movimientos,
    ],
    'Pedidos y entregas': [
      AppModule.asignaciones,
      AppModule.pedidos,
      AppModule.rutas,
      AppModule.documentos,
      AppModule.incidentes,
    ],
    'Calidad y administración': [AppModule.certificaciones, AppModule.usuarios],
  };

  void _open(AppModule module) => Navigator.of(context).pushNamed(module.route);

  void _selectTab(int tab) {
    if (tab == 2) {
      Navigator.of(context).pushNamed(AppRoutes.profile);
    } else {
      setState(() => _tab = tab);
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = {
      for (final group in _groups.entries)
        group.key: group.value
            .where((module) => module.canOpen(widget.user))
            .toList(),
    }..removeWhere((_, modules) => modules.isEmpty);
    final modules = groups.values.expand((group) => group).toList();
    final today = DateTime.now();
    const days = [
      'Lunes',
      'Martes',
      'Miércoles',
      'Jueves',
      'Viernes',
      'Sábado',
      'Domingo',
    ];
    const months = [
      'enero',
      'febrero',
      'marzo',
      'abril',
      'mayo',
      'junio',
      'julio',
      'agosto',
      'septiembre',
      'octubre',
      'noviembre',
      'diciembre',
    ];
    return PopScope(
      canPop: _tab == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _tab != 0) setState(() => _tab = 0);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppTheme.forest,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  Icons.eco_outlined,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              const Flexible(child: Text('AgroFusion')),
            ],
          ),
          actions: [
            IconButton(
              onPressed: widget.onLogout,
              tooltip: 'Cerrar sesión',
              icon: const Icon(Icons.logout_rounded, size: 22),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          bottom: false,
          child: SingleChildScrollView(
            key: ValueKey(_tab),
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${days[today.weekday - 1]}, ${today.day} de ${months[today.month - 1]}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Hola, ${widget.user.name}',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 24),
                    if (modules.isEmpty)
                      const AppEmptyState(
                        icon: Icons.person_outline_rounded,
                        title: 'Tu cuenta aún no tiene accesos',
                        message:
                            'Pide al responsable que habilite las opciones que necesitas. Tu perfil sigue disponible abajo.',
                      )
                    else if (_tab == 0)
                      ..._home(modules)
                    else
                      ..._work(groups),
                    const SizedBox(height: 24),
                    _account(),
                  ],
                ),
              ),
            ),
          ),
        ),
        bottomNavigationBar: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppTheme.line)),
          ),
          child: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: _selectTab,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home_rounded),
                label: 'Inicio',
              ),
              NavigationDestination(
                icon: Icon(Icons.grid_view_outlined),
                selectedIcon: Icon(Icons.grid_view_rounded),
                label: 'Trabajo',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline_rounded),
                selectedIcon: Icon(Icons.person_rounded),
                label: 'Mi perfil',
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _home(List<AppModule> modules) {
    final primary = modules.first;
    final shortcuts = modules.skip(1).take(4).toList();
    return [
      _featured(primary),
      if (shortcuts.isNotEmpty) ...[
        const SizedBox(height: 28),
        _sectionHeading('Accesos rápidos', onMore: () => _selectTab(1)),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final singleColumn =
                constraints.maxWidth < 300 ||
                MediaQuery.textScalerOf(context).scale(16) > 24;
            final width = singleColumn
                ? constraints.maxWidth
                : (constraints.maxWidth - 12) / 2;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final module in shortcuts)
                  SizedBox(width: width, child: _shortcut(module)),
              ],
            );
          },
        ),
      ] else ...[
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () => _selectTab(1),
          icon: const Icon(Icons.grid_view_outlined),
          label: const Text('Ver mis accesos'),
        ),
      ],
    ];
  }

  Widget _featured(AppModule module) {
    final largeText = MediaQuery.textScalerOf(context).scale(16) > 24;
    final title = switch (module) {
      AppModule.actividades => 'Actividades\ndel campo',
      AppModule.asignaciones => 'Tus envíos\nasignados',
      AppModule.pedidos => 'Pedidos',
      AppModule.almacenes => 'Tus\nalmacenes',
      _ => module.label,
    };
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: ColoredBox(
        color: AppTheme.forest,
        child: Stack(
          children: [
            if (!largeText)
              const Positioned(
                right: -16,
                bottom: -10,
                width: 164,
                height: 176,
                child: ExcludeSemantics(
                  child: CustomPaint(painter: _FieldPainter()),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    children: [
                      const Icon(
                        Icons.wb_sunny_outlined,
                        color: AppTheme.ochre,
                        size: 16,
                      ),
                      Text(
                        'TU ESPACIO DE TRABAJO',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .82),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 30,
                      height: 1.1,
                      letterSpacing: -.7,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: largeText ? null : 210,
                    child: Text(
                      module.description,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.45,
                        color: Colors.white.withValues(alpha: .84),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () => _open(module),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.ochre,
                      foregroundColor: AppTheme.forest,
                      minimumSize: const Size(0, 48),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                    label: Text('Ver ${module.label.toLowerCase()}'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeading(String title, {VoidCallback? onMore}) => Wrap(
    alignment: WrapAlignment.spaceBetween,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 12,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleMedium),
      if (onMore != null)
        TextButton(onPressed: onMore, child: const Text('Ver todos')),
    ],
  );

  Widget _shortcut(AppModule module) => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: const BorderSide(color: AppTheme.line),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: () => _open(module),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(module.icon, size: 28, color: AppTheme.forest),
                const Spacer(),
                const Icon(
                  Icons.north_east_rounded,
                  size: 16,
                  color: AppTheme.muted,
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(module.label, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              _shortcutLabel(module),
              style: const TextStyle(
                fontSize: 12,
                height: 1.4,
                color: AppTheme.muted,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  String _shortcutLabel(AppModule module) => switch (module) {
    AppModule.lotes => 'Cultivos y ubicación',
    AppModule.producciones => 'Cantidades y fechas',
    AppModule.almacenes => 'Lugares de almacenamiento',
    AppModule.insumos => 'Materiales y existencias',
    _ => 'Consultar información',
  };

  List<Widget> _work(Map<String, List<AppModule>> groups) => [
    Text('Tus accesos', style: Theme.of(context).textTheme.titleLarge),
    const SizedBox(height: 6),
    const Text('Encuentra aquí las herramientas de tu trabajo.'),
    const SizedBox(height: 24),
    for (final group in groups.entries) ...[
      Text(group.key, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 12),
      Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: AppTheme.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (var i = 0; i < group.value.length; i++) ...[
              if (i > 0)
                const Divider(
                  height: 1,
                  indent: 64,
                  endIndent: 16,
                  color: AppTheme.line,
                ),
              ListTile(
                minTileHeight: 84,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                leading: Icon(group.value[i].icon, color: AppTheme.forest),
                title: Text(
                  group.value[i].label,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                subtitle: Text(group.value[i].description),
                trailing: const Icon(Icons.chevron_right_rounded, size: 20),
                onTap: () => _open(group.value[i]),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 24),
    ],
  ];

  Widget _account() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Divider(color: AppTheme.line),
      const SizedBox(height: 12),
      Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppTheme.sage,
            foregroundColor: AppTheme.forest,
            child: Text(
              widget.user.name.trim().substring(0, 1).toUpperCase(),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              widget.user.email,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () =>
              Navigator.of(context).pushNamed(AppRoutes.connection),
          icon: const Icon(Icons.wifi_outlined, size: 18),
          label: const Text('Comprobar conexión'),
        ),
      ),
    ],
  );
}

class _FieldPainter extends CustomPainter {
  const _FieldPainter();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(
      Offset(size.width * .68, size.height * .18),
      18,
      Paint()..color = AppTheme.ochre.withValues(alpha: .9),
    );
    final far = Path()
      ..moveTo(0, size.height * .66)
      ..quadraticBezierTo(
        size.width * .5,
        size.height * .2,
        size.width,
        size.height * .48,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(far, Paint()..color = const Color(0xFF63845A));
    final near = Path()
      ..moveTo(0, size.height * .86)
      ..quadraticBezierTo(
        size.width * .58,
        size.height * .34,
        size.width,
        size.height * .62,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(near, Paint()..color = const Color(0xFF3B6446));
    canvas.save();
    canvas.clipPath(near);
    for (var i = 0; i < 7; i++) {
      final row = Path()
        ..moveTo(size.width * .56 + i * 15, size.height * .55)
        ..quadraticBezierTo(
          i * 30 - 30,
          size.height * .84,
          i * 34 - 70,
          size.height * 1.1,
        );
      canvas.drawPath(
        row,
        Paint()
          ..color = const Color(0xFF8CA46C)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FieldPainter oldDelegate) => false;
}
