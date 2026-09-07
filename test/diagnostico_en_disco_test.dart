import 'dart:convert';

import 'package:hz_collection_sdk/hz_collection_sdk.dart';
import 'package:hz_collection_sdk/src/permiso.dart' show GestorDePermiso;
import 'package:firebase_messaging/firebase_messaging.dart'
    show AuthorizationStatus;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'mensajeria_falsa.dart';

/// El caso número uno de soporte: `init()` no terminó.
///
/// Cuando `init()` explota a la mitad, la fachada no tiene nada en memoria —ni
/// configuración, ni token, ni usuario— y un diagnóstico que se creyera eso
/// contestaría «no hay nada» sobre un teléfono que sí guardó todo en el arranque
/// anterior. Manda a buscar el problema al lugar equivocado, que es peor que no
/// decir nada.
///
/// Va en su propio archivo porque montar el disco de mentira reemplaza el
/// almacenamiento de TODO el aislado: mezclado con las pruebas de «no hay
/// disco», cualquiera de las dos deja de probar lo que dice su nombre según el
/// orden en que corran.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const guardado = {
    'firebase': {
      'projectId': 'mundototal-72162',
      'appId': '1:859769563262:android:69c967f8f8d0a8c516902f',
      'apiKey': 'AIza-falsa-para-la-prueba',
      'messagingSenderId': '859769563262',
    },
    'version': '7',
    'comercio': 'mundototal',
  };

  const tokenEntero = 'cX9aQ2fH7kLmN0pR3sT6vW9yZ2bE5hJ8kM1nQ4tX7zA0dG3jL6oS9uB2eH5kN8f1b';

  Future<Diagnostico> diagnosticar() => Diagnostico.reunir(
        // Se le pasa el gestor con la mensajería de mentira para que la prueba
        // mida el disco y no el humor del canal nativo.
        gestorDePermiso: GestorDePermiso(
          mensajeria: MensajeriaFalsa(estado: AuthorizationStatus.authorized),
        ),
      );

  test('sin nada en memoria, el diagnóstico se cae a lo que quedó guardado',
      () async {
    SharedPreferences.setMockInitialValues({
      'akpush.config': jsonEncode(guardado),
      'akpush.token': tokenEntero,
      'akpush.userId': 'u_887',
    });

    final d = await diagnosticar();

    // La configuración existe aunque la fachada no la tenga: decir «no hay
    // configuración» acá haría revisar la llave y el panel, cuando lo que se
    // rompió fue Firebase.
    expect(d.configuracion.hay, isTrue);
    expect(d.configuracion.version, '7');
    expect(d.configuracion.comercio, 'mundototal');
    expect(d.token.hay, isTrue);
    expect(d.registro.userId, 'u_887');

    expect(d.eslabonRoto, Eslabon.firebase);
  });

  test('la configuración de caché se marca como tal', () async {
    // No es una falla —para eso está la caché— pero cambia el diagnóstico: si
    // el comercio cambió de cuenta de Google hoy, este teléfono no se enteró.
    SharedPreferences.setMockInitialValues({
      'akpush.config': jsonEncode(guardado),
    });

    final d = await diagnosticar();

    expect(d.configuracion.vieneDeLaCache, isTrue);
    expect(d.toJson()['configuracion'], containsPair('origen', 'cache'));
  });

  test('el token viaja como huella y nunca entero', () async {
    // Lo que se pega en un ticket queda en un chat, en un correo y en el
    // historial de una herramienta de soporte para siempre. Con el principio y
    // el fin alcanza para comparar dos teléfonos, que es lo único para lo que
    // se lo mira.
    SharedPreferences.setMockInitialValues({
      'akpush.config': jsonEncode(guardado),
      'akpush.token': tokenEntero,
    });

    final d = await diagnosticar();
    final texto = d.toString();

    expect(texto, isNot(contains(tokenEntero)));
    expect(d.token.huella, isNot(contains(tokenEntero)));
    // Principio y fin, y nada del medio: alcanza para saber si dos teléfonos
    // están hablando del mismo token.
    expect(texto, contains('cX9aQ2…8f1b'));
    expect(jsonEncode(d.toJson()), isNot(contains(tokenEntero)));
  });

  test('una configuración guardada ilegible se descarta, no rompe', () async {
    // Se descarta en silencio y se pide de nuevo. Un diagnóstico que revienta
    // leyendo un JSON roto es un diagnóstico que no existe justo el día que
    // hace falta.
    SharedPreferences.setMockInitialValues({
      'akpush.config': 'esto ya no es un JSON',
      'akpush.userId': 'u_887',
    });

    final d = await diagnosticar();

    expect(d.configuracion.hay, isFalse);
    expect(d.eslabonRoto, Eslabon.configuracion);
    // Y lo demás que sí se pudo leer sigue estando: sirve para el ticket aunque
    // no sea lo que está roto.
    expect(d.registro.userId, 'u_887');
  });
}
