/// EL JSON CANÓNICO DEL LOTE — lo que se hashea y lo que se firma.
///
/// ══ 🔴 POR QUÉ ESTO NO ES `jsonEncode` Y YA ══
///
/// La ingesta está escrita en TypeScript y va a recalcular el hash con `JSON.stringify`
/// sobre el cuerpo con las claves ordenadas. Si los bytes de acá y los de allá difieren en
/// UN carácter, la firma no verifica y el lote se rechaza con 401 — **en todos los
/// teléfonos, siempre**, sin un error que diga por qué.
///
/// Y Dart y JavaScript NO escriben los números igual:
///
///   · `5.0` en Dart es `"5.0"`; en JavaScript es `"5"`.
///   · `-0.0` en Dart es `"-0.0"`; en JavaScript es `"0"`.
///
/// Una velocidad de exactamente 5 m/s bastaba para romper la cadena. Por eso los números
/// se escriben acá como los escribe JavaScript: un double entero sale sin decimales, el
/// cero negativo sale como cero, y el resto usa la representación más corta que vuelve al
/// mismo double (que en los dos lenguajes es el mismo algoritmo para los rangos de un
/// punto: coordenadas, metros, grados, milisegundos).
///
/// Las claves se ordenan por unidades de código UTF-16, que es lo que hace el `sort()` por
/// omisión de JavaScript y lo que hace `String.compareTo` de Dart.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

/// El texto canónico de [valor]: claves ordenadas, sin espacios, números como JavaScript.
String jsonCanonico(Object? valor) {
  final b = StringBuffer();
  _escribir(b, valor);
  return b.toString();
}

/// SHA-256 en hexadecimal minúscula de los bytes UTF-8 de [texto].
String sha256Hex(String texto) => sha256.convert(utf8.encode(texto)).toString();

void _escribir(StringBuffer b, Object? v) {
  if (v == null) {
    b.write('null');
  } else if (v is bool) {
    b.write(v ? 'true' : 'false');
  } else if (v is int) {
    b.write(v);
  } else if (v is double) {
    b.write(numeroComoJavaScript(v));
  } else if (v is String) {
    // `jsonEncode` de un String escapa igual que `JSON.stringify` para todo lo que viaja
    // en un lote (uuids, hex, base64, nombres de perfil).
    b.write(jsonEncode(v));
  } else if (v is List) {
    b.write('[');
    for (var i = 0; i < v.length; i++) {
      if (i > 0) b.write(',');
      _escribir(b, v[i]);
    }
    b.write(']');
  } else if (v is Map) {
    final claves = v.keys.map((k) => '$k').toList()..sort();
    b.write('{');
    var primero = true;
    for (final k in claves) {
      final x = v[k];
      if (!primero) b.write(',');
      primero = false;
      b.write(jsonEncode(k));
      b.write(':');
      _escribir(b, x);
    }
    b.write('}');
  } else {
    throw ArgumentError('No se puede escribir en JSON canónico: ${v.runtimeType}');
  }
}

/// Un double como lo escribe `JSON.stringify`.
///
/// 🔴 `NaN` e `Infinity` no existen en JSON — JavaScript los escribe `null`. Acá se niega:
/// un punto con una coordenada infinita es un punto roto, y firmarlo como `null` escondería
/// el defecto del GPS en vez de mostrarlo.
String numeroComoJavaScript(double d) {
  if (!d.isFinite) {
    throw ArgumentError('Un número no finito no se puede firmar: $d');
  }
  if (d == 0) return '0'; // incluye -0.0
  if (d == d.truncateToDouble() && d.abs() < 1e21) {
    return d.toInt().toString();
  }
  final s = d.toString();
  // Dart escribe `1e-7` y `1.5e+21` igual que JavaScript; lo único que cambia es la
  // mantisa entera con `.0` delante de la `e` (Dart: `1.0e-7`).
  return s.replaceFirst('.0e', 'e');
}
