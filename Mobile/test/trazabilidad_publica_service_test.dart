import 'dart:convert';

import 'package:agrofusion_mobile/config/api_config.dart';
import 'package:agrofusion_mobile/models/trazabilidad_publica_models.dart';
import 'package:agrofusion_mobile/services/api_client.dart';
import 'package:agrofusion_mobile/services/session_storage.dart';
import 'package:agrofusion_mobile/services/trazabilidad_publica_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const storage = SessionStorage();

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test(
    'consultarReporte consulta GET /api/trazabilidad/{codigo} sin Bearer y parsea etapas, certificaciones, blockchain y mapas',
    () async {
      await storage.saveToken('1|token-privado-no-debe-enviarse');
      String? authHeader;
      String? requestedPath;

      final api = ApiClient(
        config: ApiConfig(baseUrl: 'https://agrofusion.test/api'),
        sessionStorage: storage,
        client: MockClient((request) async {
          authHeader = request.headers['Authorization'];
          requestedPath = request.url.path;
          return http.Response(
            jsonEncode({
              'data': {
                'codigo': 'TRZ-PDV-20261124-ABC123',
                'producto': 'Hojuelas de Papa 500 g',
                'stock_actual': 24.5,
                'unidad': 'bolsas',
                'punto_venta': 'Mercado Central',
                'minorista': 'Tienda La Esperanza',
                'lote_agricola': 'Parcela Norte',
                'lote_codigo': 'TRZ-LOTE-01',
                'pedido': 'PDV-2026-045',
                'total_eventos': 2,
                'certificaciones': [
                  {
                    'nombre': 'Certificación Orgánica SENASAG',
                    'entidad': 'SENASAG',
                    'codigo': 'CERT-2026-99',
                    'estado': 'vigente',
                    'blockchain_status': 'confirmado',
                    'tx_hash': '0xabc123def456',
                    'red': 'Polygon Amoy',
                  },
                ],
                'eventos_agrupados': [
                  {
                    'key': 'agricola',
                    'label': 'Producción agrícola',
                    'eventos': [
                      {
                        'paso': 1,
                        'fecha_fmt': '10/11/2026 08:30',
                        'titulo': 'Siembra registrada',
                        'descripcion_lineas': ['Semilla certificada Huaycha'],
                        'ubicacion': 'Parcela Norte',
                        'evidencia_foto_url': '/storage/evidencias/siembra.jpg',
                      },
                    ],
                  },
                  {
                    'key': 'distribucion',
                    'label': 'Distribución al PDV',
                    'eventos': [
                      {
                        'paso': 2,
                        'fecha_fmt': '20/11/2026 14:00',
                        'titulo': 'Entrega en tienda',
                        'descripcion': 'Recibido conforme',
                        'ubicacion': 'Mercado Central',
                        'mapa_ruta': [
                          {
                            'lat': -17.3935,
                            'lng': -66.1570,
                            'orden': 1,
                            'label': 'Planta AgroFusion',
                          },
                          {
                            'lat': -17.3895,
                            'lng': -66.1568,
                            'orden': 2,
                            'label': 'Mercado Central',
                          },
                        ],
                      },
                    ],
                  },
                ],
              },
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      addTearDown(api.close);

      final service = TrazabilidadPublicaService(api);
      final reporte = await service.consultarReporte(
        'https://agrofusion.test/trazabilidad/trz-pdv-20261124-abc123',
      );

      expect(requestedPath, '/api/trazabilidad/TRZ-PDV-20261124-ABC123');
      expect(authHeader, isNull);
      expect(reporte.producto, 'Hojuelas de Papa 500 g');
      expect(reporte.loteAgricola, 'Parcela Norte');
      expect(reporte.loteCodigo, 'TRZ-LOTE-01');
      expect(reporte.puntoVenta, 'Mercado Central');
      expect(reporte.blockchainVerificado, isTrue);
      expect(reporte.blockchainHash, '0xabc123def456');
      expect(reporte.blockchainRed, 'Polygon Amoy');
      expect(reporte.certificaciones, hasLength(1));
      expect(reporte.etapas, hasLength(2));
      expect(reporte.etapas.first.eventos.first.primaryPhotoUrl, isNotNull);
      expect(reporte.etapas.last.eventos.first.mapaRuta, hasLength(2));
      expect(
        reporte.etapas.first.eventos.first.matchesQuery('huaycha'),
        isTrue,
      );
      expect(
        reporte.etapas.first.eventos.first.matchesQuery('inexistente'),
        isFalse,
      );
      expect(
        service.buildPublicWebUrl(reporte.codigo).toString(),
        'https://agrofusion.test/trazabilidad/TRZ-PDV-20261124-ABC123',
      );
      expect(
        service
            .resolvePublicAssetUrl('/storage/evidencias/siembra.jpg')
            .toString(),
        'https://agrofusion.test/storage/evidencias/siembra.jpg',
      );
    },
  );

  test(
    'Agrupa automáticamente eventos planos en orden de cadena cuando no llega eventos_agrupados',
    () {
      final reporte = TrazabilidadPublicaReporte.fromJson({
        'codigo': 'TRZ-PDV-20261124-FLAT01',
        'producto': 'Papa Lavada',
        'eventos': [
          {
            'etapa': 'pdv',
            'titulo': 'Disponible en tienda',
            'fecha_fmt': '22/11/2026 10:00',
          },
          {
            'etapa': 'agricola',
            'titulo': 'Cosecha del lote',
            'fecha_fmt': '15/11/2026 09:00',
          },
          {
            'etapa': 'planta',
            'titulo': 'Lavado y empaque',
            'fecha_fmt': '18/11/2026 11:00',
          },
        ],
      }, fallbackCode: 'TRZ-PDV-20261124-FLAT01');

      expect(reporte.etapas.map((e) => e.key).toList(), [
        'agricola',
        'planta',
        'pdv',
      ]);
      expect(reporte.blockchainVerificado, isFalse);
      expect(
        reporte.estadoCertificacionLabel,
        'Sin certificación blockchain registrada',
      );
    },
  );
}
