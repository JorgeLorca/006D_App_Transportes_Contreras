import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

typedef RegistroMapa = Map<String, dynamic>;
typedef ListaRegistros = List<RegistroMapa>;
typedef InfoCamion = Map<String, String>;

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('transportes_contreras_v2.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getApplicationDocumentsDirectory();
    final path = join(dbPath.path, filePath);

    return await openDatabase(
      path,
      version: 6, // Versión 6: todos los campos de viajes (peonetas, GPS inicio/fin) y catálogos completos
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sesion_local (
        auth_id TEXT PRIMARY KEY,
        rut TEXT NOT NULL,
        nombre_completo TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS regiones (
        id TEXT PRIMARY KEY,
        nombre TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS clientes (
        id TEXT PRIMARY KEY,
        nombre_empresa TEXT NOT NULL,
        nombre_contacto TEXT,
        telefono TEXT,
        direccion TEXT,
        region_id TEXT,
        comuna_id TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS consignatarios (
        id TEXT PRIMARY KEY,
        nombre_empresa TEXT NOT NULL,
        direccion TEXT,
        region_id TEXT,
        comuna_id TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS camiones (
        id TEXT PRIMARY KEY,
        patente TEXT NOT NULL,
        tipo_camion TEXT,
        marca TEXT,
        modelo TEXT,
        estado TEXT DEFAULT 'disponible'
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS viajes (
        id TEXT PRIMARY KEY,
        conductor_rut TEXT NOT NULL,
        camion_id TEXT,
        cliente_id TEXT,
        region_id TEXT,
        consignatario_id TEXT,
        fecha_viaje TEXT,
        numero_guia TEXT,
        pallets INTEGER DEFAULT 0,
        horas_nocturnas REAL DEFAULT 0.0,
        horas_sabado REAL DEFAULT 0.0,
        monto_tag INTEGER DEFAULT 0,
        monto_peonetas INTEGER DEFAULT 0,
        guia_petroleo TEXT,
        observaciones_conductor TEXT,
        observaciones_admin TEXT,
        estado TEXT DEFAULT 'pendiente',
        iniciado_en TEXT,
        finalizado_en TEXT,
        lat_inicio REAL,
        lng_inicio REAL,
        lat_fin REAL,
        lng_fin REAL,
        creado_en TEXT,
        hora_carga TEXT,
        hora_descarga TEXT,
        is_synced INTEGER DEFAULT 1,
        sync_action TEXT DEFAULT 'NONE'
      )
    ''');

    await _crearTablaCombustible(db);
    await _crearTablaAsistencia(db);
    await _crearTablaIncidentes(db);
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _crearTablaCombustible(db);
    }
    if (oldVersion < 3) {
      await _crearTablaCombustible(db);
      try {
        await db.execute("ALTER TABLE registros_combustible ADD COLUMN estado_revision TEXT DEFAULT 'pendiente'");
      } catch (_) {}
      try {
        await db.execute("ALTER TABLE registros_combustible ADD COLUMN observaciones_admin TEXT");
      } catch (_) {}
    }
    if (oldVersion < 4) {
      await _crearTablaAsistencia(db);
    }
    if (oldVersion < 5) {
      await _crearTablaIncidentes(db);
    }
    if (oldVersion < 6) {
      final nuevasColumnasViajes = [
        "ALTER TABLE viajes ADD COLUMN monto_peonetas INTEGER DEFAULT 0",
        "ALTER TABLE viajes ADD COLUMN lat_inicio REAL",
        "ALTER TABLE viajes ADD COLUMN lng_inicio REAL",
        "ALTER TABLE viajes ADD COLUMN lat_fin REAL",
        "ALTER TABLE viajes ADD COLUMN lng_fin REAL",
        "ALTER TABLE viajes ADD COLUMN creado_en TEXT",
        "ALTER TABLE clientes ADD COLUMN comuna_id TEXT",
        "ALTER TABLE consignatarios ADD COLUMN comuna_id TEXT",
      ];
      for (final sql in nuevasColumnasViajes) {
        try {
          await db.execute(sql);
        } catch (_) {}
      }
    }
  }

  Future<void> _crearTablaCombustible(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS registros_combustible (
        id TEXT PRIMARY KEY,
        conductor_rut TEXT NOT NULL,
        camion_id TEXT,
        camion_patente TEXT,
        estacion TEXT DEFAULT 'AIRE',
        odometro INTEGER NOT NULL,
        tipo_combustible TEXT NOT NULL,
        litros REAL NOT NULL,
        costo_total REAL NOT NULL,
        url_foto_voucher TEXT,
        url_foto_tablero TEXT,
        local_path_voucher TEXT,
        local_path_tablero TEXT,
        estado_revision TEXT DEFAULT 'pendiente',
        observaciones_admin TEXT,
        registrado_en TEXT NOT NULL,
        is_synced INTEGER DEFAULT 1,
        sync_action TEXT DEFAULT 'NONE'
      )
    ''');
  }

  Future<void> _crearTablaAsistencia(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS asistencia (
        id TEXT PRIMARY KEY,
        conductor_rut TEXT NOT NULL,
        tipo_evento TEXT NOT NULL,
        latitud REAL NOT NULL,
        longitud REAL NOT NULL,
        hora_evento TEXT NOT NULL,
        is_synced INTEGER DEFAULT 1,
        sync_action TEXT DEFAULT 'NONE'
      )
    ''');
  }

  Future<void> _crearTablaIncidentes(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS incidentes (
        id TEXT PRIMARY KEY,
        viaje_id TEXT,
        conductor_rut TEXT NOT NULL,
        tipo_incidente TEXT NOT NULL,
        gravedad TEXT NOT NULL,
        descripcion TEXT,
        latitud REAL NOT NULL,
        longitud REAL NOT NULL,
        url_evidencia_fotografica TEXT,
        local_path_evidencia TEXT,
        reportado_en TEXT NOT NULL,
        is_synced INTEGER DEFAULT 1,
        sync_action TEXT DEFAULT 'NONE'
      )
    ''');
  }

  // ==========================================
  // GESTIÓN DE SESIÓN OFFLINE
  // ==========================================
  Future<void> guardarSesionConductor(String authId, String rut, String nombreCompleto) async {
    final db = await instance.database;
    await db.delete('sesion_local');
    await db.insert(
      'sesion_local',
      {
        'auth_id': authId,
        'rut': rut,
        'nombre_completo': nombreCompleto,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<RegistroMapa?> obtenerSesionConductor() async {
    final db = await instance.database;
    final res = await db.query('sesion_local', limit: 1);
    if (res.isNotEmpty) return Map<String, dynamic>.from(res.first);
    return null;
  }

  Future<void> cerrarSesionLocal() async {
    final db = await instance.database;
    await db.delete('sesion_local');
  }

  // ==========================================
  // CATÁLOGOS: CAMIONES, CLIENTES, CONSIGNATARIOS, REGIONES
  // ==========================================
  Future<void> upsertCamionDesdeSupabase(RegistroMapa cam) async {
    final db = await instance.database;
    final id = cam['id']?.toString() ?? '';
    if (id.isEmpty) return;

    final existente = await db.query('camiones', where: 'id = ?', whereArgs: [id]);
    final prev = existente.isNotEmpty ? existente.first : <String, dynamic>{};

    final patente = (cam['patente'] ?? cam['placa'] ?? prev['patente'] ?? 'S/P').toString().toUpperCase();

    await db.insert(
      'camiones',
      {
        'id': id,
        'patente': patente,
        'tipo_camion': cam['tipo_camion']?.toString() ?? prev['tipo_camion']?.toString(),
        'marca': cam['marca']?.toString() ?? prev['marca']?.toString(),
        'modelo': cam['modelo']?.toString() ?? prev['modelo']?.toString(),
        'estado': cam['estado']?.toString() ?? prev['estado']?.toString() ?? 'disponible',
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> upsertClienteDesdeSupabase(RegistroMapa c) async {
    final db = await instance.database;
    final id = c['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final nombreCli = c['nombre_empresa'] ?? c['nombre'] ?? c['razon_social'] ?? 'Cliente';

    await db.insert(
      'clientes',
      {
        'id': id,
        'nombre_empresa': nombreCli.toString(),
        'nombre_contacto': c['nombre_contacto']?.toString() ?? '',
        'telefono': (c['telefono'] ?? c['celular'] ?? '').toString(),
        'direccion': (c['direccion'] ?? c['ubicacion'] ?? '').toString(),
        'region_id': c['region_id']?.toString(),
        'comuna_id': c['comuna_id']?.toString(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> upsertConsignatarioDesdeSupabase(RegistroMapa con) async {
    final db = await instance.database;
    final id = con['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final nombreCon = con['nombre_empresa'] ?? con['nombre'] ?? con['razon_social'] ?? 'Consignatario';

    await db.insert(
      'consignatarios',
      {
        'id': id,
        'nombre_empresa': nombreCon.toString(),
        'direccion': (con['direccion'] ?? con['ubicacion'] ?? '').toString(),
        'region_id': con['region_id']?.toString(),
        'comuna_id': con['comuna_id']?.toString(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> upsertRegionDesdeSupabase(RegistroMapa r) async {
    final db = await instance.database;
    final id = r['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final nombreReg = r['nombre'] ?? r['region'] ?? 'Región';

    await db.insert(
      'regiones',
      {
        'id': id,
        'nombre': nombreReg.toString(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<ListaRegistros> obtenerTodosLosCamiones() async {
    final db = await instance.database;
    final rows = await db.query('camiones', orderBy: 'patente ASC');
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  Future<ListaRegistros> obtenerTodosLosConsignatarios() async {
    final db = await instance.database;
    final rows = await db.query('consignatarios', orderBy: 'nombre_empresa ASC');
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  Future<bool> tieneTurnoAsistenciaActivo(String rut) async {
    final ultimo = await obtenerUltimoEventoAsistencia(rut);
    if (ultimo == null) return false;

    final tipo = (ultimo['tipo_evento'] ?? '').toString().toLowerCase().trim();
    if (tipo != 'entrada') return false;

    final horaStr = (ultimo['hora_evento'] ?? '').toString().trim();
    final dtEvento = DateTime.tryParse(horaStr)?.toLocal();
    if (dtEvento == null) return false;

    final ahora = DateTime.now();
    final esMismoDia = dtEvento.year == ahora.year &&
        dtEvento.month == ahora.month &&
        dtEvento.day == ahora.day;
    final horasTranscurridas = ahora.difference(dtEvento).inHours.abs();

    // Solo es válido si marcó entrada hoy o dentro de las últimas 14 horas (turno nocturno)
    return esMismoDia || horasTranscurridas <= 14;
  }

  /// Elimina de SQLite los viajes que fueron borrados en Supabase para que desaparezcan de la Planilla y de Mis Viajes
  Future<void> eliminarViajesBorradosEnServidor(String rut, List<String> idsRemotosVigentes) async {
    final db = await instance.database;
    final locales = await db.query(
      'viajes',
      columns: ['id', 'is_synced'],
      where: 'conductor_rut = ?',
      whereArgs: [rut],
    );

    for (final loc in locales) {
      final idLocal = loc['id']?.toString() ?? '';
      final isSynced = (loc['is_synced'] ?? 1) == 1;
      if (isSynced && idLocal.isNotEmpty && !idsRemotosVigentes.contains(idLocal)) {
        await db.delete('viajes', where: 'id = ?', whereArgs: [idLocal]);
      }
    }
  }
  // ==========================================
  // MÉTODOS DE VIAJES (INCLUYE BLOQUEO DE RUTA DOBLE Y TODOS LOS CAMPOS)
  // ==========================================
  Future<bool> tieneViajeEnCurso(String rut, {String? excluirViajeId}) async {
    final db = await instance.database;
    final rows = await db.query(
      'viajes',
      where: 'conductor_rut = ? AND estado = ?',
      whereArgs: [rut, 'en_curso'],
    );
    if (excluirViajeId != null) {
      return rows.any((r) => r['id']?.toString() != excluirViajeId);
    }
    return rows.isNotEmpty;
  }

  Future<void> upsertViajeDesdeSupabase(RegistroMapa v) async {
    final db = await instance.database;

    final existente = await db.query('viajes', where: 'id = ?', whereArgs: [v['id']]);
    if (existente.isNotEmpty && existente.first['is_synced'] == 0) {
      return;
    }

    if (v['clientes'] is Map && v['cliente_id'] != null) {
      final c = Map<String, dynamic>.from(v['clientes'] as Map);
      c['id'] = v['cliente_id'].toString();
      await upsertClienteDesdeSupabase(c);
    }

    if (v['consignatarios'] is Map && v['consignatario_id'] != null) {
      final con = Map<String, dynamic>.from(v['consignatarios'] as Map);
      con['id'] = v['consignatario_id'].toString();
      await upsertConsignatarioDesdeSupabase(con);
    }

    if (v['regiones'] is Map && v['region_id'] != null) {
      final r = Map<String, dynamic>.from(v['regiones'] as Map);
      r['id'] = v['region_id'].toString();
      await upsertRegionDesdeSupabase(r);
    }

    if (v['camiones'] is Map && v['camion_id'] != null) {
      final cam = Map<String, dynamic>.from(v['camiones'] as Map);
      cam['id'] = v['camion_id'].toString();
      await upsertCamionDesdeSupabase(cam);
    }

    await db.insert(
      'viajes',
      {
        'id': v['id'].toString(),
        'conductor_rut': v['conductor_rut']?.toString() ?? '',
        'camion_id': v['camion_id']?.toString(),
        'cliente_id': v['cliente_id']?.toString(),
        'region_id': v['region_id']?.toString(),
        'consignatario_id': v['consignatario_id']?.toString(),
        'fecha_viaje': v['fecha_viaje']?.toString() ?? '',
        'numero_guia': v['numero_guia']?.toString(),
        'pallets': v['pallets'] is int ? v['pallets'] : int.tryParse(v['pallets']?.toString() ?? '0') ?? 0,
        'horas_nocturnas': (v['horas_nocturnas'] is num)
            ? (v['horas_nocturnas'] as num).toDouble()
            : double.tryParse(v['horas_nocturnas']?.toString() ?? '0') ?? 0.0,
        'horas_sabado': (v['horas_sabado'] is num)
            ? (v['horas_sabado'] as num).toDouble()
            : double.tryParse(v['horas_sabado']?.toString() ?? '0') ?? 0.0,
        'monto_tag': v['monto_tag'] is int ? v['monto_tag'] : int.tryParse(v['monto_tag']?.toString() ?? '0') ?? 0,
        'monto_peonetas': v['monto_peonetas'] is int
            ? v['monto_peonetas']
            : int.tryParse(v['monto_peonetas']?.toString() ?? '0') ?? 0,
        'guia_petroleo': v['guia_petroleo']?.toString(),
        'observaciones_conductor': v['observaciones_conductor']?.toString(),
        'observaciones_admin': v['observaciones_admin']?.toString(),
        'estado': v['estado']?.toString() ?? 'pendiente',
        'iniciado_en': v['iniciado_en']?.toString(),
        'finalizado_en': v['finalizado_en']?.toString(),
        'lat_inicio': (v['lat_inicio'] is num) ? (v['lat_inicio'] as num).toDouble() : null,
        'lng_inicio': (v['lng_inicio'] is num) ? (v['lng_inicio'] as num).toDouble() : null,
        'lat_fin': (v['lat_fin'] is num) ? (v['lat_fin'] as num).toDouble() : null,
        'lng_fin': (v['lng_fin'] is num) ? (v['lng_fin'] as num).toDouble() : null,
        'creado_en': v['creado_en']?.toString(),
        'hora_carga': v['hora_carga']?.toString(),
        'hora_descarga': v['hora_descarga']?.toString(),
        'is_synced': 1,
        'sync_action': 'NONE',
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<ListaRegistros> obtenerViajesPorEstado(String rut, String estado) async {
    final db = await instance.database;

    final rows = await db.rawQuery('''
      SELECT 
        v.*,
        c.nombre_empresa AS cliente_nombre,
        c.nombre_contacto AS cliente_contacto,
        c.direccion AS cliente_direccion,
        c.telefono AS cliente_telefono,
        consig.nombre_empresa AS consignatario_nombre,
        consig.direccion AS consignatario_direccion,
        r.nombre AS region_nombre,
        cam.patente AS camion_patente,
        cam.tipo_camion AS camion_tipo,
        cam.marca AS camion_marca,
        cam.modelo AS camion_modelo
      FROM viajes v
      LEFT JOIN clientes c ON v.cliente_id = c.id
      LEFT JOIN consignatarios consig ON v.consignatario_id = consig.id
      LEFT JOIN regiones r ON v.region_id = r.id
      LEFT JOIN camiones cam ON v.camion_id = cam.id
      WHERE v.conductor_rut = ? AND v.estado = ?
      ORDER BY v.fecha_viaje DESC, v.hora_carga ASC
    ''', [rut, estado]);

    return rows.map((row) {
      final map = Map<String, dynamic>.from(row);
      map['clientes'] = {
        'nombre_empresa': row['cliente_nombre'],
        'nombre': row['cliente_nombre'],
        'nombre_contacto': row['cliente_contacto'],
        'direccion': row['cliente_direccion'],
        'telefono': row['cliente_telefono'],
      };
      map['consignatarios'] = {
        'nombre_empresa': row['consignatario_nombre'],
        'nombre': row['consignatario_nombre'],
        'direccion': row['consignatario_direccion'],
      };
      map['regiones'] = {
        'nombre': row['region_nombre'],
      };
      map['camiones'] = {
        'patente': row['camion_patente'],
        'tipo_camion': row['camion_tipo'],
        'marca': row['camion_marca'],
        'modelo': row['camion_modelo'],
      };
      return map;
    }).toList();
  }

  Future<void> actualizarEstadoViajeOffline(String viajeId, RegistroMapa datosActualizados) async {
    final db = await instance.database;
    final payload = Map<String, dynamic>.from(datosActualizados);
    payload['is_synced'] = 0;
    payload['sync_action'] = 'UPDATE';

    await db.update(
      'viajes',
      payload,
      where: 'id = ?',
      whereArgs: [viajeId],
    );
  }

  Future<ListaRegistros> obtenerViajesNoSincronizados() async {
    final db = await instance.database;
    final rows = await db.query('viajes', where: 'is_synced = ?', whereArgs: [0]);
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  Future<void> marcarViajeSincronizado(String viajeId) async {
    final db = await instance.database;
    await db.update(
      'viajes',
      {'is_synced': 1, 'sync_action': 'NONE'},
      where: 'id = ?',
      whereArgs: [viajeId],
    );
  }

  // ==========================================
  // MÉTODOS DE COMBUSTIBLE
  // ==========================================
  Future<InfoCamion> obtenerCamionActualConductor(String rut) async {
    final db = await instance.database;
    final res = await db.rawQuery('''
      SELECT v.camion_id, cam.patente
      FROM viajes v
      LEFT JOIN camiones cam ON v.camion_id = cam.id
      WHERE v.conductor_rut = ? AND v.camion_id IS NOT NULL
      ORDER BY CASE WHEN v.estado = 'en_curso' THEN 0 ELSE 1 END, v.fecha_viaje DESC
      LIMIT 1
    ''', [rut]);

    if (res.isNotEmpty) {
      return {
        'camion_id': res.first['camion_id']?.toString() ?? '',
        'patente': res.first['patente']?.toString() ?? 'TC-9042',
      };
    }

    final camiones = await db.query('camiones', limit: 1);
    if (camiones.isNotEmpty) {
      return {
        'camion_id': camiones.first['id']?.toString() ?? '',
        'patente': camiones.first['patente']?.toString() ?? 'TC-9042',
      };
    }

    return {'camion_id': '', 'patente': 'Sin Patente'};
  }

  Future<void> insertarCombustibleOffline(RegistroMapa registro) async {
    final db = await instance.database;
    await _crearTablaCombustible(db);

    final payload = Map<String, dynamic>.from(registro);
    payload['estacion'] = 'AIRE';
    payload['estado_revision'] = payload['estado_revision'] ?? 'pendiente';
    payload['is_synced'] = 0;
    payload['sync_action'] = 'INSERT';

    await db.insert(
      'registros_combustible',
      payload,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<ListaRegistros> obtenerRegistrosCombustible(String rut) async {
    final db = await instance.database;
    await _crearTablaCombustible(db);

    final rows = await db.query(
      'registros_combustible',
      where: 'conductor_rut = ?',
      whereArgs: [rut],
      orderBy: 'registrado_en DESC',
    );
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  Future<ListaRegistros> obtenerCombustiblesNoSincronizados() async {
    final db = await instance.database;
    await _crearTablaCombustible(db);
    final rows = await db.query('registros_combustible', where: 'is_synced = ?', whereArgs: [0]);
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  Future<void> marcarCombustibleSincronizado(
    String id, {
    String? urlVoucher,
    String? urlTablero,
    String? camionId,
  }) async {
    final db = await instance.database;
    final updateData = <String, dynamic>{
      'is_synced': 1,
      'sync_action': 'NONE',
    };
    if (urlVoucher != null) updateData['url_foto_voucher'] = urlVoucher;
    if (urlTablero != null) updateData['url_foto_tablero'] = urlTablero;
    if (camionId != null) updateData['camion_id'] = camionId;

    await db.update(
      'registros_combustible',
      updateData,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> upsertCombustibleDesdeSupabase(RegistroMapa c) async {
    final db = await instance.database;
    await _crearTablaCombustible(db);

    final existente = await db.query('registros_combustible', where: 'id = ?', whereArgs: [c['id'].toString()]);
    if (existente.isNotEmpty && existente.first['is_synced'] == 0) {
      return;
    }

    String? patente;
    if (c['camiones'] is Map) {
      patente = (c['camiones'] as Map)['patente']?.toString();
    }

    final localVoucher = existente.isNotEmpty ? existente.first['local_path_voucher']?.toString() : null;
    final localTablero = existente.isNotEmpty ? existente.first['local_path_tablero']?.toString() : null;

    await db.insert(
      'registros_combustible',
      {
        'id': c['id'].toString(),
        'conductor_rut': c['conductor_rut']?.toString() ?? '',
        'camion_id': c['camion_id']?.toString(),
        'camion_patente': patente ?? c['camion_patente']?.toString() ?? 'Camión Asignado',
        'estacion': c['estacion']?.toString() ?? 'AIRE',
        'odometro': c['odometro'] is int ? c['odometro'] : int.tryParse(c['odometro']?.toString() ?? '0') ?? 0,
        'tipo_combustible': c['tipo_combustible']?.toString() ?? 'Diesel',
        'litros': (c['litros'] is num)
            ? (c['litros'] as num).toDouble()
            : double.tryParse(c['litros']?.toString() ?? '0') ?? 0.0,
        'costo_total': (c['costo_total'] is num)
            ? (c['costo_total'] as num).toDouble()
            : double.tryParse(c['costo_total']?.toString() ?? '0') ?? 0.0,
        'url_foto_voucher': c['url_foto_voucher']?.toString(),
        'url_foto_tablero': c['url_foto_tablero']?.toString(),
        'local_path_voucher': localVoucher,
        'local_path_tablero': localTablero,
        'estado_revision': c['estado_revision']?.toString() ?? 'pendiente',
        'observaciones_admin': c['observaciones_admin']?.toString(),
        'registrado_en': c['registrado_en']?.toString() ?? c['created_at']?.toString() ?? DateTime.now().toIso8601String(),
        'is_synced': 1,
        'sync_action': 'NONE',
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ==========================================
  // MÉTODOS DE ASISTENCIA (ORDENADOS POR DATETIME UTC REAL)
  // ==========================================
  DateTime _parseHoraUtc(dynamic val) {
    if (val == null) return DateTime.fromMillisecondsSinceEpoch(0);
    return DateTime.tryParse(val.toString().trim())?.toUtc() ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  Future<void> insertarAsistenciaOffline(RegistroMapa registro) async {
    final db = await instance.database;
    await _crearTablaAsistencia(db);

    final payload = Map<String, dynamic>.from(registro);
    payload['is_synced'] = 0;
    payload['sync_action'] = 'INSERT';

    await db.insert(
      'asistencia',
      payload,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<ListaRegistros> obtenerHistorialAsistencia(String rut) async {
    final db = await instance.database;
    await _crearTablaAsistencia(db);

    final rows = await db.query(
      'asistencia',
      where: 'conductor_rut = ?',
      whereArgs: [rut],
    );
    final lista = rows.map((r) => Map<String, dynamic>.from(r)).toList();
    lista.sort((a, b) => _parseHoraUtc(b['hora_evento']).compareTo(_parseHoraUtc(a['hora_evento'])));
    return lista;
  }

  Future<RegistroMapa?> obtenerUltimoEventoAsistencia(String rut) async {
    final historial = await obtenerHistorialAsistencia(rut);
    if (historial.isNotEmpty) return historial.first;
    return null;
  }

  Future<ListaRegistros> obtenerAsistenciasNoSincronizadas() async {
    final db = await instance.database;
    await _crearTablaAsistencia(db);
    final rows = await db.query('asistencia', where: 'is_synced = ?', whereArgs: [0]);
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  Future<void> marcarAsistenciaSincronizada(String id) async {
    final db = await instance.database;
    await db.update(
      'asistencia',
      {'is_synced': 1, 'sync_action': 'NONE'},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> upsertAsistenciaDesdeSupabase(RegistroMapa a) async {
    final db = await instance.database;
    await _crearTablaAsistencia(db);

    final existente = await db.query('asistencia', where: 'id = ?', whereArgs: [a['id'].toString()]);
    if (existente.isNotEmpty && existente.first['is_synced'] == 0) {
      return;
    }

    final horaNorm = DateTime.tryParse(a['hora_evento']?.toString() ?? '')?.toUtc().toIso8601String() ??
        DateTime.now().toUtc().toIso8601String();

    await db.insert(
      'asistencia',
      {
        'id': a['id'].toString(),
        'conductor_rut': a['conductor_rut']?.toString() ?? '',
        'tipo_evento': a['tipo_evento']?.toString() ?? 'entrada',
        'latitud': (a['latitud'] is num)
            ? (a['latitud'] as num).toDouble()
            : double.tryParse(a['latitud']?.toString() ?? '0') ?? 0.0,
        'longitud': (a['longitud'] is num)
            ? (a['longitud'] as num).toDouble()
            : double.tryParse(a['longitud']?.toString() ?? '0') ?? 0.0,
        'hora_evento': horaNorm,
        'is_synced': 1,
        'sync_action': 'NONE',
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ==========================================
  // MÉTODOS DE INCIDENTES EN RUTA
  // ==========================================
  Future<void> insertarIncidenteOffline(RegistroMapa registro) async {
    final db = await instance.database;
    await _crearTablaIncidentes(db);

    final payload = Map<String, dynamic>.from(registro);
    payload['is_synced'] = 0;
    payload['sync_action'] = 'INSERT';

    await db.insert(
      'incidentes',
      payload,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<ListaRegistros> obtenerHistorialIncidentes(String rut) async {
    final db = await instance.database;
    await _crearTablaIncidentes(db);

    final rows = await db.query(
      'incidentes',
      where: 'conductor_rut = ?',
      whereArgs: [rut],
      orderBy: 'reportado_en DESC',
    );
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  Future<ListaRegistros> obtenerIncidentesNoSincronizados() async {
    final db = await instance.database;
    await _crearTablaIncidentes(db);
    final rows = await db.query('incidentes', where: 'is_synced = ?', whereArgs: [0]);
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  Future<void> marcarIncidenteSincronizado(String id, {String? urlFoto}) async {
    final db = await instance.database;
    final updateData = <String, dynamic>{
      'is_synced': 1,
      'sync_action': 'NONE',
    };
    if (urlFoto != null) updateData['url_evidencia_fotografica'] = urlFoto;

    await db.update(
      'incidentes',
      updateData,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> upsertIncidenteDesdeSupabase(RegistroMapa inc) async {
    final db = await instance.database;
    await _crearTablaIncidentes(db);

    final existente = await db.query('incidentes', where: 'id = ?', whereArgs: [inc['id'].toString()]);
    if (existente.isNotEmpty && existente.first['is_synced'] == 0) {
      return;
    }

    final localFoto = existente.isNotEmpty ? existente.first['local_path_evidencia']?.toString() : null;

    await db.insert(
      'incidentes',
      {
        'id': inc['id'].toString(),
        'viaje_id': inc['viaje_id']?.toString(),
        'conductor_rut': inc['conductor_rut']?.toString() ?? '',
        'tipo_incidente': inc['tipo_incidente']?.toString() ?? 'retraso',
        'gravedad': inc['gravedad']?.toString() ?? 'leve',
        'descripcion': inc['descripcion']?.toString() ?? '',
        'latitud': (inc['latitud'] is num)
            ? (inc['latitud'] as num).toDouble()
            : double.tryParse(inc['latitud']?.toString() ?? '0') ?? 0.0,
        'longitud': (inc['longitud'] is num)
            ? (inc['longitud'] as num).toDouble()
            : double.tryParse(inc['longitud']?.toString() ?? '0') ?? 0.0,
        'url_evidencia_fotografica': inc['url_evidencia_fotografica']?.toString(),
        'local_path_evidencia': localFoto,
        'reportado_en': inc['reportado_en']?.toString() ?? DateTime.now().toIso8601String(),
        'is_synced': 1,
        'sync_action': 'NONE',
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}