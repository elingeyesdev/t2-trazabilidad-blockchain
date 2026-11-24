import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/auth_user.dart';
import '../../navigation/app_module.dart';
import '../../navigation/app_routes.dart';
import '../../theme/app_glyphs.dart';
import '../../theme/app_theme.dart';
import '../../theme/module_palette.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/field_kit.dart';
import '../../widgets/motion.dart';
import '../../widgets/pending_banner.dart';
import '../../widgets/today_tasks.dart';
import '../../services/module_service.dart';
import '../../services/pending_queue.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.user,
    required this.onLogout,
    this.pending,
    this.offlineData,
    this.onSync,
    this.service,
  });
  final AuthUser user;
  final VoidCallback onLogout;
  final PendingQueue? pending;
  final ValueListenable<bool>? offlineData;
  final VoidCallback? onSync;
  final ModuleService? service;

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
                    if (widget.pending != null &&
                        widget.offlineData != null &&
                        widget.onSync != null)
                      PendingBanner(
                        user: widget.user,
                        pending: widget.pending!,
                        offlineData: widget.offlineData!,
                        onSync: widget.onSync!,
                      ),
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

  /// "jefe_agricultor" -> "Jefe agricultor".
  String get _roleLabel {
    if (widget.user.roles.isEmpty) return 'Trazabilidad agrícola';
    final raw = widget.user.roles.first.replaceAll('_', ' ');
    return raw[0].toUpperCase() + raw.substring(1);
  }

  Widget _topBar() {
    final theme = Theme.of(context).textTheme;
    return Column(
      children: [
        Row(
          children: [
            const BrandMark(size: 42),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'AgroFusion',
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.display(23, 1.1, 800, -.5),
                  ),
                  Text(
                    _roleLabel,
                    overflow: TextOverflow.ellipsis,
                    style: theme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              key: const ValueKey('home.trazabilidad_publica'),
              tooltip: 'Consultar trazabilidad (QR o código)',
              onPressed: () {
                FocusScope.of(context).unfocus();
                Navigator.of(context).pushNamed(AppRoutes.trazabilidadPublica);
              },
              style: IconButton.styleFrom(
                minimumSize: const Size(48, 48),
                backgroundColor: AppTheme.sprout,
                foregroundColor: AppTheme.fieldDeep,
                side: const BorderSide(color: AppTheme.sproutBorder),
              ),
              icon: const Icon(Icons.qr_code_scanner_rounded, size: 22),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Cerrar sesión',
              onPressed: widget.onLogout,
              style: IconButton.styleFrom(
                minimumSize: const Size(48, 48),
                backgroundColor: AppTheme.surface,
                side: const BorderSide(color: AppTheme.border),
              ),
              icon: const Icon(AppIcons.signOut, size: 22),
            ),
          ],
        ),
        const SizedBox(height: 14),
        const Divider(height: 1),
      ],
    );
  }

  Widget _greeting() {
    final today = DateTime.now();
    final theme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${_days[today.weekday - 1]}, ${today.day} de ${_months[today.month - 1]}',
          style: theme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
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
      if (widget.service != null)
        TodayTasks(
          user: widget.user,
          service: widget.service!,
          onOpen: (module, id) =>
              Navigator.of(context).pushNamed(AppRoutes.detalle(module, id)),
        ),
      FadeSlideIn(child: _featured(primary)),
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
                for (final (i, module) in shortcuts.indexed)
                  SizedBox(
                    width: width,
                    child: FadeSlideIn(index: i + 1, child: _shortcut(module)),
                  ),
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
      color: look.tone,
      borderColor: look.ink.withValues(alpha: .28),
      padding: const EdgeInsets.fromLTRB(16, 16, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GlyphIcon(module.icon, size: 40, color: look.ink, fillOpacity: .3),
          const SizedBox(height: 18),
          Text(
            module.label,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: look.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            look.hint,
            style: TextStyle(fontSize: 14, height: 1.35, color: look.ink),
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
          FadeSlideIn(child: _workGroup(group.value)),
          const SizedBox(height: 26),
        ],
    ];
  }

  /// Un bloque por sección, con las filas separadas por una línea fina.
  Widget _workGroup(List<AppModule> modules) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border),
        boxShadow: AppTheme.stamp(3),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(19),
        child: Material(
          color: Colors.transparent,
          child: Column(
            children: [
              for (final (i, module) in modules.indexed) ...[
                if (i > 0)
                  const Divider(height: 1, indent: 76, color: AppTheme.line),
                _workRow(module),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _workRow(AppModule module) {
    final markSize = _largeText ? 44.0 : 48.0;
    return MergeSemantics(
      child: InkWell(
        onTap: () => _open(module),
        splashColor: AppTheme.field.withValues(alpha: .08),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Row(
            children: [
              ModuleMark(module, size: markSize),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      module.label,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      module.description,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                AppIcons.caretRight,
                size: 18,
                color: AppTheme.inkSoft,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
