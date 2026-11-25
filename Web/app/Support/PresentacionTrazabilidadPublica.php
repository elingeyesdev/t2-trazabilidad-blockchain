<?php

namespace App\Support;

/** Display labels only. Certification and lineage decisions belong to the public services. */
final class PresentacionTrazabilidadPublica
{
    public static function texto(?string $valor): string
    {
        return [
            'agricola' => 'Agricultura', 'planta' => 'Planta', 'mayorista' => 'Mayorista',
            'distribucion' => 'Distribución', 'pdv' => 'Punto de venta',
            'lote_registrado' => 'Lote registrado', 'actividad_lote_origen' => 'Actividad del lote de origen',
            'cosecha' => 'Cosecha registrada', 'produccion_registrada' => 'Producción registrada',
            'consumo_registrado' => 'Materia prima utilizada', 'etapa_registrada' => 'Etapa de planta registrada',
            'ingreso_produccion' => 'Ingreso de producción', 'recepcion_agricola' => 'Recepción agrícola',
            'envio_agricola' => 'Envío agrícola', 'traslado_registrado' => 'Traslado registrado',
            'recepcion_registrada' => 'Recepción registrada', 'envio_registrado' => 'Envío registrado',
            'campo' => 'Campo', 'registro' => 'registro', 'recepcion' => 'recepción',
            'asignacion' => 'asignación', 'registro_cierre' => 'cierre registrado',
            'pedido_distribucion' => 'Pedido de distribución', 'partida_registrada' => 'Partida registrada',
            'movimiento_registrado' => 'Movimiento registrado',
            'pendiente' => 'Pendiente', 'completada' => 'Completada', 'confirmado' => 'Confirmado',
            'en_transito' => 'En tránsito', 'entregado' => 'Entregado', 'recibido' => 'Recibido',
            'rechazado' => 'Rechazado', 'cancelado' => 'Cancelado', 'asignado' => 'Asignado',
        ][$valor ?? ''] ?? ($valor ? ucfirst(str_replace('_', ' ', $valor)) : 'No registrado');
    }

    public static function campos(array $registro): array
    {
        $etiquetas = [
            'codigo_lote' => 'Código de lote', 'codigo_producto' => 'Código de producto',
            'codigo_origen_agricola' => 'Origen agrícola vinculado', 'codigo_origen_industrial' => 'Origen industrial vinculado',
            'codigo_pedido' => 'Pedido', 'referencia' => 'Referencia del registro',
            'referencia_envio' => 'Envío relacionado', 'referencia_partida' => 'Partida',
            'referencia_cosecha' => 'Cosecha vinculada', 'referencia_partida_origen' => 'Partida de origen',
            'cultivo' => 'Cultivo', 'actividad' => 'Actividad', 'proceso' => 'Proceso',
            'producto' => 'Producto', 'presentacion' => 'Presentación', 'estado' => 'Estado registrado',
            'fecha' => 'Fecha de '.self::texto($registro['fecha_tipo'] ?? 'registro'),
            'fecha_siembra' => 'Siembra', 'fecha_programada' => 'Fecha programada',
            'fecha_inicio' => 'Inicio registrado', 'fecha_fin' => 'Fin registrado',
            'fecha_envio' => 'Envío registrado', 'fecha_salida' => 'Salida registrada (puede ser programada)',
            'fecha_llegada' => 'Llegada registrada', 'fecha_recepcion' => 'Recepción registrada',
        ];
        $campos = [];
        foreach ($etiquetas as $clave => $etiqueta) {
            if (! array_key_exists($clave, $registro)) {
                continue;
            }
            $valor = $registro[$clave];
            $campos[$etiqueta] = $valor === null || $valor === '' ? 'No registrado'
                : ($clave === 'estado' ? self::texto($valor) : $valor);
        }
        foreach (['cantidad' => 'Cantidad', 'cantidad_base' => 'Cantidad base', 'cantidad_consumida' => 'Cantidad consumida',
            'cantidad_recibida' => 'Cantidad recibida', 'cantidad_kg' => 'Peso',
            'cantidad_unidades' => 'Unidades', 'cantidad_unidades_consumidas' => 'Unidades consumidas'] as $clave => $etiqueta) {
            if (! array_key_exists($clave, $registro)) {
                continue;
            }
            $unidad = match ($clave) {
                'cantidad_kg' => 'kg',
                'cantidad_unidades', 'cantidad_unidades_consumidas' => 'unidades',
                'cantidad_recibida' => $registro['unidad_recepcion'] ?? $registro['unidad'] ?? 'unidad no registrada',
                default => $registro['unidad'] ?? $registro['presentacion'] ?? 'unidad no registrada',
            };
            $campos[$etiqueta] = $registro[$clave] === null ? 'No registrada' : $registro[$clave].' '.$unidad;
        }

        return $campos;
    }
}
