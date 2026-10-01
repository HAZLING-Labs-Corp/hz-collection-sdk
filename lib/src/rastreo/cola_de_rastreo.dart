/// LA COLA DEL RASTREO, EN SQLITE — lo que se midió y todavía no llegó, y lo que ya llegó
/// y se guarda un rato para poder mostrarlo.
///
/// ══ TRES TABLAS ══
///
///  · `puntos`  — cada punto grabado, con el `tramo` al que pertenece y el `lote` que lo
///                llevó (nulo mientras espera).
///  · `lotes`   — cada lote ARMADO, con sus bytes exactos. Se manda desde acá, siempre los
///                mismos bytes: así un reintento no duplica (mismo `loteId`).
///  · `estado`  — clave/valor: el último hash aceptado (la cadena), si la clave quedó
///                registrada, el último resultado de envío.
///  · `huecos`  — cada salto dentro de un tramo más largo de lo esperado. Se anota al
///                grabar, no se calcula al mirar: el diagnóstico no barre la tabla.
///
/// ══ 🔴 EL TECHO, Y QUÉ SE DESCARTA PRIMERO (la premisa de los millones) ══
///
/// Un teléfono sin señal una semana no puede llenarse el disco. La cola tiene dos techos
/// —[topePuntos] filas y [topeBytes] de JSON— y cuando se pasa descarta, en este orden:
///
///   1. **Lo que ya llegó.** Los puntos de lotes aceptados están guardados en Collection;
///      acá sólo servían para el diagnóstico. Se van primero, los más viejos antes.
///   2. **Lo que nunca va a salir.** Los lotes rechazados (401 repetido, 400, 409, 422) y
///      sus puntos. Se guardaban para poder mirar por qué; ya no hay lugar.
///   3. **Se RALEA lo que espera, no se corta.** De la mitad más vieja de lo pendiente se
///      borra un punto de cada dos. El recorrido pierde densidad pero no pierde horas: una
///      constancia de «dónde estaba a las 10:15» prefiere un punto cada 20 s a un hueco de
///      una hora. Se repite mientras haga falta.
///   4. **Recién ahí, lo más viejo que espera.** Si aun raleado no entra (un techo mal
///      puesto), se borra desde el principio.
///
/// El lote EN VUELO —armado, mandado, sin respuesta— no se toca nunca: sus bytes ya salieron
/// y puede estar guardado del otro lado.
library;

import 'dart:async';
import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'lote.dart';
import 'medidor_de_hilo.dart';
import 'punto.dart';

/// Un punto que espera, con su fila.
class PuntoEnCola {
  const PuntoEnCola(this.id, this.punto, this.tramo);
  final int id;
  final PuntoDeRastreo punto;
  final int tramo;
}

/// Un lote guardado, tal como está en la tabla.
class LoteEnCola {
  const LoteEnCola({
    required this.loteId,
    required this.creado,
    required this.hash,
    required this.hashAnterior,
    required this.cuerpo,
    required this.n,
    required this.bytes,
    required this.estado,
    required this.intentos,
    this.codigo,
    this.respuesta,
    this.enviado,
  });

  final String loteId;
  final int creado;
  final String hash;
  final String hashAnterior;
  final String cuerpo;
  final int n;
  final int bytes;

  /// `pendiente` · `aceptado` · `rechazado`.
  final String estado;
  final int intentos;
  final int? codigo;
  final String? respuesta;
  final int? enviado;

  static LoteEnCola deFila(Map<String, Object?> f) => LoteEnCola(
        loteId: f['loteId'] as String,
        creado: f['creado'] as int,
        hash: f['hash'] as String,
        hashAnterior: f['hashAnterior'] as String,
        cuerpo: f['cuerpo'] as String,
        n: f['n'] as int,
        bytes: f['bytes'] as int,
        estado: f['estado'] as String,
        intentos: f['intentos'] as int,
        codigo: f['codigo'] as int?,
        respuesta: f['respuesta'] as String?,
        enviado: f['enviado'] as int?,
      );
}

/// Un hueco dentro de un tramo: de cuándo a cuándo no hubo puntos.
class Hueco {
  const Hueco(this.desde, this.hasta, this.tramo);
  final int desde;
  final int hasta;
  final int tramo;
  Duration get duracion => Duration(milliseconds: hasta - desde);
}

class ColaDeRastreo {
  ColaDeRastreo._(this._db, {required this.topePuntos, required this.topeBytes});

  final Database _db;

  /// ~55 horas rodando a un punto cada 10 s. Ver la cabecera.
  final int topePuntos;

  /// 4 MB de JSON: un punto pesa ~110 bytes, así que el de bytes y el de puntos llegan
  /// juntos; el de bytes está por si algún día un punto crece.
  final int topeBytes;

  static const topePuntosPorOmision = 20000;
  static const topeBytesPorOmision = 4 * 1024 * 1024;

  /// Cuánto se guarda lo que ya llegó, sólo para el diagnóstico.
  static const retencionDeLoEnviado = Duration(hours: 48);

  /// Cada cuántos puntos se mira el techo. Mirarlo en cada punto es una consulta de más
  /// por punto; cada veinte, en el peor caso se pasa por veinte filas.
  static const _mirarTechoCada = 20;
  int _desdeQueSeMiro = 0;

  static Future<ColaDeRastreo> abrir({
    String? ruta,
    DatabaseFactory? fabrica,
    int topePuntos = topePuntosPorOmision,
    int topeBytes = topeBytesPorOmision,
  }) async {
    final f = fabrica ?? databaseFactory;
    final camino = ruta ?? '${await f.getDatabasesPath()}/hz_collection_rastreo.db';
    final db = await f.openDatabase(
      camino,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE puntos (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              t INTEGER NOT NULL,
              json TEXT NOT NULL,
              bytes INTEGER NOT NULL,
              tramo INTEGER NOT NULL,
              lote TEXT
            )''');
          // Lo que espera se lee por `lote IS NULL ORDER BY id`: el índice empieza por lo que
          // acota (el lote) y sigue por lo que ordena (el id).
          await db.execute('CREATE INDEX puntos_por_lote ON puntos(lote, id)');
          await db.execute('''
            CREATE TABLE lotes (
              loteId TEXT PRIMARY KEY,
              creado INTEGER NOT NULL,
              hash TEXT NOT NULL,
              hashAnterior TEXT NOT NULL,
              cuerpo TEXT NOT NULL,
              n INTEGER NOT NULL,
              bytes INTEGER NOT NULL,
              estado TEXT NOT NULL,
              intentos INTEGER NOT NULL DEFAULT 0,
              codigo INTEGER,
              respuesta TEXT,
              enviado INTEGER
            )''');
          await db.execute('CREATE INDEX lotes_por_estado ON lotes(estado, creado)');
          await db.execute('CREATE TABLE estado (clave TEXT PRIMARY KEY, valor TEXT)');
          await db.execute('''
            CREATE TABLE huecos (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              desde INTEGER NOT NULL,
              hasta INTEGER NOT NULL,
              tramo INTEGER NOT NULL
            )''');
        },
      ),
    );
    return ColaDeRastreo._(db, topePuntos: topePuntos, topeBytes: topeBytes);
  }

  Future<void> cerrar() => _db.close();

  // ── Puntos ────────────────────────────────────────────────────────────────────────

  Future<void> agregar(PuntoDeRastreo p, int tramo) async {
    final (json, bytes) = MedidorDeHilo.sincrono('cola.agregar.json', () {
      final j = jsonEncode(p.toJson());
      return (j, utf8.encode(j).length);
    });
    // sqflite ejecuta la consulta en SU hilo (Android: un hilo de trabajo por base; iOS:
    // una cola de GCD). Acá sólo se espera.
    await MedidorDeHilo.asincrono(
        'cola.agregar.sqlite',
        () => _db.insert('puntos', {
              't': p.t,
              'json': json,
              'bytes': bytes,
              'tramo': tramo,
            }));
    if (++_desdeQueSeMiro >= _mirarTechoCada) {
      _desdeQueSeMiro = 0;
      await MedidorDeHilo.asincrono('cola.respetarTecho', respetarTecho);
    }
  }

  Future<List<PuntoEnCola>> pendientes(int cuantos) async {
    final filas = await MedidorDeHilo.asincrono(
        'cola.pendientes.sqlite',
        () => _db.query('puntos',
            columns: ['id', 'json', 'tramo'],
            where: 'lote IS NULL',
            orderBy: 'id',
            limit: cuantos));
    return MedidorDeHilo.sincrono('cola.pendientes.decodificar(${filas.length})', () => [
          for (final f in filas)
            PuntoEnCola(
              f['id'] as int,
              PuntoDeRastreo.fromJson(
                  (jsonDecode(f['json'] as String) as Map).cast<String, dynamic>()),
              f['tramo'] as int,
            ),
        ]);
  }

  Future<int> contarPendientes() async => Sqflite.firstIntValue(
          await _db.rawQuery('SELECT COUNT(*) FROM puntos WHERE lote IS NULL')) ??
      0;

  /// El `t` del punto que más espera, o `null` si no espera ninguno.
  Future<int?> tDelMasViejoPendiente() async {
    final f = await _db.query('puntos',
        columns: ['t'], where: 'lote IS NULL', orderBy: 'id', limit: 1);
    return f.isEmpty ? null : f.first['t'] as int;
  }

  Future<({int filas, int bytes})> tamano() async {
    final f = await _db.rawQuery(
        'SELECT COUNT(*) AS n, COALESCE(SUM(bytes),0) AS b FROM puntos');
    final l = await _db.rawQuery(
        "SELECT COALESCE(SUM(bytes),0) AS b FROM lotes WHERE estado != 'aceptado'");
    return (
      filas: (f.first['n'] as int?) ?? 0,
      bytes: ((f.first['b'] as int?) ?? 0) + ((l.first['b'] as int?) ?? 0),
    );
  }

  // ── Lotes ─────────────────────────────────────────────────────────────────────────

  /// Guarda el lote armado y le ata sus puntos, en una transacción: o quedan las dos cosas
  /// o ninguna. Si se cortara en el medio, un punto quedaría en dos lotes.
  Future<void> guardarLote(LoteArmado l, List<int> idsDePuntos, int ahora) async {
    await _db.transaction((tx) async {
      await tx.insert('lotes', {
        'loteId': l.loteId,
        'creado': ahora,
        'hash': l.hash,
        'hashAnterior': l.hashAnterior,
        'cuerpo': l.cuerpo,
        'n': l.n,
        'bytes': l.bytes,
        'estado': 'pendiente',
        'intentos': 0,
      });
      for (var i = 0; i < idsDePuntos.length; i += 500) {
        final tramo = idsDePuntos.sublist(
            i, i + 500 > idsDePuntos.length ? idsDePuntos.length : i + 500);
        await tx.rawUpdate(
            'UPDATE puntos SET lote = ? WHERE id IN (${List.filled(tramo.length, '?').join(',')})',
            [l.loteId, ...tramo]);
      }
    });
  }

  /// El lote armado que todavía no tuvo respuesta definitiva. Hay a lo sumo uno: el
  /// siguiente no se arma hasta que éste se resuelve, porque su `hashAnterior` depende de
  /// si éste entró.
  Future<LoteEnCola?> loteEnVuelo() async {
    final f = await _db.query('lotes',
        where: "estado = 'pendiente'", orderBy: 'creado', limit: 1);
    return f.isEmpty ? null : LoteEnCola.deFila(f.first);
  }

  Future<LoteEnCola?> ultimoLoteConRespuesta() async {
    final f = await _db.query('lotes',
        where: 'enviado IS NOT NULL', orderBy: 'enviado DESC', limit: 1);
    return f.isEmpty ? null : LoteEnCola.deFila(f.first);
  }

  Future<void> anotarIntento(String loteId, int? codigo, String? respuesta, int ahora) =>
      _db.rawUpdate(
          'UPDATE lotes SET intentos = intentos + 1, codigo = ?, respuesta = ?, enviado = ? '
          'WHERE loteId = ?',
          [codigo, respuesta, ahora, loteId]);

  Future<void> marcarAceptado(String loteId, String hash) async {
    await _db.transaction((tx) async {
      await tx.update('lotes', {'estado': 'aceptado'},
          where: 'loteId = ?', whereArgs: [loteId]);
      await tx.insert('estado', {'clave': 'ultimoHashAceptado', 'valor': hash},
          conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  /// 409 `cadena_rota`: el lote armado encadenaba a un hash que la ingesta no tiene. Se
  /// borra el lote, sus puntos vuelven a esperar, y el último hash pasa a ser el de la
  /// ingesta. En una transacción: o las tres cosas o ninguna.
  Future<void> resincronizarCadena(String loteId, String ultimoHash) async {
    await _db.transaction((tx) async {
      await tx.update('puntos', {'lote': null}, where: 'lote = ?', whereArgs: [loteId]);
      await tx.delete('lotes', where: 'loteId = ?', whereArgs: [loteId]);
      await tx.insert('estado', {'clave': 'ultimoHashAceptado', 'valor': ultimoHash},
          conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<void> marcarRechazado(String loteId) => _db.update(
      'lotes', {'estado': 'rechazado'},
      where: 'loteId = ?', whereArgs: [loteId]);

  Future<({int aceptados, int rechazados})> contarLotes() async {
    final f = await _db.rawQuery(
        "SELECT SUM(estado='aceptado') AS a, SUM(estado='rechazado') AS r FROM lotes");
    return (
      aceptados: (f.first['a'] as int?) ?? 0,
      rechazados: (f.first['r'] as int?) ?? 0,
    );
  }

  // ── Estado ────────────────────────────────────────────────────────────────────────

  Future<String?> leer(String clave) async {
    final f = await _db.query('estado',
        columns: ['valor'], where: 'clave = ?', whereArgs: [clave], limit: 1);
    return f.isEmpty ? null : f.first['valor'] as String?;
  }

  Future<void> escribir(String clave, String? valor) => valor == null
      ? _db.delete('estado', where: 'clave = ?', whereArgs: [clave])
      : _db.insert('estado', {'clave': clave, 'valor': valor},
          conflictAlgorithm: ConflictAlgorithm.replace);

  /// El `hash` del último lote que la ingesta aceptó, o `"0"`: es el `hashAnterior` del
  /// siguiente. Se guarda en la misma transacción que marca el lote aceptado.
  Future<String> ultimoHashAceptado() async => await leer('ultimoHashAceptado') ?? '0';

  // ── Huecos ────────────────────────────────────────────────────────────────────────

  Future<void> anotarHueco(int desde, int hasta, int tramo) =>
      _db.insert('huecos', {'desde': desde, 'hasta': hasta, 'tramo': tramo});

  Future<List<Hueco>> huecosDesde(int desde, {int cuantos = 20}) async {
    final f = await _db.query('huecos',
        where: 'hasta >= ?', whereArgs: [desde], orderBy: 'hasta DESC', limit: cuantos);
    return [
      for (final x in f) Hueco(x['desde'] as int, x['hasta'] as int, x['tramo'] as int)
    ];
  }

  // ── El techo y la limpieza ────────────────────────────────────────────────────────

  /// Borra lo enviado más viejo que [retencionDeLoEnviado]. Se llama al aceptar un lote.
  Future<void> purgarLoEnviado(int ahora) async {
    final antes = ahora - retencionDeLoEnviado.inMilliseconds;
    await _db.transaction((tx) async {
      await tx.rawDelete(
          "DELETE FROM puntos WHERE lote IN (SELECT loteId FROM lotes WHERE estado = 'aceptado' AND creado < ?)",
          [antes]);
      await tx.rawDelete(
          "DELETE FROM lotes WHERE estado = 'aceptado' AND creado < ?", [antes]);
      await tx.rawDelete('DELETE FROM huecos WHERE hasta < ?', [antes]);
    });
  }

  /// Aplica el orden de descarte de la cabecera hasta quedar bajo los dos techos.
  /// Devuelve cuántos puntos que ESPERABAN se perdieron (pasos 3 y 4). Lo de los pasos 1 y
  /// 2 no es pérdida: ya estaba en Collection, o nunca iba a estarlo.
  Future<int> respetarTecho() async {
    var borrados = 0;
    var perdidos = 0;
    bool pasado(({int filas, int bytes}) t) => t.filas > topePuntos || t.bytes > topeBytes;

    var t = await tamano();
    if (!pasado(t)) return 0;

    // 1. Lo que ya llegó, lo más viejo primero.
    borrados += await _db.rawDelete(
        "DELETE FROM puntos WHERE lote IN (SELECT loteId FROM lotes WHERE estado = 'aceptado')");
    await _db.rawDelete("DELETE FROM lotes WHERE estado = 'aceptado'");
    t = await tamano();
    if (!pasado(t)) return 0;

    // 2. Lo que nunca va a salir.
    borrados += await _db.rawDelete(
        "DELETE FROM puntos WHERE lote IN (SELECT loteId FROM lotes WHERE estado = 'rechazado')");
    await _db.rawDelete("DELETE FROM lotes WHERE estado = 'rechazado'");
    t = await tamano();

    // 3. Ralear la mitad más vieja de lo que espera, un punto de cada dos, mientras haga
    //    falta y mientras quede algo que ralear.
    var vueltas = 0;
    while (pasado(t) && vueltas++ < 8) {
      final n = await contarPendientes();
      if (n < 4) break;
      final mitad = n ~/ 2;
      final b = await _db.rawDelete('''
        DELETE FROM puntos WHERE id IN (
          SELECT id FROM (
            SELECT id, ROW_NUMBER() OVER (ORDER BY id) AS r FROM puntos WHERE lote IS NULL
            ORDER BY id LIMIT ?
          ) WHERE r % 2 = 0
        )''', [mitad]).catchError((Object _) => _ralearSinVentanas(mitad));
      if (b == 0) break;
      perdidos += b;
      t = await tamano();
    }

    // 4. Lo más viejo que espera.
    if (pasado(t)) {
      final sobran = t.filas - topePuntos;
      if (sobran > 0) {
        perdidos += await _db.rawDelete(
            'DELETE FROM puntos WHERE id IN (SELECT id FROM puntos WHERE lote IS NULL ORDER BY id LIMIT ?)',
            [sobran]);
      }
    }
    assert(borrados >= 0);
    return _anotarDescarte(perdidos);
  }

  /// SQLite anterior a 3.25 (Android 10 y más viejos, que es un Tecno barato) no tiene
  /// `ROW_NUMBER()`. Se ralea igual, leyendo los ids en Dart.
  Future<int> _ralearSinVentanas(int mitad) async {
    final f = await _db.query('puntos',
        columns: ['id'], where: 'lote IS NULL', orderBy: 'id', limit: mitad);
    final ids = [for (var i = 1; i < f.length; i += 2) f[i]['id'] as int];
    var b = 0;
    for (var i = 0; i < ids.length; i += 500) {
      final tramo = ids.sublist(i, i + 500 > ids.length ? ids.length : i + 500);
      b += await _db.rawDelete(
          'DELETE FROM puntos WHERE id IN (${List.filled(tramo.length, '?').join(',')})',
          tramo);
    }
    return b;
  }

  Future<int> _anotarDescarte(int borrados) async {
    if (borrados > 0) {
      final antes = int.tryParse(await leer('descartados') ?? '') ?? 0;
      await escribir('descartados', '${antes + borrados}');
    }
    return borrados;
  }

  Future<int> descartados() async => int.tryParse(await leer('descartados') ?? '') ?? 0;
}
