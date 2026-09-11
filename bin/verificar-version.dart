// Comprueba que `versionDelSdk` y `pubspec.yaml` digan lo mismo.
//
// 🔴 Existe por la regla de esta casa: cuando algo se puede desincronizar en silencio, no se
// escribe una advertencia — se le pone un script. Una versión que miente es peor que ninguna,
// porque se usa para decidir si un teléfono ya tiene un arreglo.
import 'dart:io';

void main() {
  final pubspec = File('pubspec.yaml').readAsStringSync();
  final fuente = File('lib/src/version.dart').readAsStringSync();

  final enPubspec = RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(pubspec)?.group(1);
  final enConstante = RegExp(r"versionDelSdk\s*=\s*'([^']+)'").firstMatch(fuente)?.group(1);

  if (enPubspec == null || enConstante == null) {
    stderr.writeln('🔴 No pude leer una de las dos versiones. pubspec=$enPubspec constante=$enConstante');
    exit(2);
  }
  if (enPubspec != enConstante) {
    stderr.writeln('🔴 La versión no coincide: pubspec.yaml dice "$enPubspec" y version.dart dice "$enConstante".');
    stderr.writeln('   Se actualizan LAS DOS al publicar. La que viaja al servidor es la constante.');
    exit(1);
  }
  stdout.writeln('✅ Las dos dicen $enPubspec.');
}
