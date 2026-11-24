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
  TrazabilidadPublicaReporte? _reporte;
  bool _loading = false;
  bool _notFound = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reporte = widget.initialReporte;
    if (_reporte == null) {
      unawaited(_load());
    }
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

  String _formatQuantity(double value) {
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(2);
  }
}
