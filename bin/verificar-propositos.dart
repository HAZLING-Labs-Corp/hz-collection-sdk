/// COMPRUEBA QUE TODA CATEGORÍA DEL CATÁLOGO TENGA SU PROPÓSITO.
///
/// 🔴 Sin este control, una señal nueva entra con una categoría propia y **desaparece de la
/// pantalla de configuración** sin ningún error: el comercio no la ve, no la puede apagar, y se
/// sigue midiendo igual. Es la clase de falla que este producto persigue — la que no falla.
///
///     dart run bin/verificar-propositos.dart
library;

import 'dart:io';
import 'package:hz_collection_sdk/src/permisologia/campos.dart';
import 'package:hz_collection_sdk/src/permisologia/propositos.dart';

void main() {
  final todos = [...camposDeSenales, ...camposDeAutenticidad];
  final sinMapear = <String, int>{};
  final porProposito = <String, int>{};

  for (final c in todos) {
    final cat = categoriaCruda(c.paraQue);
    final p = propositoDeLaCategoria[cat];
    if (p == null) {
      sinMapear[cat] = (sinMapear[cat] ?? 0) + 1;
    } else {
      porProposito[p] = (porProposito[p] ?? 0) + 1;
    }
  }

  stdout.writeln('\n  ${todos.length} campos · ${propositos.length} propósitos\n');
  for (final p in propositos) {
    stdout.writeln('  ${p.clave.padRight(16)}${(porProposito[p.clave] ?? 0).toString().padLeft(4)} campos   ${p.titulo}');
  }

  /* 🔴 Un propósito sin un solo campo también es un defecto: se le está ofreciendo al comercio
     algo que no mide nada. Se avisa, sin frenar — puede ser un propósito recién agregado para
     señales que vienen. */
  final vacios = propositos.where((p) => (porProposito[p.clave] ?? 0) == 0).toList();
  if (vacios.isNotEmpty) {
    stdout.writeln('\n  ⚠️  Sin ningún campo: ${vacios.map((p) => p.clave).join(', ')}');
  }

  if (sinMapear.isNotEmpty) {
    stdout.writeln('\n  🔴 ${sinMapear.length} categoría(s) sin propósito — esos campos no se van '
        'a poder configurar y nadie se entera:\n');
    sinMapear.forEach((cat, n) => stdout.writeln('     $n campo(s)  «$cat»'));
    stdout.writeln('\n  Agregalas en `propositos.dart`.\n');
    exit(1);
  }
  stdout.writeln('\n  Todas las categorías tienen su propósito.\n');
}
