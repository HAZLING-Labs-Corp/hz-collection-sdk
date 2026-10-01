/// LA PANTALLA DE DIAGNÓSTICO DEL RASTREO — lo que hay que mirar para saber si mide.
///
/// Permiso, GPS, batería, captura activa, último lote enviado y su respuesta, puntos en
/// cola y huecos. Y los botones para enrolar, arrancar, mandar ya y simular un recorrido.
///
/// No explica nada que no sea verdad en ese momento: cada fila sale de
/// `Rastreo.diagnostico()`, que lee la cola, el sistema y la última respuesta de la ingesta.
library;

import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:hz_collection_sdk/hz_collection_sdk.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/generado/textos_de_rastreo.dart';
import 'caminata_de_prueba.dart';
import 'captura_transistor.dart';
import 'historial_de_recorrido.dart';
import 'medidas.dart';
import 'pantalla_del_mapa.dart';
import 'ruta_de_prueba.dart';

class PantallaDeRastreo extends StatefulWidget {
  const PantallaDeRastreo({
    super.key,
    required this.llave,
    required this.url,
    required this.urlIngesta,
    required this.sujeto,
    required this.capturaInicial,
  });

  final String llave;
  final String url;
  final String? urlIngesta;
  final String sujeto;

  /// `propia` o `transistor` (la bandera `RASTREO_CAPTURA`). Se puede cambiar en la
  /// pantalla y queda recordada: así el MISMO APK mide las dos en el teléfono.
  final String capturaInicial;

  @override
  State<PantallaDeRastreo> createState() => _PantallaDeRastreoState();
}

class _PantallaDeRastreoState extends State<PantallaDeRastreo> {
  static const _claveCaptura = 'ejemplo.rastreo.captura';

  Rastreo? _rastreo;
  HistorialDeRecorrido? _historial;
  DiagnosticoDeRastreo? _diag;
  StreamSubscription<void>? _cambios;
  Timer? _refresco;
  String _captura = 'propia';
  String? _aviso;
  bool _actividadConcedida = false;
  int? _bateria;
  bool? _cargando;
  ({bool corriendo, int indice, int total})? _simulacion;
  bool _ocupado = false;

  TextosDeRastreo get t => TextosDeRastreo.of(context);

  @override
  void initState() {
    super.initState();
    unawaited(_abrir());
  }

  @override
  void dispose() {
    _cambios?.cancel();
    _refresco?.cancel();
    super.dispose();
  }

  Future<void> _abrir() async {
    final prefs = await SharedPreferences.getInstance();
    _captura = prefs.getString(_claveCaptura) ?? widget.capturaInicial;
    _historial = await HistorialDeRecorrido.abrir();
    await _armar();
    _refresco = Timer.periodic(const Duration(seconds: 3), (_) => unawaited(_refrescar()));
  }

  CapturaDeRastreo _nuevaCaptura() {
    final textos = lookupTextosDeRastreo(const Locale('es'));
    return _captura == 'transistor'
        ? CapturaTransistor(tituloDelAviso: textos.avisoTitulo, cuerpoDelAviso: textos.avisoCuerpo)
        : CapturaPropia(
            textos: TextosDelAvisoDeRastreo(titulo: textos.avisoTitulo, cuerpo: textos.avisoCuerpo));
  }

  Future<void> _armar() async {
    final anterior = _rastreo;
    await _cambios?.cancel();
    if (anterior != null) await anterior.detener();
    final r = await Rastreo.abrir(
      llave: widget.llave,
      url: widget.url,
      urlIngesta: widget.urlIngesta,
      captura: _nuevaCaptura(),
      cola: anterior?.cola,
    );
    _rastreo = r;
    _historial?.escuchar(r.captura);
    _cambios = r.cambios.listen((_) => unawaited(_refrescar()));
    // Si ya estaba enrolado, arranca solo: es lo que hace una app de verdad en cada
    // arranque. La primera vez hay que tocar «Enrolar».
    if (r.sujetoId != null) {
      final no = await r.iniciar();
      if (no != null && mounted) setState(() => _aviso = t.noArranco(no));
    }
    await _refrescar();
    unawaited(_permisoAlAbrir());
  }

  // ═══ CL-36 · EL PERMISO SE PIDE AL ABRIR, COMO MANDA LA POLÍTICA DEL COMERCIO ═══
  //
  // La misma regla de Collection que rige las notificaciones (`politica.dart`): cuándo y cómo
  // pedir lo decide el comercio, y viaja con la configuración (`rastreo.permiso`). Con el módulo
  // habilitado y `momento: arranque`, al abrir la app: pregunta blanda con los textos del comercio
  // (el diálogo del sistema se gasta) → ubicación → «todo el tiempo» como segundo paso guiado.
  static const _clavePermisoAhoraNo = 'ejemplo.rastreo.permisoAhoraNo';
  bool _permisoYaPreguntado = false;

  Future<void> _permisoAlAbrir() async {
    if (_permisoYaPreguntado) return;
    _permisoYaPreguntado = true;
    final r = _rastreo;
    if (r == null) return;
    final c = await r.releerConfiguracion();
    if (!c.activo || !mounted) return;
    final pol = c.permiso;
    if (pol.momento != MomentoDelPermiso.arranque) return;
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.always) {
      await _arrancarSolo();
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final ultimo = prefs.getInt(_clavePermisoAhoraNo);
    if (ultimo != null &&
        DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ultimo)).inDays <
            pol.reintentarCadaDias) {
      return;
    }
    if (p == LocationPermission.deniedForever) {
      if (mounted) setState(() => _aviso = t.permisoDenegado);
      return;
    }
    if (pol.preguntaBlanda && p == LocationPermission.denied) {
      final si = await _preguntar(pol.textos.titulo, pol.textos.cuerpo, pol.textos.aceptar, pol.textos.ahoraNo);
      if (si != true) {
        await prefs.setInt(_clavePermisoAhoraNo, DateTime.now().millisecondsSinceEpoch);
        return;
      }
    }
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    if (p == LocationPermission.whileInUse && mounted) {
      final txt = t;
      final ir = await _preguntar(txt.permisoSiempreTitulo, txt.permisoSiempreCuerpo, txt.permisoAbrirAjustes, pol.textos.ahoraNo);
      if (ir == true) await Geolocator.openAppSettings();
    }
    await ActividadDelAparato.pedirPermiso();
    await _arrancarSolo();
  }

  /// Al aceptar el permiso el rastreo ARRANCA SOLO: si la instalación todavía no estaba enrolada,
  /// se enrola (la primera vez no hay que tocar «Enrolar»), y después inicia.
  Future<void> _arrancarSolo() async {
    final r = _rastreo;
    if (r == null) return;
    if (r.sujetoId == null) await r.enrolar(sujetoId: widget.sujeto);
    final no = await r.iniciar();
    if (no != null && mounted) setState(() => _aviso = t.noArranco(no));
    await _refrescar();
  }

  Future<bool?> _preguntar(String titulo, String cuerpo, String si, String no) => showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (c) => AlertDialog(
          title: Text(titulo),
          content: Text(cuerpo),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(no)),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(si)),
          ],
        ),
      );

  /// Un refresco a la vez. Llegan pedidos del reloj de 3 s y de CADA cambio (un punto, un
  /// envío): sin esto, con el emulador lento se apilaban diagnósticos en paralelo —cada uno
  /// ~12 consultas y ~7 viajes al nativo— y la cola de mensajes del hilo principal crecía.
  /// Los pedidos que llegan mientras uno corre se juntan en UNO al terminar.
  bool _refrescando = false;
  bool _otroPendiente = false;

  Future<void> _refrescar() async {
    if (_refrescando) {
      _otroPendiente = true;
      return;
    }
    _refrescando = true;
    try {
      do {
        _otroPendiente = false;
        await _refrescarUnaVez();
      } while (_otroPendiente && mounted);
    } finally {
      _refrescando = false;
    }
  }

  Future<void> _refrescarUnaVez() async {
    final r = _rastreo;
    if (r == null) return;
    final d = await r.diagnostico();
    final act = await ActividadDelAparato.tienePermiso();
    int? nivel;
    bool? cargando;
    try {
      nivel = await Battery().batteryLevel;
      cargando = (await Battery().batteryState) == BatteryState.charging;
    } catch (_) {}
    final sim = await Simulador.estado();
    if (!mounted) return;
    setState(() {
      _diag = d;
      _actividadConcedida = act;
      _bateria = nivel;
      _cargando = cargando;
      _simulacion = sim;
    });
  }

  Future<void> _hacer(Future<void> Function() f) async {
    if (_ocupado) return;
    setState(() => _ocupado = true);
    try {
      await f();
    } catch (e) {
      if (mounted) setState(() => _aviso = '$e');
    } finally {
      if (mounted) setState(() => _ocupado = false);
      await _refrescar();
    }
  }

  Future<void> _enrolar() => _hacer(() async {
        final r = _rastreo!;
        final e = await r.enrolar(sujetoId: widget.sujeto);
        final txt = t;
        setState(() => _aviso = e.completo
            ? txt.enrolado(e.claveId.substring(0, 12))
            : txt.enrolamientoIncompleto(e.toString()));
        final no = await r.iniciar();
        if (no != null) setState(() => _aviso = txt.noArranco(no));
      });

  Future<void> _pedirPermisos() => _hacer(() async {
        var p = await Geolocator.checkPermission();
        if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
        // La segunda pregunta —«siempre»— va aparte: Android 11+ la manda a Ajustes.
        if (p == LocationPermission.whileInUse) p = await Geolocator.requestPermission();
        await ActividadDelAparato.pedirPermiso();
        await _rastreo?.iniciar();
      });

  Future<void> _cambiarCaptura(String c) => _hacer(() async {
        _captura = c;
        (await SharedPreferences.getInstance()).setString(_claveCaptura, c);
        await _armar();
      });

  Future<void> _simular() => _hacer(() async {
        final sim = _simulacion;
        if (sim != null && sim.corriendo) {
          await Simulador.detener();
          return;
        }
        final ruta = rutaDePrueba(quietoMin: _rastreo!.configuracion.quietoMin);
        final no = await Simulador.iniciar(ruta);
        if (no != null) {
          final txt = t;
          setState(() => _aviso = Theme.of(context).platform == TargetPlatform.iOS
              ? '${txt.simulacionIos}\n$no'
              : no);
        }
      });

  Future<void> _simularMoto() => _simularPorCalles(MedioDePrueba.moto, elSilencio);
  Future<void> _simularCaminata() => _simularPorCalles(MedioDePrueba.aPie, null);

  Future<void> _simularPorCalles(MedioDePrueba medio, LatLng? destino) => _hacer(() async {
        final sim = _simulacion;
        if (sim != null && sim.corriendo) {
          await Simulador.detener();
          return;
        }
        final pos = await Geolocator.getLastKnownPosition() ??
            await Geolocator.getCurrentPosition(
                locationSettings: const LocationSettings(accuracy: LocationAccuracy.best, timeLimit: Duration(seconds: 15)));
        final ruta = await recorridoDePrueba(
            lat: pos.latitude, lon: pos.longitude, quietoMin: _rastreo!.configuracion.quietoMin, medio: medio, destino: destino);
        final txt = t;
        if (ruta == null) {
          setState(() => _aviso = txt.caminataSinRuta);
          return;
        }
        final no = await Simulador.iniciar(ruta);
        if (no != null) setState(() => _aviso = no);
      });

  @override
  Widget build(BuildContext context) {
    final m = context.medidas;
    final d = _diag;
    return Scaffold(
      appBar: AppBar(
        title: Text(t.titulo),
        actions: [
          IconButton(
            tooltip: t.mapaVerMapa,
            icon: const Icon(Icons.map_outlined),
            onPressed: _historial == null
                ? null
                : () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => PantallaDelMapa(historial: _historial!, rastreo: _rastreo))),
          ),
        ],
      ),
      body: SafeArea(
        child: d == null
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _refrescar,
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: m.anchoMaximo),
                    child: ListView(
                      padding: EdgeInsets.all(m.l),
                      children: [
                        if (_aviso != null) _Aviso(_aviso!, alCerrar: () => setState(() => _aviso = null)),
                        _capturaSeccion(d),
                        _cola(d),
                        _ultimoLote(d),
                        _huecos(d),
                        _problemas(d),
                        _simularSeccion(),
                        _permisos(d),
                        _bateriaSeccion(d),
                        _configuracion(d),
                        _enrolamiento(d),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  String _textoDeFila(FilaDeCadencia f) => f.muestreoSeg == 0
      ? t.filaSinGps(f.latidoMin ?? 0)
      : t.filaConGps(f.muestreoSeg, f.loteSeg ?? 0);

  String _siNo(bool? b) => b == null ? t.sinDato : (b ? t.si : t.no);

  String _hora(DateTime? x) =>
      x == null ? t.sinDato : TimeOfDay.fromDateTime(x).format(context);

  String _horaSeg(int ms) {
    final x = DateTime.fromMillisecondsSinceEpoch(ms);
    String dos(int n) => n.toString().padLeft(2, '0');
    return '${dos(x.hour)}:${dos(x.minute)}:${dos(x.second)}';
  }

  Widget _capturaSeccion(DiagnosticoDeRastreo d) => _Seccion(
        titulo: t.seccionCaptura,
        filas: [
          _Fila(t.estado, switch (d.estado) {
            EstadoDeMovimiento.quieto => t.estadoQuieto,
            EstadoDeMovimiento.confirmando => t.estadoConfirmando,
            EstadoDeMovimiento.rodando => t.estadoRodando,
          }, bien: d.capturaActiva),
          _Fila(t.activa, _siNo(d.capturaActiva), bien: d.capturaActiva),
          _Fila(t.cadenciaAhora, '${d.cadencia.estado} · ${_textoDeFila(d.cadencia)}'),
          _Fila(t.motivo, d.motivoDelEstado ?? t.sinDato),
        ],
        encabezado: SegmentedButton<String>(
          segments: [
            ButtonSegment(value: 'propia', label: Text(t.capturaPropia)),
            ButtonSegment(value: 'transistor', label: Text(t.capturaTransistor)),
          ],
          selected: {_captura},
          onSelectionChanged: _ocupado ? null : (s) => _cambiarCaptura(s.first),
        ),
        acciones: [
          FilledButton(
            onPressed: _ocupado
                ? null
                : () => _hacer(() async {
                      final no = await _rastreo!.iniciar();
                      if (no != null) setState(() => _aviso = t.noArranco(no));
                    }),
            child: Text(t.iniciar),
          ),
          OutlinedButton(
            onPressed: _ocupado ? null : () => _hacer(() => _rastreo!.detener()),
            child: Text(t.detener),
          ),
        ],
      );

  Widget _cola(DiagnosticoDeRastreo d) => _Seccion(
        titulo: t.seccionCola,
        filas: [
          _Fila(t.enCola, '${d.enCola}'),
          _Fila(t.tamano, t.kb((d.colaBytes / 1024).toStringAsFixed(1))),
          _Fila(t.loteEnVuelo, d.loteEnVuelo ?? t.sinDato),
          _Fila(t.aceptados, '${d.lotesAceptados}', bien: d.lotesAceptados > 0 ? true : null),
          _Fila(t.rechazados, '${d.lotesRechazados}', bien: d.lotesRechazados == 0 ? null : false),
          _Fila(t.descartados, '${d.descartados}', bien: d.descartados == 0 ? null : false),
          _Fila(t.proximoIntento, _hora(d.proximoIntento)),
          _Fila(t.fallosSeguidos, '${d.fallosSeguidos}', bien: d.fallosSeguidos == 0 ? null : false),
        ],
        acciones: [
          FilledButton.tonal(
            onPressed: _ocupado ? null : () => _hacer(() async => _rastreo!.enviarAhora()),
            child: Text(t.enviarAhora),
          ),
        ],
      );

  Widget _ultimoLote(DiagnosticoDeRastreo d) {
    final u = d.ultimoEnvio;
    final bien = u == null ? null : (u.codigo == '200' || u.codigo == '202');
    return _Seccion(
      titulo: t.seccionUltimoLote,
      filas: u == null
          ? [_Fila(t.ningunLote, '')]
          : [
              _Fila(t.cuando, _horaSeg(u.cuando.millisecondsSinceEpoch)),
              _Fila(t.lote, u.loteId),
              _Fila(t.codigo, u.codigo, bien: bien),
              _Fila(t.respuesta, u.respuesta, largo: true),
            ],
    );
  }

  Widget _huecos(DiagnosticoDeRastreo d) => _Seccion(
        titulo: t.seccionHuecos,
        filas: d.huecos.isEmpty
            ? [_Fila(t.sinHuecos, '', bien: true)]
            : [
                for (final h in d.huecos)
                  _Fila(t.hueco(_horaSeg(h.desde), _horaSeg(h.hasta), h.duracion.inSeconds), '',
                      bien: false),
              ],
      );

  Widget _problemas(DiagnosticoDeRastreo d) => _Seccion(
        titulo: t.seccionProblemas,
        filas: d.problemas.isEmpty
            ? [_Fila(t.sinProblemas, '', bien: true)]
            : [for (final p in d.problemas) _Fila(p, '', largo: true)],
      );

  Widget _simularSeccion() {
    final s = _simulacion;
    final corriendo = s != null && s.corriendo;
    return _Seccion(
      titulo: t.seccionSimular,
      filas: [
        _Fila(t.motoExplicacion, '', largo: true),
        _Fila(t.caminataExplicacion, '', largo: true),
        if (corriendo) _Fila(t.simulando(s.indice, s.total), ''),
      ],
      acciones: [
        FilledButton.icon(
          onPressed: _ocupado ? null : _simularMoto,
          icon: Icon(corriendo ? Icons.stop : Icons.two_wheeler),
          label: Text(corriendo ? t.detenerSimulacion : t.simularMoto),
        ),
        OutlinedButton.icon(
          onPressed: _ocupado || corriendo ? null : _simularCaminata,
          icon: const Icon(Icons.directions_walk),
          label: Text(t.simularCaminata),
        ),
        OutlinedButton.icon(
          onPressed: _ocupado || corriendo ? null : _simular,
          icon: const Icon(Icons.route),
          label: Text(t.simular),
        ),
      ],
    );
  }

  Widget _permisos(DiagnosticoDeRastreo d) => _Seccion(
        titulo: t.seccionPermisos,
        filas: [
          _Fila(t.ubicacion, switch (d.permiso) {
            'siempre' => t.permisoSiempre,
            'enUso' => t.permisoEnUso,
            _ => t.permisoNo,
          }, bien: d.permiso == 'siempre' ? true : (d.permiso == 'no' ? false : null)),
          _Fila(t.gps, d.gpsPrendido ? t.prendido : t.apagado, bien: d.gpsPrendido),
          _Fila(t.actividadFisica, _siNo(_actividadConcedida), bien: _actividadConcedida ? true : null),
        ],
        acciones: [
          OutlinedButton(onPressed: _ocupado ? null : _pedirPermisos, child: Text(t.pedirPermisos)),
        ],
      );

  Widget _bateriaSeccion(DiagnosticoDeRastreo d) {
    final e = d.energia;
    return _Seccion(
      titulo: t.seccionBateria,
      filas: [
        _Fila(t.nivel, _bateria == null ? t.sinDato : t.porciento(_bateria!)),
        _Fila(t.cargando, _siNo(_cargando)),
        _Fila(t.sinRestricciones, _siNo(e.sinOptimizacion), bien: e.sinOptimizacion),
        _Fila(t.ahorro, _siNo(e.ahorroDeEnergia), bien: e.ahorroDeEnergia == true ? false : null),
        _Fila(t.aparato, [e.fabricante, e.modelo, if (e.android != null) t.versionAndroid(e.android!)]
            .whereType<String>()
            .join(' · ')),
      ],
      acciones: [
        OutlinedButton(
          onPressed: EnergiaDelAparato.abrirAjustesDeBateria,
          child: Text(t.ajustesDeBateria),
        ),
      ],
    );
  }

  Widget _configuracion(DiagnosticoDeRastreo d) {
    final c = d.configuracion;
    return _Seccion(
      titulo: t.seccionConfiguracion,
      filas: [
        _Fila(t.activo, _siNo(c.activo), bien: c.activo),
        _Fila(t.perfil, c.perfil ?? t.sinDato),
        _Fila(t.respuesta, '${d.configuracionCodigo ?? t.sinDato} · ${_hora(d.configuracionCuando)}',
            bien: d.configuracionCodigo == 200 ? true : (d.configuracionCodigo == null ? null : false)),
        _Fila(t.quietoTras, t.minutos(c.quietoMin)),
        _Fila(t.arranque, t.kmh(c.arranqueKmh)),
        _Fila(t.techoLote, t.puntos(c.lotePuntos)),
        _Fila(t.forzado, c.estadoForzado ?? t.sinDato),
        if (c.cadencia.isEmpty) _Fila(t.cadenciaRespaldo, '', largo: true),
        for (final f in c.cadencia) _Fila(f.estado, _textoDeFila(f)),
      ],
      acciones: [
        OutlinedButton(
          onPressed: _ocupado ? null : () => _hacer(() async => _rastreo!.iniciar()),
          child: Text(t.releer),
        ),
      ],
    );
  }

  Widget _enrolamiento(DiagnosticoDeRastreo d) => _Seccion(
        titulo: t.seccionEnrolamiento,
        filas: [
          _Fila(t.sujeto, d.sujetoId ?? widget.sujeto),
          _Fila(t.instalacion, d.instalacionId, copiable: true),
          _Fila(t.clave, d.claveId ?? t.sinDato, copiable: true),
          _Fila(t.claveEnHardware, _siNo(d.claveId == null ? null : d.claveEnHardware)),
          _Fila(t.claveRegistrada, _siNo(d.claveRegistrada), bien: d.claveRegistrada),
        ],
        acciones: [
          FilledButton(onPressed: _ocupado ? null : _enrolar, child: Text(t.enrolar)),
        ],
      );
}

// ── Piezas ─────────────────────────────────────────────────────────────────────────

class _Seccion extends StatelessWidget {
  const _Seccion({required this.titulo, required this.filas, this.acciones = const [], this.encabezado});

  final String titulo;
  final List<_Fila> filas;
  final List<Widget> acciones;
  final Widget? encabezado;

  @override
  Widget build(BuildContext context) {
    final m = context.medidas;
    final tema = Theme.of(context);
    return Card(
      margin: EdgeInsets.only(bottom: m.m),
      child: Padding(
        padding: EdgeInsets.all(m.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(titulo, style: tema.textTheme.titleMedium),
            SizedBox(height: m.s),
            if (encabezado != null) ...[encabezado!, SizedBox(height: m.s)],
            ...filas,
            if (acciones.isNotEmpty) ...[
              SizedBox(height: m.m),
              Wrap(spacing: m.s, runSpacing: m.s, children: acciones),
            ],
          ],
        ),
      ),
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila(this.etiqueta, this.valor, {this.bien, this.largo = false, this.copiable = false});

  final String etiqueta;
  final String valor;

  /// `true` verde · `false` rojo · `null` sin color.
  final bool? bien;
  final bool largo;
  final bool copiable;

  @override
  Widget build(BuildContext context) {
    final m = context.medidas;
    final tema = Theme.of(context);
    final color = switch (bien) {
      true => tema.colorScheme.primary,
      false => tema.colorScheme.error,
      null => tema.colorScheme.onSurface,
    };
    final texto = Text(valor,
        style: tema.textTheme.bodyMedium?.copyWith(color: color),
        textAlign: largo ? TextAlign.start : TextAlign.end);
    final cuerpo = largo || valor.isEmpty
        ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(etiqueta, style: tema.textTheme.bodyMedium?.copyWith(color: valor.isEmpty ? color : null)),
            if (valor.isNotEmpty) texto,
          ])
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(etiqueta, style: tema.textTheme.bodyMedium)),
              SizedBox(width: m.s),
              Flexible(child: texto),
            ],
          );
    return Padding(
      padding: EdgeInsets.symmetric(vertical: m.xs),
      child: copiable
          ? InkWell(onLongPress: () => Clipboard.setData(ClipboardData(text: valor)), child: cuerpo)
          : cuerpo,
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso(this.texto, {required this.alCerrar});
  final String texto;
  final VoidCallback alCerrar;

  @override
  Widget build(BuildContext context) {
    final m = context.medidas;
    final tema = Theme.of(context);
    return Card(
      color: tema.colorScheme.secondaryContainer,
      margin: EdgeInsets.only(bottom: m.m),
      child: Padding(
        padding: EdgeInsets.all(m.m),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: SelectableText(texto, style: tema.textTheme.bodyMedium)),
            IconButton(onPressed: alCerrar, icon: Icon(Icons.close, size: m.icono)),
          ],
        ),
      ),
    );
  }
}
