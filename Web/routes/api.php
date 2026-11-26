<?php

use Illuminate\Support\Facades\Route;

use App\Http\Controllers\Api\TipoActividadController;
use App\Http\Controllers\Api\PrioridadController;
use App\Http\Controllers\Api\TipoInsumoController;
use App\Http\Controllers\Api\UnidadMedidaController;
use App\Http\Controllers\Api\CultivoController;
use App\Http\Controllers\Api\EstadoLoteTipoController;
use App\Http\Controllers\Api\DestinoProduccionController;
use App\Http\Controllers\Api\EstadoLoteInsumoController;
use App\Http\Controllers\Api\HistorialEstadoLoteController;
use App\Http\Controllers\Api\PedidoController;

use App\Http\Controllers\Api\RolController;
use App\Http\Controllers\Api\UsuarioController;
use App\Http\Controllers\Api\UsuarioRolController;

use App\Http\Controllers\Api\LoteController;
use App\Http\Controllers\Api\EstadoLoteController;
use App\Http\Controllers\Api\ProduccionController;

use App\Http\Controllers\Api\InsumoController;
use App\Http\Controllers\Api\LoteInsumoController;
use App\Http\Controllers\Api\ActividadController;

use App\Http\Controllers\Api\ClimaController;
use App\Http\Controllers\Api\CertificacionController;

use App\Http\Controllers\Api\AuthController;
use App\Http\Controllers\Api\PerfilUsuarioController;
use App\Http\Controllers\Api\IncidenteEnvioController;
use App\Http\Controllers\Api\RutaMultiEntregaController;
use App\Http\Controllers\Api\AsignacionMultipleController;
use App\Http\Controllers\Api\DocumentoEntregaController;
use App\Http\Controllers\Api\AlmacenMovimientoController;

// 🔹 nuevos controladores API
use App\Http\Controllers\Api\TipoAlmacenController;
use App\Http\Controllers\Api\AlmacenController;
use App\Http\Controllers\Api\ProduccionAlmacenamientoController;

/**
 * Registra un apiResource exigiendo auth:sanctum y el permiso de la matriz según el verbo:
 * index/show → read, store → create, update → update, destroy → delete.
 * Si $accionUnica se indica, todos los verbos exigen esa acción (p. ej. usuarios,admin).
 */
$recursoProtegido = function (string $uri, string $controller, string $modulo, ?string $accionUnica = null): void {
    $verbos = [
        'read' => ['index', 'show'],
        'create' => ['store'],
        'update' => ['update'],
        'delete' => ['destroy'],
    ];

    foreach ($verbos as $accion => $metodos) {
        Route::apiResource($uri, $controller)
            ->only($metodos)
            ->middleware(['auth:sanctum', 'action.permission:'.$modulo.','.($accionUnica ?? $accion)]);
    }
};

Route::name('api.')->group(function () use ($recursoProtegido) {
    Route::get('trazabilidad/evidencias/{token}', function (string $token, \App\Services\EvidenciaPublicacionService $service) {
        return $service->archivoPublico($token);
    })->middleware('throttle:trazabilidad-publica')->name('trazabilidad.evidencia');

    Route::get('trazabilidad/{codigo}', [\App\Http\Controllers\Api\TrazabilidadPublicaController::class, 'show'])
        ->middleware('throttle:trazabilidad-publica')->name('trazabilidad.publica');

    Route::prefix('evidencias-publicacion')->middleware('auth:sanctum')->group(function () {
        $controller = \App\Http\Controllers\Api\EvidenciaPublicacionController::class;
        Route::get('/', [$controller, 'index'])->name('evidencias-publicacion.index');
        Route::post('actividades/{actividad}/solicitar', [$controller, 'solicitar'])->whereNumber('actividad')->name('evidencias-publicacion.solicitar');
        Route::get('{publicacion}/archivo', [$controller, 'archivo'])->whereNumber('publicacion')->name('evidencias-publicacion.archivo');
        Route::post('{publicacion}/aprobar', [$controller, 'aprobar'])->whereNumber('publicacion')->name('evidencias-publicacion.aprobar');
        Route::post('{publicacion}/solicitar-retiro', [$controller, 'solicitarRetiro'])->whereNumber('publicacion')->name('evidencias-publicacion.solicitar-retiro');
        Route::post('{publicacion}/retirar', [$controller, 'retirar'])->whereNumber('publicacion')->name('evidencias-publicacion.retirar');
    });

    Route::get('consulta-recorrido', [\App\Http\Controllers\RecorridoConsultaController::class, 'index'])
        ->middleware('auth:sanctum')->name('consulta-recorrido');

    Route::middleware('auth:sanctum')->group(function () {
        $controller = \App\Http\Controllers\Api\EnvioMovilController::class;
        Route::post('envios/qr/resolver', [$controller, 'resolver']);
        Route::get('envios/{tipo}', [$controller, 'index'])->where('tipo', 'agricola|distribucion|traslado');
        Route::get('envios/{tipo}/{envio}', [$controller, 'show'])->whereNumber('envio')->where('tipo', 'agricola|distribucion|traslado');
        Route::post('envios/{tipo}/{envio}/codigos', [$controller, 'codigos'])->whereNumber('envio')->where('tipo', 'agricola|distribucion|traslado');
        Route::post('envios/{tipo}/{envio}/recepcion', [$controller, 'confirmar'])->whereNumber('envio')->where('tipo', 'agricola|distribucion|traslado');
        Route::get('recepciones-envio/{recepcion}', [$controller, 'recepcion'])->whereNumber('recepcion');
        Route::get('recepciones-envio/{recepcion}/firma', [$controller, 'firma'])->whereNumber('recepcion');
        Route::get('recepciones-envio/{recepcion}/comprobante', [$controller, 'comprobante'])->whereNumber('recepcion');
    });

    Route::prefix('planta')->middleware('auth:sanctum')->group(function () {
        $controller = \App\Http\Controllers\Api\PlantaTrabajoController::class;
        Route::get('lotes-produccion/{loteProduccion}', [\App\Http\Controllers\Api\ProduccionPlantaRecorridoController::class, 'show'])->whereNumber('loteProduccion')->middleware('action.permission:lote_produccion,read');
        Route::get('lotes-produccion/{loteProduccion}/tareas/{asignacion}', [$controller, 'tareaAnidada'])->whereNumber(['loteProduccion', 'asignacion'])->middleware('action.permission:lote_produccion,read');
        Route::get('tareas', [$controller, 'tareas'])->middleware('action.permission:lote_produccion,read');
        Route::get('tareas/{asignacion}', [$controller, 'tarea'])->whereNumber('asignacion')->middleware('action.permission:lote_produccion,read');
        Route::post('lotes-produccion/{loteProduccion}/tareas/{asignacion}/completar', [$controller, 'completar'])
            ->whereNumber(['loteProduccion', 'asignacion'])->middleware('action.permission:lote_produccion,read');
        Route::get('recepciones', [$controller, 'recepciones'])->middleware('action.permission:recepcion_planta,read');
        Route::get('recepciones/{pedido}', [$controller, 'recepcion'])->whereNumber('pedido')->middleware('action.permission:recepcion_planta,read');
        Route::post('recepciones/{pedido}/confirmar', [$controller, 'confirmar'])->whereNumber('pedido')->middleware('action.permission:recepcion_planta,confirm');
    });

    // Read-only options for already-authorized operations; no global users/catalog grant.
    Route::get('catalogos-operativos/{catalogo}', [\App\Http\Controllers\Api\SelectorOperativoController::class, 'catalogo'])
        ->whereIn('catalogo', ['tipoactividades', 'prioridades', 'unidadesmedida'])->middleware('auth:sanctum');
    Route::get('actividades/responsables', [\App\Http\Controllers\Api\SelectorOperativoController::class, 'responsablesActividad'])
        ->middleware(['auth:sanctum', 'action.permission:lotes,read']);
    Route::get('punto-venta/inventario', [InsumoController::class, 'indexPdv'])
        ->middleware(['auth:sanctum', 'action.permission:punto_venta,read']);
    Route::get('punto-venta/inventario/{insumo}', [InsumoController::class, 'showPdv'])->whereNumber('insumo')
        ->middleware(['auth:sanctum', 'action.permission:punto_venta,read']);
    Route::get('incidentes/responsables', [IncidenteEnvioController::class, 'responsables'])
        ->middleware('auth:sanctum');
    Route::patch('incidentes/{incidente}/asignar', [IncidenteEnvioController::class, 'asignar'])->whereNumber('incidente')
        ->middleware(['auth:sanctum', 'action.permission:incidentes,update']);
    // ENDPOINT DE PRUEBA
    Route::get('/test-api', function () {
        return response()->json(['ok' => true]);
    });

    // ========================================================
    // GRUPO: CATÁLOGOS
    // ========================================================
    $recursoProtegido('tipoactividades', TipoActividadController::class, 'catalogos');
    $recursoProtegido('prioridades', PrioridadController::class, 'catalogos');
    $recursoProtegido('tipoinsumos', TipoInsumoController::class, 'catalogos');
    $recursoProtegido('unidadesmedida', UnidadMedidaController::class, 'catalogos');
    $recursoProtegido('cultivos', CultivoController::class, 'catalogos');
    $recursoProtegido('estadolote-tipos', EstadoLoteTipoController::class, 'catalogos');
    $recursoProtegido('destinoproducciones', DestinoProduccionController::class, 'catalogos');
    $recursoProtegido('estadolote-insumos', EstadoLoteInsumoController::class, 'catalogos');

    // 🔹 nuevos catálogos de almacenamiento
    $recursoProtegido('tipo-almacenes', TipoAlmacenController::class, 'catalogos');

    // ========================================================
    // GRUPO: USUARIOS Y ROLES
    // ========================================================
    // Solo administración de usuarios (usuarios.admin): la API no acota por jefe/empleado.
    $recursoProtegido('roles', RolController::class, 'usuarios', 'admin');
    $recursoProtegido('usuarios', UsuarioController::class, 'usuarios', 'admin');
    $recursoProtegido('usuario-roles', UsuarioRolController::class, 'usuarios', 'admin');

    // ========================================================
    // GRUPO: LOTES Y PRODUCCIÓN
    // ========================================================
    Route::get('lotes', [LoteController::class, 'index'])
        ->middleware(['auth:sanctum', 'action.permission:lotes,read']);
    Route::get('lotes/{lote}/actividades', [ActividadController::class, 'porLote'])
        ->middleware(['auth:sanctum', 'action.permission:lotes,read']);
    Route::get('lotes/{lote}/actividades/{actividad}', [ActividadController::class, 'showEnLote'])
        ->middleware(['auth:sanctum', 'action.permission:lotes,read']);
    Route::post('lotes', [LoteController::class, 'store'])
        ->middleware(['auth:sanctum', 'action.permission:lotes,create']);
    Route::get('lotes/{lote}', [LoteController::class, 'show'])
        ->middleware(['auth:sanctum', 'action.permission:lotes,read']);
    Route::match(['put', 'patch'], 'lotes/{lote}', [LoteController::class, 'update'])
        ->middleware(['auth:sanctum', 'action.permission:lotes,update']);
    Route::delete('lotes/{lote}', [LoteController::class, 'destroy'])
        ->middleware(['auth:sanctum', 'action.permission:lotes,delete']);
    $recursoProtegido('estadolotes', EstadoLoteController::class, 'lotes');
    Route::apiResource('producciones', ProduccionController::class)
        ->middleware(['auth:sanctum', 'action.permission:lotes,read']);
    Route::get('lotes/{lote}/producciones', [ProduccionController::class, 'index'])
        ->name('lotes.producciones.index')->whereNumber('lote')->middleware(['auth:sanctum', 'action.permission:lotes,read']);
    Route::get('lotes/{lote}/producciones/{produccion}', [ProduccionController::class, 'showEnLote'])
        ->name('lotes.producciones.show')->whereNumber(['lote', 'produccion'])->middleware(['auth:sanctum', 'action.permission:lotes,read']);
    Route::get('lotes/{lote}/presentaciones-cosecha', [ProduccionController::class, 'configuracion'])
        ->name('lotes.presentaciones-cosecha')->whereNumber('lote')->middleware(['auth:sanctum', 'action.permission:lotes,read']);
    $recursoProtegido('historial-estados-lote', HistorialEstadoLoteController::class, 'lotes');

    // ========================================================
    // GRUPO: ALMACENES Y ALMACENAMIENTO
    // ========================================================
    Route::get('almacenes/{almacen}/existencias', [\App\Http\Controllers\InventarioExistenciasController::class, 'index'])
        ->middleware(['auth:sanctum', 'action.permission:inventario,read']);
    Route::patch('almacenes/{almacen}/existencias/{insumo}/minimo', [\App\Http\Controllers\InventarioExistenciasController::class, 'minimo'])
        ->middleware(['auth:sanctum', 'action.permission:inventario,update']);
    Route::get('almacenes/{almacen}/movimientos', [\App\Http\Controllers\InventarioExistenciasController::class, 'movimientos'])
        ->middleware(['auth:sanctum', 'action.permission:almacen_movimientos,read']);
    Route::get('almacenes/{almacen}/movimientos/{movimiento}', [\App\Http\Controllers\InventarioExistenciasController::class, 'movimiento'])
        ->middleware(['auth:sanctum', 'action.permission:almacen_movimientos,read']);
    $recursoProtegido('almacenes', AlmacenController::class, 'inventario');
    $recursoProtegido('producciones-almacenamiento', ProduccionAlmacenamientoController::class, 'inventario');
    Route::get('almacen-movimientos', [AlmacenMovimientoController::class, 'index'])
        ->middleware(['auth:sanctum', 'action.permission:almacen_movimientos,read']);
    // Escritura: exige el permiso de creación de ingreso/salida en la ruta (no el de lectura).
    Route::post('almacen-movimientos/ingreso', [AlmacenMovimientoController::class, 'store'])
        ->defaults('naturaleza', 'ingreso')
        ->middleware(['auth:sanctum', 'action.permission:almacen_ingresos,create']);
    Route::post('almacen-movimientos/salida', [AlmacenMovimientoController::class, 'store'])
        ->defaults('naturaleza', 'salida')
        ->middleware(['auth:sanctum', 'action.permission:almacen_salidas,create']);

    // ========================================================
    // GRUPO: INSUMOS Y APLICACIONES
    // ========================================================
    Route::get('insumos', [InsumoController::class, 'index'])
        ->middleware(['auth:sanctum', 'action.permission:inventario,read']);
    Route::post('insumos', [InsumoController::class, 'store'])
        ->middleware(['auth:sanctum', 'action.permission:inventario,create']);
    Route::get('insumos/{insumo}', [InsumoController::class, 'show'])
        ->middleware(['auth:sanctum', 'action.permission:inventario,read']);
    Route::match(['put', 'patch'], 'insumos/{insumo}', [InsumoController::class, 'update'])
        ->middleware(['auth:sanctum', 'action.permission:inventario,update']);
    Route::delete('insumos/{insumo}', [InsumoController::class, 'destroy'])
        ->middleware(['auth:sanctum', 'action.permission:inventario,delete']);
    $recursoProtegido('lote-insumos', LoteInsumoController::class, 'lotes');

    // ACTIVIDADES: lectura y escritura protegidas por acción y ownership del controlador.
    Route::post('actividades/{actividad}/cerrar', [\App\Http\Controllers\Api\ActividadCierreController::class, 'cerrar'])
        ->middleware(['auth:sanctum', 'action.permission:lotes,read'])->name('actividades.cerrar');
    Route::get('actividades/{actividad}/evidencia', [\App\Http\Controllers\Api\ActividadCierreController::class, 'evidencia'])
        ->middleware(['auth:sanctum', 'action.permission:lotes,read'])->name('actividades.evidencia');
    Route::get('actividades', [ActividadController::class, 'index'])
        ->middleware(['auth:sanctum', 'action.permission:lotes,read']);
    Route::post('actividades', [ActividadController::class, 'store'])
        ->middleware(['auth:sanctum', 'action.permission:lotes,update']);
    Route::get('actividades/{actividad}', [ActividadController::class, 'show'])
        ->middleware(['auth:sanctum', 'action.permission:lotes,read']);
    Route::match(['put', 'patch'], 'actividades/{actividad}', [ActividadController::class, 'update'])
        ->middleware(['auth:sanctum', 'action.permission:lotes,update']);
    Route::delete('actividades/{actividad}', [ActividadController::class, 'destroy'])
        ->middleware(['auth:sanctum', 'action.permission:lotes,update']);

    // CLIMA
    $recursoProtegido('climas', ClimaController::class, 'lotes');

    // ========================================================
    // GRUPO: PEDIDOS (CLIENTE EXTERNO) - control granular API
    // ========================================================
    foreach (['pedidos-agricolas' => ['agricola', 'pedidos'], 'pedidos-distribucion' => ['distribucion', 'pedidos_distribucion']] as $prefijo => [$tipo, $permiso]) {
        Route::prefix($prefijo)->middleware('auth:sanctum')->group(function () use ($tipo, $permiso) {
            $controller = \App\Http\Controllers\Api\PedidoMovilController::class;
            Route::get('', [$controller, 'index'])->defaults('tipo_pedido', $tipo)->middleware('action.permission:'.$permiso.',read');
            Route::post('', [$controller, 'store'])->defaults('tipo_pedido', $tipo)->middleware('action.permission:'.$permiso.',create');
            Route::get('{pedido}', [$controller, 'show'])->whereNumber('pedido')->defaults('tipo_pedido', $tipo)->middleware('action.permission:'.$permiso.',read');
            Route::post('{pedido}/transiciones', [$controller, 'transicion'])->whereNumber('pedido')->defaults('tipo_pedido', $tipo)->middleware('action.permission:'.$permiso.',update');
        });
    }

    Route::get('pedidos', [PedidoController::class, 'index'])
        ->middleware(['auth:sanctum', 'action.permission:pedidos,read']);
    Route::post('pedidos', [PedidoController::class, 'store'])
        ->middleware(['auth:sanctum', 'action.permission:pedidos,create']);
    Route::get('pedidos/{pedido}', [PedidoController::class, 'show'])
        ->middleware(['auth:sanctum', 'action.permission:pedidos,read']);
    Route::match(['put', 'patch'], 'pedidos/{pedido}', [PedidoController::class, 'update'])
        ->middleware(['auth:sanctum', 'action.permission:pedidos,update']);
    Route::delete('pedidos/{pedido}', [PedidoController::class, 'destroy'])
        ->middleware(['auth:sanctum', 'action.permission:pedidos,delete']);

    // CERTIFICACIONES - control granular API
    Route::get('certificaciones/{certificacion}', [\App\Http\Controllers\CertificadoHistorialController::class, 'campo'])->middleware(['auth:sanctum', 'action.permission:certificaciones,read']);
    Route::get('certificaciones/{certificacion}/archivo', [\App\Http\Controllers\CertificadoHistorialController::class, 'archivoCampo'])->middleware(['auth:sanctum', 'action.permission:certificaciones,read']);
    Route::get('lotes/{lote}/certificados', [\App\Http\Controllers\CertificadoHistorialController::class, 'historialCampo'])->middleware(['auth:sanctum', 'action.permission:certificaciones,read']);
    Route::get('lotes/{lote}/certificados/{certificacion}', [\App\Http\Controllers\CertificadoHistorialController::class, 'campoAnidado'])->middleware(['auth:sanctum', 'action.permission:certificaciones,read']);
    Route::get('lotes/{lote}/antecedentes', [\App\Http\Controllers\CertificadoHistorialController::class, 'recorridoCampo'])->middleware(['auth:sanctum', 'action.permission:certificaciones,read']);
    Route::get('planta/lotes-produccion/{loteProduccion}/certificados', [\App\Http\Controllers\CertificadoHistorialController::class, 'historialPlanta'])->middleware(['auth:sanctum', 'action.permission:lote_produccion,read']);
    Route::get('planta/lotes-produccion/{loteProduccion}/certificados/{evaluacionFinalLoteProduccion}', [\App\Http\Controllers\CertificadoHistorialController::class, 'plantaAnidado'])->middleware(['auth:sanctum', 'action.permission:lote_produccion,read']);
    Route::get('planta/lotes-produccion/{loteProduccion}/antecedentes', [\App\Http\Controllers\CertificadoHistorialController::class, 'recorridoPlanta'])->middleware(['auth:sanctum', 'action.permission:lote_produccion,read']);
    Route::get('planta/certificados/{evaluacionFinalLoteProduccion}/archivo', [\App\Http\Controllers\CertificadoHistorialController::class, 'archivoPlanta'])->middleware(['auth:sanctum', 'action.permission:lote_produccion,read']);

    Route::get('certificaciones', [CertificacionController::class, 'index'])
        ->middleware(['auth:sanctum', 'action.permission:certificaciones,read']);
    Route::post('certificaciones', [CertificacionController::class, 'store'])
        ->middleware(['auth:sanctum', 'action.permission:certificaciones,create']);


    // AUTH
    Route::post('/register', [AuthController::class, 'register'])->name('register');
    Route::post('/login',    [AuthController::class, 'login'])->name('login');

    Route::middleware('auth:sanctum')->group(function () {
        Route::get('/me',     [AuthController::class, 'me'])->name('me');
        Route::match(['put', 'patch'], '/me', [PerfilUsuarioController::class, 'update'])->name('me.update');
        Route::post('/logout',[AuthController::class, 'logout'])->name('logout');
    });

    // LOGISTICA OPERATIVA - API GRANULAR
    Route::get('incidentes', [IncidenteEnvioController::class, 'index'])
        ->middleware(['auth:sanctum', 'action.permission:incidentes,read']);
    Route::get('incidentes/{incidente}', [IncidenteEnvioController::class, 'show'])->whereNumber('incidente')
        ->middleware(['auth:sanctum', 'action.permission:incidentes,read']);
    Route::get('incidentes/afectados/{tipo}/{afectado}/{incidente}', [IncidenteEnvioController::class, 'anidado'])
        ->whereIn('tipo', \App\Services\IncidenteReferenciaService::TIPOS)->whereNumber(['afectado', 'incidente'])
        ->middleware(['auth:sanctum', 'action.permission:incidentes,read']);
    Route::post('incidentes', [IncidenteEnvioController::class, 'store'])
        ->middleware(['auth:sanctum', 'action.permission:incidentes,create']);
    Route::patch('incidentes/{incidente}/resolver', [IncidenteEnvioController::class, 'resolve'])
        ->middleware(['auth:sanctum', 'action.permission:incidentes,resolve']);

    Route::get('rutas-multi', [RutaMultiEntregaController::class, 'index'])
        ->middleware(['auth:sanctum', 'action.permission:rutas_multi,read']);
    Route::post('rutas-multi', [RutaMultiEntregaController::class, 'store'])
        ->middleware(['auth:sanctum', 'action.permission:rutas_multi,create']);
    Route::get('rutas-multi/{ruta}', [RutaMultiEntregaController::class, 'show'])
        ->middleware(['auth:sanctum', 'action.permission:rutas_multi,read']);
    Route::patch('rutas-multi/{ruta}', [RutaMultiEntregaController::class, 'update'])
        ->middleware(['auth:sanctum', 'action.permission:rutas_multi,update']);
    Route::patch('rutas-multi/{ruta}/reordenar', [RutaMultiEntregaController::class, 'reorder'])
        ->middleware(['auth:sanctum', 'action.permission:rutas_multi,reorder']);

    Route::get('asignaciones-multiples', [AsignacionMultipleController::class, 'index'])
        ->middleware(['auth:sanctum', 'action.permission:asignaciones,read']);
    Route::post('asignaciones-multiples', [AsignacionMultipleController::class, 'store'])
        ->middleware(['auth:sanctum', 'action.permission:asignaciones,create']);
    Route::post('asignaciones-multiples/lote', [AsignacionMultipleController::class, 'storeBatch'])
        ->middleware(['auth:sanctum', 'action.permission:asignaciones,multiple']);

    Route::get('documentos-entrega', [DocumentoEntregaController::class, 'index'])
        ->middleware(['auth:sanctum', 'action.permission:documentos,read']);
    Route::post('documentos-entrega', [DocumentoEntregaController::class, 'store'])
        ->middleware(['auth:sanctum', 'action.permission:documentos,create']);
    Route::get('documentos-entrega/{documento}/download', [DocumentoEntregaController::class, 'download'])
        ->middleware(['auth:sanctum', 'action.permission:documentos,read']);
});
