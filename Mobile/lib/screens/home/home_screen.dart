import 'package:flutter/material.dart';

import '../../models/auth_user.dart';
import '../../navigation/app_module.dart';
import '../../navigation/app_routes.dart';
import '../../theme/app_theme.dart';
import '../../theme/module_palette.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/field_kit.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.user, required this.onLogout});
  final AuthUser user;
  final VoidCallback onLogout;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  final _workSearch = TextEditingController();

  @override
  void dispose() {
    _workSearch.dispose();
    super.dispose();
  }

  static const _groups = {
    'Trabajo de campo': [
      AppModule.actividades,
      AppModule.lotes,
      AppModule.producciones,
    ],
    'Trabajo en planta': [AppModule.tareasPlanta, AppModule.recepcionesPlanta],
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

  static const _days = [
    'Lunes',
    'Martes',
    'Miércoles',
    'Jueves',
    'Viernes',
    'Sábado',
    'Domingo',
  ];
  static const _months = [
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

  void _open(AppModule module) {
    FocusScope.of(context).unfocus();
    Navigator.of(context).pushNamed(module.route);
  }

  void _selectTab(int tab) {
    FocusScope.of(context).unfocus();
    if (tab == 2) {
      Navigator.of(context).pushNamed(AppRoutes.profile);
    } else {
      setState(() => _tab = tab);
    }
  }

  bool get _largeText => MediaQuery.textScalerOf(context).scale(16) > 24;

  @override
  Widget build(BuildContext context) {
    final groups = {
      for (final group in _groups.entries)
        group.key: group.value
            .where((module) => module.canOpen(widget.user))
            .toList(),
    }..removeWhere((_, modules) => modules.isEmpty);
    final modules = groups.values.expand((group) => group).toList();
    return PopScope(
      canPop: _tab == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _tab != 0) setState(() => _tab = 0);
      },
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: SingleChildScrollView(
            key: ValueKey(_tab),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _topBar(),
                    const SizedBox(height: 22),
                    if (_tab == 0 || modules.isEmpty) ...[
                      _greeting(),
                      const SizedBox(height: 24),
                    ],
                    if (modules.isEmpty)
                      AppEmptyState(
                        icon: Icons.person_outline_rounded,
                        tone: AppTheme.maizeSoft,
                        ink: const Color(0xFF5F4100),
                        title: widget.user.permissions.isEmpty
                            ? 'Tu cuenta aún no tiene accesos'
                            : 'Las funciones de tu perfil están en la web',
                        message: widget.user.permissions.isEmpty
                            ? 'Pide al responsable que habilite las opciones que necesitas. Tu perfil sigue disponible abajo.'
                            : 'Tu cuenta está activa. Por ahora, sus funciones se consultan desde la web. Puedes revisar tu perfil aquí.',
                      )
                    else if (_tab == 0)
                      ..._home(modules)
                    else
                      ..._work(groups),
                    if (_tab == 0) ...[const SizedBox(height: 32), _account()],
                  ],
                ),
              ),
            ),
          ),
        ),
        bottomNavigationBar: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppTheme.border, width: 1)),
          ),
          child: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: _selectTab,
            animationDuration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 200),
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

  Widget _topBar() => Row(
    children: [
      const BrandMark(size: 40),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          'AgroFusion',
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
      ),
      const SizedBox(width: 8),
      Tooltip(
        message: 'Cerrar sesión',
        excludeFromSemantics: true,
        child: Semantics(
          button: true,
          label: 'Cerrar sesión',
          excludeSemantics: true,
          child: OutlinedButton.icon(
            onPressed: widget.onLogout,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            icon: const Icon(Icons.logout_rounded, size: 22),
            label: const Text('Salir'),
          ),
        ),
      ),
    ],
  );

  Widget _greeting() {
    final today = DateTime.now();
    final theme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.wb_sunny_rounded,
              size: 20,
              color: Color(0xFF9A6A00),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${_days[today.weekday - 1]}, ${today.day} de ${_months[today.month - 1]}',
                style: theme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Semantics(
          header: true,
          child: Text('Hola, ${widget.user.name}', style: theme.displaySmall),
        ),
      ],
    );
  }

  List<Widget> _home(List<AppModule> modules) {
    final primary = modules.first;
    final shortcuts = modules.skip(1).take(4).toList();
    return [
      _featured(primary),
      if (shortcuts.isNotEmpty) ...[
        const SizedBox(height: 32),
        const SectionTitle('Accesos rápidos'),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final singleColumn = constraints.maxWidth < 300 || _largeText;
            final width = singleColumn
                ? constraints.maxWidth
                : (constraints.maxWidth - 14) / 2;
            return Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                for (final module in shortcuts)
                  SizedBox(width: width, child: _shortcut(module)),
              ],
            );
          },
        ),
      ],
      if (modules.length > 1) ...[
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: () => _selectTab(1),
          icon: const Icon(Icons.grid_view_rounded),
          label: const Text('Ver todo mi trabajo'),
        ),
      ],
    ];
  }

  Widget _featured(AppModule module) {
    final title = switch (module) {
      AppModule.actividades => 'Actividades del campo',
      AppModule.tareasPlanta => 'Tus tareas de planta',
      AppModule.asignaciones => 'Tus envíos asignados',
      AppModule.almacenes => 'Tus almacenes',
      _ => module.label,
    };
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.fieldDeep,
        borderRadius: BorderRadius.circular(24),
        boxShadow: AppTheme.stamp(5),
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF13331C), width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: _largeText ? 72 : 112,
              child: const Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(color: Color(0xFF2C5E39)),
                  ExcludeSemantics(
                    child: CustomPaint(painter: FurrowPainter()),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.maize,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Lo principal',
                      style: TextStyle(
                        color: AppTheme.ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Semantics(
                    header: true,
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 28,
                        height: 1.15,
                        letterSpacing: -.6,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    module.description,
                    style: const TextStyle(
                      fontSize: 17,
                      height: 1.4,
                      color: Color(0xFFE6EFE2),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => _open(module),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.maize,
                        foregroundColor: AppTheme.ink,
                        side: const BorderSide(
                          color: Color(0xFFC58C1F),
                          width: 1,
                        ),
                      ),
                      icon: const Icon(Icons.arrow_forward_rounded),
                      label: Text('Ver ${module.label.toLowerCase()}'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _shortcut(AppModule module) {
    final look = module.look;
    return PressableCard(
      onTap: () => _open(module),
      color: AppTheme.sprout,
      borderColor: AppTheme.sproutBorder,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppTheme.field,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: AppTheme.fieldDeep, width: 1),
                  ),
                  child: Icon(module.icon, color: Colors.white, size: 28),
                ),
              ),
              const Spacer(),
              const Icon(
                Icons.arrow_forward_rounded,
                size: 24,
                color: AppTheme.fieldDeep,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            module.label,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(
            look.hint,
            style: const TextStyle(
              fontSize: 15,
              height: 1.35,
              color: AppTheme.fieldDeep,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _work(Map<String, List<AppModule>> groups) {
    final query = _workSearch.text.trim().toLowerCase();
    final visible = {
      for (final group in groups.entries)
        group.key: group.value
            .where(
              (module) => '${module.label} ${module.description} ${group.key}'
                  .toLowerCase()
                  .contains(query),
            )
            .toList(),
    }..removeWhere((_, modules) => modules.isEmpty);

    return [
      Semantics(
        header: true,
        child: Text(
          'Tus accesos',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        'Encuentra aquí las herramientas de tu trabajo.',
        style: Theme.of(context).textTheme.bodyLarge,
      ),
      const SizedBox(height: 20),
      TextField(
        controller: _workSearch,
        onChanged: (_) => setState(() {}),
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => FocusScope.of(context).unfocus(),
        style: const TextStyle(fontSize: 18),
        decoration: InputDecoration(
          hintText: 'Buscar herramienta',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: query.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Limpiar herramientas',
                  onPressed: () => setState(() => _workSearch.clear()),
                  icon: const Icon(Icons.close_rounded),
                ),
        ),
      ),
      const SizedBox(height: 24),
      if (visible.isEmpty)
        AppEmptyState(
          icon: Icons.search_off_rounded,
          tone: AppTheme.maizeSoft,
          ink: const Color(0xFF5F4100),
          title: 'No encontramos herramientas',
          message: 'Prueba con otro nombre o limpia la búsqueda.',
          action: OutlinedButton.icon(
            onPressed: () => setState(() => _workSearch.clear()),
            icon: const Icon(Icons.close_rounded),
            label: const Text('Limpiar búsqueda'),
          ),
        )
      else
        for (final group in visible.entries) ...[
          SectionTitle(group.key, color: AppTheme.field),
          const SizedBox(height: 14),
          for (final module in group.value) ...[
            _workRow(module),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 18),
        ],
    ];
  }

  Widget _workRow(AppModule module) {
    final badgeSize = _largeText ? 44.0 : 56.0;
    return PressableCard(
      onTap: () => _open(module),
      padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
      child: Row(
        children: [
          ExcludeSemantics(
            child: Container(
              width: badgeSize,
              height: badgeSize,
              decoration: BoxDecoration(
                color: AppTheme.field,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: AppTheme.fieldDeep, width: 1),
              ),
              child: Icon(
                module.icon,
                color: Colors.white,
                size: badgeSize * 0.54,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  module.label,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  module.description,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(
            Icons.chevron_right_rounded,
            size: 32,
            color: AppTheme.ink,
          ),
        ],
      ),
    );
  }

  Widget _account() => Align(
    alignment: Alignment.centerLeft,
    child: TextButton.icon(
      onPressed: () => Navigator.of(context).pushNamed(AppRoutes.connection),
      icon: const Icon(Icons.wifi_rounded),
      label: const Text('Comprobar conexión'),
    ),
  );
}
