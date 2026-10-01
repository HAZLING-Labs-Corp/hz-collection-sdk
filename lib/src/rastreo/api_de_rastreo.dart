/// LAS TRES LLAMADAS DEL RASTREO A LA INGESTA — y ninguna por punto.
///
///   · `POST /api/v1/rastreo/claves`   — una vez, al enrolar (y de nuevo si un 401 lo pide).
///   · `POST /api/v1/rastreo/lotes`    — cada ~5 min o 40 puntos mientras se mueve.
///   · `GET  /api/v1/configuracion`    — al arrancar y cada hora, sólo el bloque `rastreo`.
///
/// ══ 🔴 NO TIRA EXCEPCIONES AL ENVIAR UN LOTE ══
///
/// A diferencia de `AkPushApi._pedir`, `enviarLote` devuelve siempre una [RespuestaDeIngesta]
/// con el código —o `null` si no hubo red— y el `Retry-After` si vino. Quien decide qué
/// hacer con un 429, un 401 o un corte es el emisor, y necesita los tres casos separados:
/// tratarlos a todos como «falló» es cómo un SDK termina martillando una ingesta caída.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../api_client.dart';

class RespuestaDeIngesta {
  const RespuestaDeIngesta({this.codigo, this.cuerpo, this.reintentarEn, this.error});

  /// El código HTTP, o `null` si no hubo respuesta (sin red, DNS, timeout).
  final int? codigo;

  /// El cuerpo de la respuesta, recortado a 500 caracteres para el diagnóstico.
  final String? cuerpo;

  /// Lo que dijo `Retry-After`, si vino.
  final Duration? reintentarEn;

  /// Por qué no hubo respuesta, si no la hubo.
  final String? error;

  bool get aceptado => codigo != null && codigo! >= 200 && codigo! < 300;
}

class ApiDeRastreo {
  ApiDeRastreo({
    required this.llave,
    required String url,
    String? urlIngesta,
    http.Client? cliente,
    this.timeout = const Duration(seconds: 20),
  })  : baseUrl = AkPushApi.normalizarUrl(url),
        _baseIngestaLocal = AkPushApi.normalizarUrl(urlIngesta ?? url),
        _cliente = cliente ?? http.Client();

  final String llave;

  /// La API de Collection: `/configuracion` (y, en `Rastreo`, instalaciones y sujetos).
  final String baseUrl;

  /// La ingesta: `/rastreo/claves` y `/rastreo/lotes`. Es un proceso aparte (PM-025 §5 B)
  /// con otra dirección. Manda la que diga el servidor en `rastreo.ingestaUrl`; si no la
  /// dice (todavía no la sirve), la que pasó la aplicación; si tampoco, la de la API.
  String get baseIngesta => _baseIngestaDelServidor ?? _baseIngestaLocal;
  final String _baseIngestaLocal;
  String? _baseIngestaDelServidor;

  /// Aplica `rastreo.ingestaUrl`. Sólo http/https; otra cosa se ignora.
  void usarIngestaDelServidor(String? url) {
    final u = url == null ? null : Uri.tryParse(url.trim());
    _baseIngestaDelServidor =
        (u != null && (u.scheme == 'https' || u.scheme == 'http') && u.host.isNotEmpty)
            ? AkPushApi.normalizarUrl(url!.trim())
            : null;
  }
  final Duration timeout;
  final http.Client _cliente;

  Map<String, String> get _cabeceras => {
        'content-type': 'application/json',
        'authorization': 'Bearer $llave',
      };

  /// Registra la pública del aparato: `{ instalacionId, clavePublica, claveId, alg }`
  /// (RESUMEN-B §8). `clavePublica` es el SPKI DER en base64 —Android lo da así; en iOS el
  /// nativo le antepone el encabezado fijo de P-256—. 201 nueva · 200 ya estaba ·
  /// 409 `ya_tiene_clave` (esta instalación ya tiene otra: no se pisa).
  Future<RespuestaDeIngesta> registrarClave({
    required String instalacionId,
    required String claveId,
    required String publicaSpkiBase64,
    Map<String, dynamic>? atestacion,
  }) =>
      _mandar(() => _cliente.post(
            Uri.parse('$baseIngesta/api/v1/rastreo/claves'),
            headers: _cabeceras,
            body: jsonEncode({
              'instalacionId': instalacionId,
              'claveId': claveId,
              'clavePublica': publicaSpkiBase64,
              'alg': 'ES256',
              if (atestacion != null) 'atestacion': atestacion,
            }),
          ));

  /// Manda los bytes EXACTOS del lote armado. No los vuelve a serializar.
  Future<RespuestaDeIngesta> enviarLote(String cuerpo) => _mandar(() => _cliente.post(
        Uri.parse('$baseIngesta/api/v1/rastreo/lotes'),
        headers: _cabeceras,
        body: utf8.encode(cuerpo),
      ));

  /// PRESENCIA (§4.2): dónde está ahora, liviana y de un solo uso (no se encola ni se reintenta:
  /// una presencia vieja no sirve). Devuelve el resultado sólo para el diagnóstico.
  Future<RespuestaDeIngesta> enviarPresencia(Map<String, dynamic> cuerpo) => _mandar(() => _cliente.post(
        Uri.parse('$baseIngesta/api/v1/rastreo/presencia'),
        headers: _cabeceras,
        body: jsonEncode(cuerpo),
      ));

  /// El bloque `rastreo` de la configuración, o `null` si no vino (o no se pudo leer).
  /// El segundo valor es el código, para el diagnóstico.
  Future<(Map<String, dynamic>?, RespuestaDeIngesta)> leerConfiguracion(
      String paquete) async {
    final r = await _mandar(() => _cliente.get(
          Uri.parse('$baseUrl/api/v1/configuracion')
              .replace(queryParameters: {'paquete': paquete}),
          headers: _cabeceras,
        ));
    if (!r.aceptado) return (null, r);
    try {
      final j = jsonDecode(r.cuerpoCompleto ?? '');
      final bloque = j is Map ? j['rastreo'] : null;
      return (bloque is Map ? bloque.cast<String, dynamic>() : null, r);
    } catch (_) {
      return (null, r);
    }
  }

  Future<_Respuesta> _mandar(Future<http.Response> Function() peticion) async {
    try {
      final r = await peticion().timeout(timeout);
      final cuerpo = r.body;
      return _Respuesta(
        codigo: r.statusCode,
        cuerpo: cuerpo.length > 500 ? '${cuerpo.substring(0, 500)}…' : cuerpo,
        cuerpoCompleto: cuerpo,
        reintentarEn: leerRetryAfter(r.headers['retry-after'], DateTime.now()),
      );
    } catch (e) {
      return _Respuesta(error: '$e');
    }
  }

  /// `Retry-After` en segundos o como fecha HTTP. Lo que no se entiende, `null`.
  static Duration? leerRetryAfter(String? v, DateTime ahora) {
    if (v == null || v.trim().isEmpty) return null;
    final seg = int.tryParse(v.trim());
    if (seg != null) return Duration(seconds: seg < 0 ? 0 : seg);
    try {
      final cuando = leerFechaHttp(v.trim());
      final d = cuando.difference(ahora);
      return d.isNegative ? Duration.zero : d;
    } catch (_) {
      return null;
    }
  }
}

/// Una fecha HTTP (RFC 7231: `Wed, 21 Oct 2015 07:28:00 GMT`).
DateTime leerFechaHttp(String v) {
  const meses = {
    'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
    'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12,
  };
  final p = v.split(RegExp(r'[ ,:]+')).where((x) => x.isNotEmpty).toList();
  // [Wed, 21, Oct, 2015, 07, 28, 00, GMT]
  return DateTime.utc(int.parse(p[3]), meses[p[2]]!, int.parse(p[1]), int.parse(p[4]),
      int.parse(p[5]), int.parse(p[6]));
}

class _Respuesta extends RespuestaDeIngesta {
  const _Respuesta({
    super.codigo,
    super.cuerpo,
    super.reintentarEn,
    super.error,
    this.cuerpoCompleto,
  });
  final String? cuerpoCompleto;
}
