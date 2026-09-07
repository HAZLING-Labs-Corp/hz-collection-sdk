/// Las fichas de las señales de nivel 0.
///
/// 🔴 No prueban que el teléfono devuelva algo —eso necesita un teléfono—, sino lo que sí se
/// puede probar sin uno y es donde de verdad se rompe: que ninguna ficha esté mal declarada.
/// Un campo mal declarado no falla: manda algo distinto de lo que dice que manda, y nadie se
/// entera hasta que alguien pregunta qué se sabe de él.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:hz_collection_sdk/src/modulos/modulo_senales.dart';
import 'package:hz_collection_sdk/src/permisologia/transformar.dart';

void main() {
  group('las fichas de señales', () {
    test('ningún nombre repetido', () {
      final vistos = <String>{};
      for (final c in camposDeSenales) {
        expect(vistos.add(c.nombre), isTrue, reason: '«${c.nombre}» está declarado dos veces');
      }
    });

    test('todas dicen qué mandan, en una frase de verdad', () {
      for (final c in camposDeSenales) {
        expect(c.queManda.trim(), isNotEmpty, reason: c.nombre);
        // El umbral atrapa lo vacío y el nombre del campo disfrazado de frase; no discute
        // estilo. Se puso en cinco y lo bajó una prueba: «si tiene giroscopio» son tres
        // palabras y está perfectamente dicho. Una regla que obliga a inflar una frase clara
        // empeora justo lo que quería cuidar.
        expect(c.queManda.split(' ').length, greaterThan(2), reason: '«${c.nombre}» no explica nada');
      }
    });

    test('ningún grupo quedó sin campos', () {
      for (final prefijo in ['cfg_', 'acc_', 'bat_', 'sen_', 'usr_', 'red_', 'hd_', 'canal_', 'ent_']) {
        expect(camposDeSenales.any((c) => c.nombre.startsWith(prefijo)), isTrue,
            reason: 'el grupo «$prefijo» no tiene ni un campo declarado');
      }
    });

    test('el grupo de NBER está entero: sin él este módulo es sólo el de CredoLab', () {
      // La huella digital es el único grupo con respaldo auditado por terceros. Si alguien
      // la borra por «simplificar», que se entere acá y no en el puntaje.
      for (final imprescindible in [
        'hd_hora_local',
        'hd_marca',
        'hd_pais_coherente',
        'hd_vino_de_la_tienda',
        'hd_meses_sin_parche',
      ]) {
        expect(camposDeSenales.any((c) => c.nombre == imprescindible), isTrue,
            reason: 'falta «$imprescindible»');
      }
    });

    test('lo que no está declarado no sale, aunque el teléfono lo mande', () {
      final salida = armarPaquete(camposDeSenales, {
        'hd_marca': 'Xiaomi',
        'cfg_adb_enabled': '0',
        // Esto es lo que se prueba: una clave que alguien agregue mañana del lado nativo
        // NO puede viajar sin ficha. Sin esta regla, el catálogo miente por omisión.
        'imei': '355458061234567',
        'numero': '+584121234567',
      });
      expect(salida.containsKey('imei'), isFalse);
      expect(salida.containsKey('numero'), isFalse);
      expect(salida['hd_marca'], 'Xiaomi');
    });

    test('los tramos redondean hacia abajo y no delatan el valor exacto', () {
      final salida = armarPaquete(camposDeSenales, {
        'hd_ram_total_mb': 3894,
        'hd_dias_desde_la_instalacion': 43,
        'hd_horas_desde_el_arranque': 71,
      });
      expect(salida['hd_ram_total_mb'], 3584); // tramos de 512
      expect(salida['hd_dias_desde_la_instalacion'], 42); // semanas
      expect(salida['hd_horas_desde_el_arranque'], 48); // días
    });

    test('un campo que no se pudo medir no viaja como cero', () {
      // «Nulo no es cero»: si el fabricante no expone el voltaje, ese teléfono no puede
      // entrar a una estadística como si tuviera la batería en cero.
      final salida = armarPaquete(camposDeSenales, {'hd_marca': 'Samsung'});
      expect(salida.containsKey('bat_voltaje_mv'), isFalse);
      expect(salida.length, 1);
    });
  });
}
