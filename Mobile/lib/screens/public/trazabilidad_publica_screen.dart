import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/api_exception.dart';
import '../../models/trazabilidad_publica_models.dart';
import '../../services/trazabilidad_publica_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/app_error_state.dart';
import '../../widgets/app_loading.dart';
import '../../widgets/field_kit.dart';

class TrazabilidadPublicaScreen extends StatefulWidget {
  const TrazabilidadPublicaScreen({
    super.key,
    required this.codigo,
    required this.service,
    this.initialReporte,
  });

  final String codigo;
  final TrazabilidadPublicaService service;
  final TrazabilidadPublicaReporte? initialReporte;

  @override
  State<TrazabilidadPublicaScreen> createState() =>
      _TrazabilidadPublicaScreenState();
}

class _TrazabilidadPublicaScreenState extends State<TrazabilidadPublicaScreen> {
  final _searchCtrl = TextEditingController();
  final Set<String> _collapsedStages = <String>{};

  TrazabilidadPublicaReporte? _reporte;
  bool _loading = false;
  bool _notFound = false;
  String? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _reporte = widget.initialReporte;
    if (_reporte == null) {
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _notFound = false;
      _error = null;
    });
    try {
      final result = await widget.service.consultarReporte(widget.codigo);
      if (!mounted) return;
      setState(() {
        _reporte = result;
        _loading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      if (error.statusCode == 404) {
        setState(() {
          _loading = false;
          _notFound = true;
        });
        return;
      }
      setState(() {
        _loading = false;
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error =
            'No se pudo cargar la trazabilidad. Revisa tu conexión e intenta nuevamente.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trazabilidad del producto'),
        actions: [
          IconButton(
            key: const ValueKey('trazabilidad.publica.actualizar'),
            tooltip: 'Actualizar trazabilidad',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: _loading && _reporte == null
            ? const AppLoading(message: 'Cargando historial del producto...')
            : _notFound
            ? const AppEmptyState(
                icon: Icons.search_off_rounded,
                tone: AppTheme.maizeSoft,
                ink: Color(0xFF5F4100),
                title: 'Producto no encontrado',
                message:
                    'No existe un historial público asociado al código consultado.',
              )
            : _error != null && _reporte == null
            ? AppErrorState(message: _error!, onRetry: _load)
            : _buildContent(context, _reporte!),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    TrazabilidadPublicaReporte reporte,
  ) {
    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.claySoft,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.clay),
                    ),
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        color: AppTheme.clay,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                _buildHeaderCard(context, reporte),
                const SizedBox(height: 16),
                _buildMetadataCard(context, reporte),
                const SizedBox(height: 16),
                _buildCertificationsCard(context, reporte),
                const SizedBox(height: 16),
                _buildTimelineSection(context, reporte),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCard(
    BuildContext context,
    TrazabilidadPublicaReporte reporte,
  ) {
    final theme = Theme.of(context);
    final isVerified = reporte.blockchainVerificado;
    final hasCerts = reporte.tieneCertificaciones;

    final badgeBg = isVerified
        ? const Color(0xFF123629)
        : hasCerts
        ? AppTheme.maizeSoft
        : AppTheme.paper;
    final badgeFg = isVerified
        ? const Color(0xFFF3FAF6)
        : hasCerts
        ? const Color(0xFF5F4100)
        : AppTheme.inkSoft;
    final badgeBorder = isVerified
        ? const Color(0xFF1F664C)
        : hasCerts
        ? const Color(0xFFC58C1F)
        : AppTheme.border;
    final badgeIcon = isVerified
        ? Icons.verified_user_rounded
        : hasCerts
        ? Icons.workspace_premium_outlined
        : Icons.info_outline_rounded;

    return Container(
      key: const ValueKey('trazabilidad.publica.header'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppTheme.border),
        boxShadow: AppTheme.stamp(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const BrandMark(size: 38),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AgroFusion · Consulta pública',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: AppTheme.fieldDeep,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Trazabilidad del campo al punto de venta',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Semantics(
            header: true,
            child: Text(
              reporte.producto,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: AppTheme.ink,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.sprout,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppTheme.sproutBorder),
                ),
                child: Text(
                  reporte.codigo,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: AppTheme.fieldDeep,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                key: const ValueKey('trazabilidad.publica.certificacion_badge'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: badgeBorder),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(badgeIcon, size: 16, color: badgeFg),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        reporte.estadoCertificacionLabel,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: badgeFg,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (reporte.blockchainHash != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.paper,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    reporte.blockchainRed != null
                        ? 'Respaldo blockchain · ${reporte.blockchainRed}'
                        : 'Respaldo blockchain',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppTheme.inkSoft,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    reporte.blockchainHash!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: AppTheme.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetadataCard(
    BuildContext context,
    TrazabilidadPublicaReporte reporte,
  ) {
    final theme = Theme.of(context);
    final rows = <(String, String)>[
      if (reporte.loteAgricola != null)
        (
          'Origen agrícola',
          reporte.loteCodigo != null
              ? '${reporte.loteAgricola} (${reporte.loteCodigo})'
              : reporte.loteAgricola!,
        ),
      if (reporte.puntoVenta != null) ('Punto de venta', reporte.puntoVenta!),
      if (reporte.minorista != null) ('Minorista', reporte.minorista!),
      if (reporte.pedido != null) ('Pedido vinculado', reporte.pedido!),
      if (reporte.stockActual != null)
        (
          'Disponibilidad en tienda',
          '${_formatQuantity(reporte.stockActual!)} ${reporte.unidad ?? 'ud'}',
        ),
      (
        'Eventos registrados',
        '${reporte.totalEventos} ${reporte.totalEventos == 1 ? 'hito' : 'hitos'} en la cadena',
      ),
    ];

    return Container(
      key: const ValueKey('trazabilidad.publica.metadatos'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ficha del producto',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 18),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rows[i].$1,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppTheme.inkSoft,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  rows[i].$2,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppTheme.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCertificationsCard(
    BuildContext context,
    TrazabilidadPublicaReporte reporte,
  ) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('trazabilidad.publica.certificaciones'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.verified_outlined,
                color: AppTheme.fieldDeep,
                size: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Certificaciones y respaldo',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (reporte.certificaciones.isEmpty)
            Text(
              'Este producto no registra certificaciones adicionales ni sello blockchain por el momento.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppTheme.inkSoft,
              ),
            )
          else
            for (var i = 0; i < reporte.certificaciones.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              _buildCertificationItem(context, reporte.certificaciones[i]),
            ],
        ],
      ),
    );
  }

  Widget _buildCertificationItem(
    BuildContext context,
    TrazabilidadCertificacion cert,
  ) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.paper,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            cert.nombre,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: AppTheme.ink,
            ),
          ),
          if (cert.entidad != null || cert.codigo != null) ...[
            const SizedBox(height: 4),
            Text(
              [
                if (cert.entidad != null) cert.entidad!,
                if (cert.codigo != null) 'Código: ${cert.codigo}',
              ].join(' · '),
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (cert.estado != null || cert.fecha != null) ...[
            const SizedBox(height: 4),
            Text(
              [
                if (cert.estado != null) 'Estado: ${cert.estado}',
                if (cert.fecha != null) 'Fecha: ${cert.fecha}',
              ].join(' · '),
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (cert.txHash != null) ...[
            const SizedBox(height: 8),
            Text(
              cert.red != null
                  ? 'Hash (${cert.red}): ${cert.txHash}'
                  : 'Hash: ${cert.txHash}',
              style: theme.textTheme.labelSmall?.copyWith(
                fontFamily: 'monospace',
                color: AppTheme.fieldDeep,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTimelineSection(
    BuildContext context,
    TrazabilidadPublicaReporte reporte,
  ) {
    final theme = Theme.of(context);
    final trimmedQuery = _query.trim();
    final filteredStages = <TrazabilidadEtapaGrupo>[];
    var matchingCount = 0;

    for (final stage in reporte.etapas) {
      final matches = trimmedQuery.isEmpty
          ? stage.eventos
          : stage.eventos
                .where((event) => event.matchesQuery(trimmedQuery))
                .toList();
      if (matches.isNotEmpty) {
        matchingCount += matches.length;
        filteredStages.add(
          TrazabilidadEtapaGrupo(
            key: stage.key,
            label: stage.label,
            eventos: matches,
          ),
        );
      }
    }

    return Column(
      key: const ValueKey('trazabilidad.publica.timeline'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Recorrido del producto',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Campo → Planta → Mayorista → Distribución → Punto de venta',
                style: theme.textTheme.bodySmall,
              ),
              if (reporte.etapas.isNotEmpty) ...[
                const SizedBox(height: 14),
                TextField(
                  key: const ValueKey('trazabilidad.publica.buscar'),
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    labelText: 'Buscar en el recorrido',
                    hintText: 'Ej. siembra, cosecha, planta, recepción...',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: trimmedQuery.isEmpty
                        ? null
                        : IconButton(
                            key: const ValueKey(
                              'trazabilidad.publica.buscar_limpiar',
                            ),
                            tooltip: 'Limpiar búsqueda',
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _query = '');
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
                if (trimmedQuery.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    '$matchingCount ${matchingCount == 1 ? 'coincidencia' : 'coincidencias'} para "$trimmedQuery"',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.fieldDeep,
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (reporte.etapas.isEmpty)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppTheme.border),
            ),
            child: Text(
              'Aún no hay eventos registrados en el recorrido de este producto.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppTheme.inkSoft,
              ),
            ),
          )
        else if (filteredStages.isEmpty)
          Container(
            key: const ValueKey('trazabilidad.publica.sin_coincidencias'),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppTheme.maizeSoft,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFC58C1F)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sin coincidencias en el recorrido',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: const Color(0xFF5F4100),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'No encontramos eventos que coincidan con "$trimmedQuery".',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF5F4100),
                  ),
                ),
              ],
            ),
          )
        else
          for (var i = 0; i < filteredStages.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            _buildStageCard(
              context,
              filteredStages[i],
              forceExpanded: trimmedQuery.isNotEmpty,
            ),
          ],
      ],
    );
  }

  Widget _buildStageCard(
    BuildContext context,
    TrazabilidadEtapaGrupo stage, {
    required bool forceExpanded,
  }) {
    final theme = Theme.of(context);
    final style = _stageVisual(stage.key);
    final isExpanded = forceExpanded || !_collapsedStages.contains(stage.key);

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            key: ValueKey('trazabilidad.etapa.${stage.key}'),
            onTap: forceExpanded
                ? null
                : () {
                    setState(() {
                      if (_collapsedStages.contains(stage.key)) {
                        _collapsedStages.remove(stage.key);
                      } else {
                        _collapsedStages.add(stage.key);
                      }
                    });
                  },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: style.headerBg,
                border: Border(
                  left: BorderSide(color: style.accent, width: 4),
                  bottom: isExpanded
                      ? const BorderSide(color: AppTheme.line)
                      : BorderSide.none,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: style.chipBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(style.icon, color: style.accent, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      stage.label,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppTheme.ink,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: style.chipBg,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${stage.total}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: style.accent,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    isExpanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: AppTheme.inkSoft,
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < stage.eventos.length; i++)
                    _buildEventItem(
                      context,
                      stage.eventos[i],
                      accent: style.accent,
                      chipBg: style.chipBg,
                      isLast: i == stage.eventos.length - 1,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEventItem(
    BuildContext context,
    TrazabilidadEvento event, {
    required Color accent,
    required Color chipBg,
    required bool isLast,
  }) {
    final theme = Theme.of(context);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: chipBg,
                    shape: BoxShape.circle,
                    border: Border.all(color: accent, width: 1.5),
                  ),
                  child: Text(
                    '${event.paso}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                    ),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: AppTheme.line,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.titulo,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppTheme.ink,
                    ),
                  ),
                  if (event.fechaFmt != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      event.fechaFmt!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppTheme.inkSoft,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (event.ubicacion != null || event.referencia != null) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (event.ubicacion != null)
                          _infoPill(
                            context,
                            Icons.place_outlined,
                            event.ubicacion!,
                          ),
                        if (event.referencia != null)
                          _infoPill(
                            context,
                            Icons.tag_rounded,
                            event.referencia!,
                          ),
                      ],
                    ),
                  ],
                  if (event.descripcionLineas.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    for (final linea in event.descripcionLineas)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(linea, style: theme.textTheme.bodyMedium),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoPill(BuildContext context, IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.paper,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.inkSoft),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppTheme.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  ({Color accent, Color chipBg, Color headerBg, IconData icon}) _stageVisual(
    String key,
  ) => switch (key.toLowerCase()) {
    'agricola' => (
      accent: const Color(0xFF1F6642),
      chipBg: const Color(0xFFDCEBD3),
      headerBg: const Color(0xFFF3F8EF),
      icon: Icons.eco_outlined,
    ),
    'planta' => (
      accent: const Color(0xFF623CEA),
      chipBg: const Color(0xFFECE6FF),
      headerBg: const Color(0xFFF7F4FF),
      icon: Icons.precision_manufacturing_outlined,
    ),
    'mayorista' => (
      accent: const Color(0xFF0F766E),
      chipBg: const Color(0xFFD7F3EF),
      headerBg: const Color(0xFFF1FBF9),
      icon: Icons.warehouse_outlined,
    ),
    'distribucion' => (
      accent: AppTheme.sky,
      chipBg: AppTheme.skySoft,
      headerBg: const Color(0xFFF2F7FB),
      icon: Icons.local_shipping_outlined,
    ),
    'pdv' => (
      accent: const Color(0xFF9A5B00),
      chipBg: AppTheme.maizeSoft,
      headerBg: const Color(0xFFFFF8E8),
      icon: Icons.storefront_outlined,
    ),
    _ => (
      accent: AppTheme.fieldDeep,
      chipBg: AppTheme.sprout,
      headerBg: AppTheme.paper,
      icon: Icons.timeline_rounded,
    ),
  };

  String _formatQuantity(double value) {
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(2);
  }
}
