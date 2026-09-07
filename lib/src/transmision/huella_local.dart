/// LO ÚLTIMO QUE ESTE TELÉFONO LE MANDÓ AL SERVICIO, POR MÓDULO.
///
/// ══ POR QUÉ LA HUELLA VIVE EN EL TELÉFONO Y NO SÓLO EN EL SERVIDOR ══
///
/// El servidor ya calcula su propio delta —lo hace desde que existe la escritura a
/// destinos— pero lo calcula **después de recibir la medición**. Eso ahorra escrituras en
/// la base y no ahorra ni un byte de red ni un milisegundo de radio: la petición ya salió.
/// La única forma de no gastar la llamada es decidir de este lado, antes de hablar.
///
/// ══ 🔴 SE GUARDA EL HASH, NUNCA EL VALOR ══
///
/// Guardar los valores sería tener una segunda copia de los datos de la persona adentro del
/// teléfono, y de las dos copias una envejece. Con el hash alcanza para contestar la única
/// pregunta que esta clase tiene que contestar —*«¿esto cambió?»*— y no es una segunda copia
/// de nada. Es el mismo razonamiento que el back escribió para `HuellaEnviada`, y vale igual
/// de este lado.
///
/// ══ QUÉ PASA SI LA HUELLA SE PIERDE ══
///
/// Se manda todo de nuevo, una vez. Perder la huella es el caso barato: cuesta una
/// transmisión de más. El caso caro es el contrario —creer que se mandó algo que no se
/// mandó— y contra ése está la resincronización de los siete días.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'politica_de_transmision.dart';

class HuellaLocal {
  const HuellaLocal({this.comercio = ''});

  /// 🔴 DE QUÉ COMERCIO ES ESTA HUELLA. Sin esto, cambiar de comercio rompe la recolección.
  ///
  /// Encontrado el 2026-09-06 midiendo por qué un comercio recibía 18 señales y otro 125, con
  /// el mismo teléfono y la misma aplicación. La cadena era ésta:
  ///
  ///   1. el teléfono mide sus ~125 señales y se las manda a Rodar
  ///   2. anota en el disco «ya mandé esto», con la clave `akpush.huellaEnviada.senales`
  ///   3. se cambia a mundototal — que del otro lado NO TIENE NADA
  ///   4. mide otra vez, compara contra esa huella, y concluye «no cambió nada»
  ///   5. **no manda**. Y como el bloque básico del aparato viaja por otro camino que no
  ///      consulta al portero, del otro lado quedan 18 señales y ninguna de los módulos.
  ///
  /// La persona queda inevaluable para siempre, en silencio: los tres motores dicen «0 de 38
  /// reglas» y la consola lo muestra como «no sumó puntos», que se lee como que la miramos.
  ///
  /// 🔴 Y LA CLAVE LLEVA EL COMERCIO EN VEZ DE BORRARSE AL CAMBIAR. Borrar también arreglaría
  /// el defecto, pero volver al comercio anterior retransmitiría las 125 señales que ese
  /// comercio ya tiene — y con dos comercios en uso alternado, cada cambio pagaría un barrido
  /// completo. Con el comercio en la clave, cada uno recuerda lo suyo y ninguno pisa al otro.
  ///
  /// Vacío conserva la clave vieja, así que un SDK que todavía no lo pase se comporta igual.
  final String comercio;

  String get _sufijo => comercio.isEmpty ? '' : '.$comercio';

  String _clave(String modulo) => 'akpush.huellaEnviada.$modulo$_sufijo';
  String _claveResync(String modulo) => 'akpush.resincronizado.$modulo$_sufijo';

  /// Lo último que se mandó de este módulo: `nombre del campo → hash`. Vacío si nunca.
  Future<Map<String, String>> leer(String modulo) async {
    try {
      final crudo =
          (await SharedPreferences.getInstance()).getString(_clave(modulo));
      if (crudo == null) return const {};
      final j = jsonDecode(crudo);
      if (j is! Map) return const {};
      return j.map((k, v) => MapEntry('$k', '$v'));
    } catch (_) {
      // Una huella ilegible es peor que ninguna: se descarta y se manda todo de nuevo.
      return const {};
    }
  }

  Future<DateTime?> ultimaResincronizacion(String modulo) async {
    try {
      final crudo = (await SharedPreferences.getInstance())
          .getString(_claveResync(modulo));
      return crudo == null ? null : DateTime.tryParse(crudo);
    } catch (_) {
      return null;
    }
  }

  /// Anota que ESTO se mandó, y cuándo.
  ///
  /// [fueResincronizacion] mueve además el reloj de los siete días, y **se mueve sólo cuando
  /// lo que salió fue la medición completa**. Hoy siempre lo es —el delta decide *si* se
  /// manda, nunca *qué* se manda, ver `ModuloDeSenales`— así que en la práctica va siempre
  /// en `true`. El parámetro existe igual: el día que alguien mande de verdad sólo los
  /// campos que cambiaron, correr el reloj ahí apagaría la resincronización justo en los
  /// teléfonos que más se mueven, que son los que más la necesitan.
  Future<void> anotar(
    String modulo,
    Map<String, Object?> medido, {
    required bool fueResincronizacion,
    DateTime? cuando,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_clave(modulo), jsonEncode(huellaDe(medido)));
      if (fueResincronizacion) {
        await prefs.setString(_claveResync(modulo),
            (cuando ?? DateTime.now()).toIso8601String());
      }
    } catch (_) {
      // Sin huella se manda de más la próxima vez. Barato, y nunca al revés.
    }
  }

  /// Se olvida de un módulo. Se usa desde el diagnóstico y desde las pruebas: es la forma
  /// de forzar una transmisión completa sin esperar siete días.
  Future<void> olvidar(String modulo) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_clave(modulo));
      await prefs.remove(_claveResync(modulo));
    } catch (_) {}
  }
}

/// EL PORTERO: junta la huella del disco con la decisión pura, y contesta si se manda.
///
/// Está separado de [decidirEnvio] a propósito. La decisión es aritmética y se prueba sin
/// teléfono; esto es el disco. Mezclarlos habría dejado la única parte con reglas de negocio
/// —qué cuenta como cambio— detrás de un `SharedPreferences` que no corre en una prueba.
class PorteroDeEnvio {
  PorteroDeEnvio({
    this.politica = PoliticaDeTransmision.porOmision,
    this.huellas = const HuellaLocal(),
  });

  final PoliticaDeTransmision politica;
  final HuellaLocal huellas;

  /// Lo último que se decidió de cada módulo, para que salga en el diagnóstico. Sin esto,
  /// «no mandó porque no cambió nada» y «no mandó porque falló» se ven iguales, que es el
  /// error que ya costó una tarde con las señales que el servicio descartaba en silencio.
  final Map<String, DecisionDeEnvio> ultimaDecision = {};

  Future<DecisionDeEnvio> decidir({
    required String modulo,
    required Map<String, Object?> medido,
    DateTime? ahora,
  }) async {
    final d = decidirEnvio(
      modulo: modulo,
      medido: medido,
      huellaAnterior: await huellas.leer(modulo),
      ultimaResincronizacion: await huellas.ultimaResincronizacion(modulo),
      ahora: ahora ?? DateTime.now(),
      politica: politica,
    );
    ultimaDecision[modulo] = d;
    return d;
  }

  /// Se llama DESPUÉS de que el servicio aceptó, nunca antes.
  ///
  /// 🔴 Anotar antes de que el envío llegue es el error que rompe todo el mecanismo: la
  /// huella diría que el servidor tiene algo que no tiene, y ese campo no se volvería a
  /// mandar hasta la resincronización. Por eso esto es un método aparte y no pasa adentro
  /// de [decidir].
  Future<void> anotarQueLlego({
    required String modulo,
    required Map<String, Object?> medido,
    DateTime? ahora,
  }) =>
      huellas.anotar(
        modulo,
        medido,
        // Cualquier envío que llegó sirve de resincronización, porque lo que viaja es la
        // medición ENTERA y no el delta: del otro lado quedan los 105 campos, no los tres
        // que cambiaron. Corriendo el reloj acá, un teléfono que cambia seguido no paga
        // además una transmisión semanal que no aportaría nada nuevo.
        fueResincronizacion: true,
        cuando: ahora,
      );
}
