/// EL DETECTOR DE GOLPE — puro: recibe muestras del acelerómetro y velocidades del GPS, y
/// dice si hubo un golpe seguido de quietud. No toca sensores, ni red, ni disco; por eso se
/// prueba entero con muestras sintéticas.
///
/// ══ QUÉ ES UN GOLPE ══
///
/// ```
///   VIGILANDO ──(|a| ≥ gPico, en g CON la gravedad)──► ASENTANDO (3 s: el teléfono rueda, rebota)
///   ASENTANDO ──(pasan 3 s)──► QUIETUD (quietudSeg segundos, en bloques de 5 s)
///   QUIETUD ──(un bloque se mueve, o el GPS dice que va a más de 1,5 m/s)──► VIGILANDO  (fue un bache)
///   QUIETUD ──(se cumplen quietudSeg)──► emite `golpe_quietud` y entra en ANTIREBOTE
///   ANTIREBOTE ──(pasan 5 min)──► VIGILANDO
/// ```
///
/// 🔴 **Un pico sin quietud no es nada.** Un bache en moto da 4-6 g y la persona sigue
/// rodando; lo que distingue un choque es que, después, el teléfono queda quieto (en el piso,
/// en el bolsillo de alguien tendido). Por eso la quietud se mide por bloques: que el
/// promedio de un minuto sea tranquilo no alcanza si en uno de sus bloques se movió.
///
/// ══ POR QUÉ CON LA GRAVEDAD ══
///
/// El Honor LLY-LX3 no trae el sensor «sin gravedad». El pico se mide sobre la magnitud del
/// acelerómetro común (en reposo ≈ 1 g), y la quietud sobre la DISPERSIÓN de esa magnitud,
/// que no depende de hacia dónde quedó apuntando el teléfono: así no hace falta ningún
/// filtro de gravedad, que además tarda segundos en asentarse después de un golpe.
library;

import 'dart:math' as math;

/// La gravedad estándar, m/s².
const double gravedad = 9.80665;

/// Una muestra del acelerómetro, en m/s² con la gravedad incluida (lo que da `sensors_plus`).
class MuestraDeAceleracion {
  const MuestraDeAceleracion({required this.t, required this.x, required this.y, required this.z});

  /// ms desde época.
  final int t;
  final double x;
  final double y;
  final double z;

  /// La magnitud en g.
  double get g => math.sqrt(x * x + y * y + z * z) / gravedad;
}

/// Los umbrales del golpe. Vienen del bloque `rastreo.golpe` de `/configuracion`
/// (`{ g, quietoSeg }`), que el servidor arma con los mismos números de su política
/// `sucesos` (`gPico`, `quietudSeg`). Lo que falta cae a 4 g y 60 s; lo que se sale, al piso
/// o al techo.
class UmbralesDeGolpe {
  const UmbralesDeGolpe({this.gPico = 4, this.quietudSeg = 60});

  final double gPico;
  final int quietudSeg;

  /// Por debajo de 2 g, una frenada o un tropiezo «chocan».
  static const pisoGPico = 2.0;

  /// Más de 16 g no lo mide la mayoría de los acelerómetros de teléfono: nunca dispararía.
  static const techoGPico = 16.0;
  static const pisoQuietudSeg = 10;
  static const techoQuietudSeg = 600;

  static const porOmision = UmbralesDeGolpe();

  factory UmbralesDeGolpe.fromJson(Object? crudo) {
    if (crudo is! Map) return porOmision;
    final g = crudo['g'] ?? crudo['gPico'];
    final q = crudo['quietoSeg'] ?? crudo['quietudSeg'];
    return UmbralesDeGolpe(
      gPico: g is num && g.isFinite ? g.toDouble().clamp(pisoGPico, techoGPico) : porOmision.gPico,
      quietudSeg: q is num && q.isFinite ? q.round().clamp(pisoQuietudSeg, techoQuietudSeg) : porOmision.quietudSeg,
    );
  }

  Map<String, dynamic> toJson() => {'g': gPico, 'quietoSeg': quietudSeg};
}

/// Lo que el detector concluye: hubo golpe y después quietud.
class GolpeDetectado {
  const GolpeDetectado({required this.t, required this.pico, required this.confianza, required this.conGps});

  /// La hora del pico (ms). Es la `t` del suceso y entra en su id.
  final int t;

  /// El pico, en g.
  final double pico;

  /// 0..1.
  final double confianza;

  /// Si el GPS confirmó la quietud (velocidad ~0) o no dijo nada.
  final bool conGps;
}

enum FaseDelGolpe { vigilando, asentando, quietud, antirebote }

class DetectorDeGolpe {
  DetectorDeGolpe([this.umbrales = UmbralesDeGolpe.porOmision]);

  UmbralesDeGolpe umbrales;

  /// Lo que el teléfono tarda en dejar de rodar después del golpe: no cuenta para la quietud.
  static const asentamiento = Duration(seconds: 3);

  /// La quietud se juzga en bloques de este largo.
  static const bloque = Duration(seconds: 5);

  /// Dispersión máxima de la magnitud en un bloque, en g. Un teléfono en el piso da ~0,01 g;
  /// en el bolsillo de alguien que camina, ~0,2-0,3 g; en una moto andando, más.
  static const dispersionMaxima = 0.08;

  /// Por encima de esto (m/s, ~5 km/h) el GPS dice que sigue andando: fue un bache.
  static const velocidadMaxima = 1.5;

  /// Después de un suceso, cuánto se ignoran los picos: un solo suceso por golpe.
  static const antirebote = Duration(minutes: 5);

  /// Un bloque con menos muestras no se juzga (el sistema entregó poco): no aprueba ni reprueba.
  static const muestrasMinimasPorBloque = 3;

  FaseDelGolpe _fase = FaseDelGolpe.vigilando;
  FaseDelGolpe get fase => _fase;

  int _tPico = 0;
  double _pico = 0;
  int _inicioQuietud = 0;
  int _inicioBloque = 0;
  int _hastaAntirebote = 0;

  // Welford del bloque en curso
  int _n = 0;
  double _media = 0;
  double _m2 = 0;
  double _peorDispersion = 0;
  bool _bloquesJuzgados = false;
  bool _gpsDijoQuieto = false;

  /// Si está midiendo un golpe (quien lo alimenta no tiene que apagar el sensor).
  bool get ocupado => _fase == FaseDelGolpe.asentando || _fase == FaseDelGolpe.quietud;

  void _volver() {
    _fase = FaseDelGolpe.vigilando;
    _n = 0;
  }

  void _nuevoBloque(int t) {
    _inicioBloque = t;
    _n = 0;
    _media = 0;
    _m2 = 0;
  }

  /// Una velocidad del GPS (m/s) con su hora. Sólo importa durante la quietud.
  void velocidad(double v, int t) {
    if (_fase != FaseDelGolpe.quietud && _fase != FaseDelGolpe.asentando) return;
    if (t < _tPico) return;
    if (_fase == FaseDelGolpe.quietud && t >= _inicioQuietud && v > velocidadMaxima) {
      _volver(); // sigue andando: bache
      return;
    }
    if (_fase == FaseDelGolpe.quietud && t >= _inicioQuietud && v >= 0 && v <= velocidadMaxima) {
      _gpsDijoQuieto = true;
    }
  }

  /// Una muestra. Devuelve el golpe si con ella se completó la quietud.
  GolpeDetectado? muestra(MuestraDeAceleracion m) {
    final g = m.g;
    if (!g.isFinite) return null;
    switch (_fase) {
      case FaseDelGolpe.antirebote:
        if (m.t < _hastaAntirebote) return null;
        _fase = FaseDelGolpe.vigilando;
        return muestra(m);
      case FaseDelGolpe.vigilando:
        if (g >= umbrales.gPico) {
          _fase = FaseDelGolpe.asentando;
          _tPico = m.t;
          _pico = g;
          _gpsDijoQuieto = false;
        }
        return null;
      case FaseDelGolpe.asentando:
        if (g > _pico) _pico = g;
        if (m.t - _tPico >= asentamiento.inMilliseconds) {
          _fase = FaseDelGolpe.quietud;
          _inicioQuietud = m.t;
          _peorDispersion = 0;
          _bloquesJuzgados = false;
          _nuevoBloque(m.t);
          return _acumular(m.t, g);
        }
        return null;
      case FaseDelGolpe.quietud:
        return _acumular(m.t, g);
    }
  }

  GolpeDetectado? _acumular(int t, double g) {
    if (t - _inicioBloque >= bloque.inMilliseconds) {
      if (!_cerrarBloque()) return null;
      _nuevoBloque(t);
    }
    _n++;
    final d = g - _media;
    _media += d / _n;
    _m2 += d * (g - _media);
    if (t - _inicioQuietud >= umbrales.quietudSeg * 1000) {
      if (!_cerrarBloque()) return null;
      if (!_bloquesJuzgados) {
        _volver(); // no hubo con qué juzgar la quietud: no se afirma nada
        return null;
      }
      final golpe = GolpeDetectado(
        t: _tPico,
        pico: _pico,
        confianza: confianzaDe(_pico, _peorDispersion, _gpsDijoQuieto),
        conGps: _gpsDijoQuieto,
      );
      _fase = FaseDelGolpe.antirebote;
      _hastaAntirebote = t + antirebote.inMilliseconds;
      _n = 0;
      return golpe;
    }
    return null;
  }

  /// Juzga el bloque en curso. `false` si se movió (y entonces vuelve a vigilar).
  bool _cerrarBloque() {
    if (_n < muestrasMinimasPorBloque) return true;
    final disp = math.sqrt(_m2 / _n);
    if (disp > dispersionMaxima) {
      _volver();
      return false;
    }
    _bloquesJuzgados = true;
    if (disp > _peorDispersion) _peorDispersion = disp;
    return true;
  }

  /// LA CONFIANZA (0..1) = la del pico × la de la quietud × la del GPS.
  ///
  ///  · pico: 0,5 justo en `gPico`, sube lineal hasta 1 en el doble.
  ///  · quietud: 1 con el teléfono inmóvil, 0,5 con la dispersión al borde del máximo.
  ///  · GPS: 1 si confirmó velocidad ~0; 0,85 si no dijo nada (sin fix, en un túnel).
  double confianzaDe(double pico, double peorDispersion, bool conGps) {
    final p = 0.5 + 0.5 * ((pico - umbrales.gPico) / umbrales.gPico).clamp(0.0, 1.0);
    final q = 1 - 0.5 * (peorDispersion / dispersionMaxima).clamp(0.0, 1.0);
    final c = p * q * (conGps ? 1.0 : 0.85);
    return (c.clamp(0.0, 1.0) * 100).round() / 100;
  }

  /// Muestras sintéticas de un golpe: [antesSeg] rodando (1 g con ruido de 0,3 g), un pico de
  /// [pico] g, y quietud (1 g con ruido de 0,005 g) hasta pasar la quietud pedida. A 20 Hz.
  /// Las usa `Rastreo.simularGolpe` y las pruebas: el MISMO detector las juzga.
  static List<MuestraDeAceleracion> muestrasDeGolpe({
    required int desde,
    required UmbralesDeGolpe umbrales,
    double? pico,
    int antesSeg = 2,
    bool quietudDespues = true,
    int semilla = 7,
  }) {
    final azar = math.Random(semilla);
    final out = <MuestraDeAceleracion>[];
    const paso = 50; // ms
    var t = desde;
    MuestraDeAceleracion m(double g, double ruido) {
      final v = (g + (azar.nextDouble() * 2 - 1) * ruido) * gravedad;
      return MuestraDeAceleracion(t: t, x: 0, y: 0, z: v);
    }

    for (var i = 0; i < antesSeg * 1000 ~/ paso; i++, t += paso) {
      out.add(m(1, 0.3));
    }
    final p = pico ?? umbrales.gPico * 1.5;
    final tPico = t;
    for (var i = 0; i < 3; i++, t += paso) {
      out.add(m(p, 0));
    }
    final fin = tPico + asentamiento.inMilliseconds + umbrales.quietudSeg * 1000 + 1000;
    for (; t <= fin; t += paso) {
      // el teléfono rueda mientras dura el asentamiento; después, inmóvil
      final enAsentamiento = t < tPico + asentamiento.inMilliseconds;
      out.add(quietudDespues
          ? m(1, enAsentamiento ? 0.5 : 0.005)
          : m(1, 0.3));
    }
    return out;
  }
}

/// UN GOLPE SINTÉTICO, juzgado por una instancia aparte del detector (el que escucha el sensor
/// no se toca). Sin [confianzaMinima], un solo intento con [pico] (o 1,5 × `gPico`). Con ella, se
/// prueba de menor a mayor —el pico pedido o 1,5 × `gPico`; 2 × `gPico`; 2 × `gPico` con el GPS
/// confirmando la quietud (velocidad 0)— y sale el primero que la alcanza; si ninguno, el más
/// fuerte. `null` si el detector no concluyó ninguno.
GolpeDetectado? golpeSintetico({
  required UmbralesDeGolpe umbrales,
  required int desde,
  double? pico,
  double? confianzaMinima,
}) {
  GolpeDetectado? juzgar(double? p, bool conGps) {
    final d = DetectorDeGolpe(umbrales);
    GolpeDetectado? g;
    for (final m in DetectorDeGolpe.muestrasDeGolpe(desde: desde, umbrales: umbrales, pico: p)) {
      g = d.muestra(m) ?? g;
      if (conGps) d.velocidad(0, m.t);
    }
    return g;
  }

  if (confianzaMinima == null) return juzgar(pico, false);
  final fuerte = math.max(pico ?? 0, umbrales.gPico * 2);
  GolpeDetectado? mejor;
  for (final (p, gps) in [(pico, false), (fuerte, false), (fuerte, true)]) {
    final g = juzgar(p, gps);
    if (g == null) continue;
    if (g.confianza >= confianzaMinima) return g;
    if (mejor == null || g.confianza > mejor.confianza) mejor = g;
  }
  return mejor;
}
