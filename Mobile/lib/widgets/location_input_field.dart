import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'action_confirmation.dart';
import 'form_validation.dart';

class DeviceLocation {
  const DeviceLocation({
    required this.latitude,
    required this.longitude,
    this.address,
  });

  final double latitude;
  final double longitude;
  final String? address;

  String get formattedCoordinates =>
      '${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)}';
}

class LocationPermissionException implements Exception {
  const LocationPermissionException([
    this.message =
        'El teléfono no permitió obtener la ubicación actual. Puedes introducir la ubicación manualmente para continuar.',
  ]);

  final String message;

  static bool isPermissionError(Object error) {
    if (error is LocationPermissionException) return true;
    if (error is PlatformException) {
      final code = error.code.toLowerCase();
      return code.contains('permission') ||
          code.contains('location') ||
          code.contains('denied') ||
          code.contains('disabled');
    }
    return false;
  }

  static String messageFor(Object error) {
    if (error is LocationPermissionException) return error.message;
    return 'El teléfono no permitió obtener la ubicación actual. Puedes introducir la ubicación manualmente para continuar.';
  }
}

String? validateLatitude(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return null;
  final parsed = double.tryParse(text.replaceAll(',', '.'));
  if (parsed == null || parsed < -90 || parsed > 90) {
    return 'Ingresa una latitud entre -90 y 90.';
  }
  return null;
}

String? validateLongitude(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return null;
  final parsed = double.tryParse(text.replaceAll(',', '.'));
  if (parsed == null || parsed < -180 || parsed > 180) {
    return 'Ingresa una longitud entre -180 y 180.';
  }
  return null;
}

class LocationInputField extends StatefulWidget {
  const LocationInputField({
    super.key,
    required this.controller,
    this.latitudeController,
    this.longitudeController,
    this.requestLocation,
    this.onLocationChanged,
    this.onCoordinatesChanged,
    this.labelText = 'Ubicación',
    this.hintText = 'Ej. Sector norte, Parcela Los Pinos',
    this.helperText =
        'Puedes usar el GPS del teléfono o escribir la referencia del lugar.',
    this.requiredField = false,
    this.enabled = true,
    this.allowManualCoordinates = true,
    this.locationError,
    this.latitudeError,
    this.longitudeError,
  });

  final TextEditingController controller;
  final TextEditingController? latitudeController;
  final TextEditingController? longitudeController;
  final Future<DeviceLocation?> Function()? requestLocation;
  final ValueChanged<String>? onLocationChanged;
  final ValueChanged<DeviceLocation?>? onCoordinatesChanged;
  final String labelText;
  final String hintText;
  final String helperText;
  final bool requiredField;
  final bool enabled;
  final bool allowManualCoordinates;
  final String? locationError;
  final String? latitudeError;
  final String? longitudeError;

  @override
  State<LocationInputField> createState() => _LocationInputFieldState();
}

class _LocationInputFieldState extends State<LocationInputField> {
  final _locationFocus = FocusNode();
  late final TextEditingController _latController =
      widget.latitudeController ?? TextEditingController();
  late final TextEditingController _lngController =
      widget.longitudeController ?? TextEditingController();
  bool _locating = false;
  bool _showManualCoordinates = false;
  String? _permissionMessage;
  DeviceLocation? _captured;

  @override
  void initState() {
    super.initState();
    final initial = _parseCoordinates();
    if (initial != null) {
      _captured = initial;
    }
  }

  @override
  void dispose() {
    _locationFocus.dispose();
    if (widget.latitudeController == null) _latController.dispose();
    if (widget.longitudeController == null) _lngController.dispose();
    super.dispose();
  }

  DeviceLocation? _parseCoordinates() {
    final lat = double.tryParse(_latController.text.trim().replaceAll(',', '.'));
    final lng = double.tryParse(_lngController.text.trim().replaceAll(',', '.'));
    if (lat != null &&
        lng != null &&
        lat >= -90 &&
        lat <= 90 &&
        lng >= -180 &&
        lng <= 180) {
      return DeviceLocation(
        latitude: lat,
        longitude: lng,
        address: widget.controller.text.trim().isEmpty
            ? null
            : widget.controller.text.trim(),
      );
    }
    return null;
  }

  Future<void> _useDeviceLocation() async {
    if (_locating || !widget.enabled) return;
    setState(() {
      _locating = true;
      _permissionMessage = null;
    });
    try {
      final request = widget.requestLocation;
      if (request == null) {
        throw const LocationPermissionException();
      }
      final location = await request();
      if (!mounted || location == null) return;
      _latController.text = location.latitude.toStringAsFixed(6);
      _lngController.text = location.longitude.toStringAsFixed(6);
      if (location.address != null && location.address!.trim().isNotEmpty) {
        widget.controller.text = location.address!.trim();
        widget.onLocationChanged?.call(widget.controller.text);
      } else if (widget.controller.text.trim().isEmpty) {
        widget.controller.text =
            'Ubicación registrada (${location.formattedCoordinates})';
        widget.onLocationChanged?.call(widget.controller.text);
      }
      setState(() {
        _captured = location;
        _permissionMessage = null;
      });
      widget.onCoordinatesChanged?.call(location);
    } catch (error) {
      if (!mounted) return;
      if (LocationPermissionException.isPermissionError(error)) {
        setState(() {
          _permissionMessage = LocationPermissionException.messageFor(error);
          if (widget.allowManualCoordinates) {
            _showManualCoordinates = true;
          }
        });
        _locationFocus.requestFocus();
      } else {
        setState(() {
          _permissionMessage =
              'No se pudo obtener la ubicación del dispositivo. Intenta de nuevo o escríbela manualmente.';
        });
        _locationFocus.requestFocus();
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _syncManualCoordinates() {
    final updated = _parseCoordinates();
    setState(() => _captured = updated);
    widget.onCoordinatesChanged?.call(updated);
  }

  void _clearCoordinates() {
    _latController.clear();
    _lngController.clear();
    setState(() => _captured = null);
    widget.onCoordinatesChanged?.call(null);
  }

  @override
  Widget build(BuildContext context) {
    final busy = _locating || !widget.enabled;
    final scrollPadding = formScrollPadding(context);
    final showCoords =
        _showManualCoordinates ||
        widget.latitudeError != null ||
        widget.longitudeError != null ||
        _latController.text.isNotEmpty ||
        _lngController.text.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          key: const ValueKey('location.ubicacion'),
          controller: widget.controller,
          focusNode: _locationFocus,
          scrollPadding: scrollPadding,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          forceErrorText: widget.locationError,
          enabled: widget.enabled,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: widget.labelText,
            hintText: widget.hintText,
            helperText: widget.helperText,
            prefixIcon: const Icon(Icons.place_outlined),
          ),
          validator: (value) {
            final text = value?.trim() ?? '';
            if (widget.requiredField && text.isEmpty && _captured == null) {
              return 'Ingresa la ubicación o regístrala con el dispositivo.';
            }
            return null;
          },
          onChanged: (value) => widget.onLocationChanged?.call(value),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: busy ? null : _useDeviceLocation,
              icon: _locating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location_rounded, size: 18),
              label: Text(
                _locating
                    ? 'Obteniendo ubicación...'
                    : 'Usar ubicación actual',
              ),
            ),
            if (widget.allowManualCoordinates)
              TextButton.icon(
                onPressed: !widget.enabled
                    ? null
                    : () => setState(
                        () => _showManualCoordinates = !showCoords,
                      ),
                icon: Icon(
                  showCoords
                      ? Icons.expand_less_rounded
                      : Icons.edit_location_alt_outlined,
                  size: 18,
                ),
                label: Text(
                  showCoords
                      ? 'Ocultar coordenadas'
                      : 'Introducir coordenadas manualmente',
                ),
              ),
          ],
        ),
        if (_captured case final location?) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.sage,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.gps_fixed_rounded,
                  size: 18,
                  color: AppTheme.forest,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Coordenadas registradas: ${location.formattedCoordinates}',
                    style: const TextStyle(
                      color: AppTheme.forest,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (widget.allowManualCoordinates)
                  IconButton(
                    tooltip: 'Quitar coordenadas',
                    onPressed: !widget.enabled ? null : _clearCoordinates,
                    icon: const Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: AppTheme.forest,
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (_permissionMessage case final message?) ...[
          const SizedBox(height: 12),
          AppNotice(
            tone: AppNoticeTone.warning,
            title: 'Permiso de ubicación denegado',
            message: message,
            action: TextButton.icon(
              onPressed: !widget.enabled
                  ? null
                  : () {
                      setState(() {
                        if (widget.allowManualCoordinates) {
                          _showManualCoordinates = true;
                        }
                      });
                      _locationFocus.requestFocus();
                    },
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Escribir ubicación manualmente'),
            ),
          ),
        ],
        if (showCoords && widget.allowManualCoordinates) ...[
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final sideBySide =
                  constraints.maxWidth >= 320 &&
                  MediaQuery.textScalerOf(context).scale(16) <= 22;
              final fieldWidth = sideBySide
                  ? (constraints.maxWidth - 12) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 12,
                runSpacing: 16,
                children: [
                  SizedBox(
                    width: fieldWidth,
                    child: TextFormField(
                      key: const ValueKey('location.latitud'),
                      controller: _latController,
                      scrollPadding: scrollPadding,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      forceErrorText: widget.latitudeError,
                      enabled: widget.enabled,
                      keyboardType: const TextInputType.numberWithOptions(
                        signed: true,
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Latitud (opcional)',
                        hintText: '-17.7833',
                      ),
                      validator: (value) {
                        final rangeError = validateLatitude(value);
                        if (rangeError != null) return rangeError;
                        final hasLat = value != null && value.trim().isNotEmpty;
                        final hasLng = _lngController.text.trim().isNotEmpty;
                        if (!hasLat && hasLng) {
                          return 'Indica también la latitud o deja ambas vacías.';
                        }
                        return null;
                      },
                      onChanged: (_) => _syncManualCoordinates(),
                    ),
                  ),
                  SizedBox(
                    width: fieldWidth,
                    child: TextFormField(
                      key: const ValueKey('location.longitud'),
                      controller: _lngController,
                      scrollPadding: scrollPadding,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      forceErrorText: widget.longitudeError,
                      enabled: widget.enabled,
                      keyboardType: const TextInputType.numberWithOptions(
                        signed: true,
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Longitud (opcional)',
                        hintText: '-63.1821',
                      ),
                      validator: (value) {
                        final rangeError = validateLongitude(value);
                        if (rangeError != null) return rangeError;
                        final hasLng = value != null && value.trim().isNotEmpty;
                        final hasLat = _latController.text.trim().isNotEmpty;
                        if (!hasLng && hasLat) {
                          return 'Indica también la longitud o deja ambas vacías.';
                        }
                        return null;
                      },
                      onChanged: (_) => _syncManualCoordinates(),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ],
    );
  }
}
