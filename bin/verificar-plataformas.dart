/// COMPRUEBA QUE LA MARCA DE PLATAFORMA DE CADA GRUPO SEA CIERTA.
///
/// 🔴 Existe porque `GrupoDeSenales.plataformas` se declara a mano y los plugins cambian solos.
/// El día que alguien agregue una señal `acc_` al plugin de iOS y se olvide de tocar el
/// catálogo, la consola va a seguir diciéndole a los comercios que ese grupo no existe en iOS —
/// y ese error no se nota: simplemente no se ofrece algo que sí se podía medir.
///
/// Cuenta las claves de cada plugin nativo por prefijo y las contrasta con lo declarado.
///
///     dart run hz_collection_sdk:verificar-plataformas
library;

import 'dart:io';
import 'package:hz_collection_sdk/src/permisologia/campos.dart';

void main() {
  final android = File(
    'android/src/main/kotlin/com/hazling/collection/SenalesPlugin.kt',
  ).readAsStringSync();
  final ios = File('ios/Classes/SenalesPlugin.swift').readAsStringSync();
  final claves = RegExp(r'"([a-z][a-z0-9_]{3,})"');

  Set<String> de(String t) => claves.allMatches(t).map((m) => m.group(1)!).toSet();
  final enAndroid = de(android), enIos = de(ios);

  var fallas = 0;
  for (final g in gruposDeSenales) {
    final a = enAndroid.where((k) => k.startsWith(g.prefijo)).length;
    final i = enIos.where((k) => k.startsWith(g.prefijo)).length;
    final deberia = <String>[
      if (a > 0) 'ANDROID',
      if (i > 0) 'IOS',
    ];
    final declarado = [...g.plataformas]..sort();
    final medido = [...deberia]..sort();
    final ok = declarado.join(',') == medido.join(',');
    if (!ok) fallas++;
    stdout.writeln(
      '  ${ok ? '·' : '🔴'} ${g.prefijo.padRight(8)}'
      'Android:$a iOS:$i  ·  declarado ${g.plataformas.join('+')}'
      '${ok ? '' : '  ← debería ser ${deberia.isEmpty ? '(ninguna)' : deberia.join('+')}'}',
    );
  }

  if (fallas > 0) {
    stdout.writeln('\n  $fallas grupo(s) con la marca desactualizada. Corregí `campos.dart`.\n');
    exit(1);
  }
  stdout.writeln('\n  Las ${gruposDeSenales.length} marcas coinciden con lo que reportan los plugins.\n');
}
