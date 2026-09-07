// Pruebas de la traducción entre lo que devuelve el núcleo y lo que el SDK
// espera. Es donde se rompe primero una integración: un campo que cambia de
// nombre del otro lado no da error de compilación, da un dato vacío en la ficha.
//
// (Este archivo tenía la plantilla de `flutter create`, que importaba una clase
// `MyApp` que nunca existió en esta app —se llama `DemoApp`— y por eso no
// compilaba desde el primer día.)

import 'package:flutter_test/flutter_test.dart';
import 'package:hz_collection_sdk/hz_collection_sdk.dart';

import 'package:hz_collection_app/nucleo.dart';

void main() {
  test('una persona natural del núcleo se traduce al modelo del SDK', () {
    final p = PersonaDelNucleo.desdeJson(const {
      'uuid': '6693ea988b7b3a506c2aa58e',
      'cedula': '13245607',
      'nombre': 'Iván Quintero García',
      'usuario': 'usuario1',
      'telefono': '+584125550001',
      'email': 'ivan.quintero@ejemplo.mundototal.test',
      'pais': 'Venezuela',
      'estado': 'Miranda',
      'ciudad': 'Santa Teresa del Tuy',
      'genero': 'Masculino',
      'tipoDeSujeto': 'natural',
      'claseDeDocumento': 'cedula',
      'organizacion': null,
    });

    // El identificador principal es el uuid, no la cédula.
    expect(p.uuid, '6693ea988b7b3a506c2aa58e');
    expect(p.tipo, TipoDeSujeto.natural);
    expect(p.organizacion, isNull);

    // El SDK pide la CLASE del documento, no sólo el número.
    expect(p.documento.clase, ClaseDeDocumento.cedula);
    expect(p.documento.numero, '13245607');

    // El núcleo lo llama `email`; el SDK, `correo`.
    expect(p.correo, 'ivan.quintero@ejemplo.mundototal.test');
  });

  test('una empresa llega con RIF, no con cédula', () {
    final p = PersonaDelNucleo.desdeJson(const {
      'uuid': '5e3eb78d97c714b829473f9e',
      'cedula': 'J-304521679',
      'nombre': 'Distribuidora Los Médanos, C.A.',
      'usuario': 'empresa1',
      'tipoDeSujeto': 'juridica',
      'claseDeDocumento': 'rif',
      'organizacion': null,
    });

    expect(p.tipo, TipoDeSujeto.juridica);
    expect(p.documento.clase, ClaseDeDocumento.rif);
    // Se guarda tal cual, con el guion: sacárselo sería inventarle al comercio
    // un número que no es el que tiene anotado.
    expect(p.documento.numero, 'J-304521679');
  });

  test('un empleado de proveedor conserva su organización, con un código derivado', () {
    final p = PersonaDelNucleo.desdeJson(const {
      'uuid': 'd800be959c6b52140e91f340',
      'cedula': '19988341',
      'nombre': 'Julio Giménez',
      'usuario': 'empleado1',
      'tipoDeSujeto': 'natural',
      'claseDeDocumento': 'cedula',
      'organizacion': 'Logística Sur, C.A.',
    });

    expect(p.organizacion, isNotNull);
    expect(p.organizacion!.nombre, 'Logística Sur, C.A.');
    // El núcleo guarda el nombre; el SDK pide además un código. Se deriva, para
    // no inventar uno que no existe en ningún lado.
    expect(p.organizacion!.codigo, 'log-stica-sur-c-a');
    // Sigue siendo una persona natural: pertenecer a una organización no la
    // convierte en la organización.
    expect(p.tipo, TipoDeSujeto.natural);
  });

  test('los campos que el núcleo no manda no rompen la traducción', () {
    final p = PersonaDelNucleo.desdeJson(const {'uuid': 'x', 'nombre': 'Sin más'});
    expect(p.cedula, '');
    expect(p.telefono, '');
    expect(p.tipo, TipoDeSujeto.natural);
    expect(p.claseDeDocumento, ClaseDeDocumento.cedula);
    expect(p.organizacion, isNull);
  });
}
