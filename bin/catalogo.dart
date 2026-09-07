/// EMITE EL CATÁLOGO DE PERMISOS COMO JSON.
///
///     dart run hz_collection_sdk:catalogo > catalogo-de-permisos.json
///
/// 🔴 EXISTE PARA QUE NO HAYA DOS CATÁLOGOS. La consola necesita mostrar qué puede pedirle
/// cada comercio al teléfono y qué hace falta para que se lo aprueben; el servicio necesita
/// resolverlo contra el rubro. Copiar las fichas a TypeScript habría dejado dos listas que
/// empiezan iguales y se separan en el primer permiso que se agregue de un solo lado — y
/// una de las dos decide qué se le muestra a quien administra un comercio.
///
/// Así, el catálogo de Dart es la única fuente y el JSON es un artefacto generado. El
/// servicio lo lee; nadie lo edita a mano.
///
/// **Cuándo hay que volver a correrlo:** cada vez que se agregue o cambie una ficha. Si se
/// olvida, el servicio sirve el catálogo viejo — por eso el JSON lleva la fecha de
/// generación y el servicio la muestra.
library;

import 'dart:convert';
import 'dart:io';

import 'package:hz_collection_sdk/src/permisologia/campos.dart';
import 'package:hz_collection_sdk/src/permisologia/catalogo_de_permisos.dart';
import 'package:hz_collection_sdk/src/permisologia/transformar.dart';

String _nivel(Nivel n) => switch (n) {
      Nivel.ninguno => 'ninguno',
      Nivel.comun => 'comun',
      Nivel.asusta => 'asusta',
      Nivel.revisionManual => 'revisionManual',
    };

String _estado(Estado e) => switch (e) {
      Estado.libre => 'libre',
      Estado.condicionado => 'condicionado',
      Estado.prohibido => 'prohibido',
    };

/// FINALIDAD — para qué SISTEMA sirve el dato. Se deriva de la primera palabra del «para qué
/// sirve», que ya lo dice, así no hay una segunda lista que se separe. Tres destinos:
/// «Envío» (el motor de notificaciones), «Puntaje» (scoring/antifraude) y «Contexto» (ambos).
String _finalidad(String? paraQue) {
  if (paraQue == null || paraQue.isEmpty) return 'Contexto';
  final t = paraQue.split(':').first.split(RegExp(r'[ ,]')).first;
  const envio = {'Entregabilidad', 'Alcance', 'Señal', 'Actividad'};
  const puntaje = {'Antifraude', 'Puntaje', 'Coherencia', 'Autenticidad', 'Antigüedad', 'Riesgo'};
  if (envio.contains(t)) return 'Envío';
  if (puntaje.contains(t)) return 'Puntaje';
  return 'Contexto';
}

void main() {
  final salida = {
    'generado': DateTime.now().toUtc().toIso8601String(),
    'aviso': 'Generado por «dart run hz_collection_sdk:catalogo». No editar a mano: '
        'la fuente es lib/src/permisologia/catalogo_de_permisos.dart.',
    'puertaDeDatoSensible': sistemaAdmiteDatoSensible ? 'abierta' : 'cerrada',
    'motivoPuertaCerrada': motivoPuertaCerrada,
    'permisos': [
      for (final p in catalogoDePermisos)
        {
          'nombre': p.nombre,
          'plataforma': p.plataforma.name,
          'modulo': p.modulo,
          'paraQue': p.paraQue,
          'nivel': _nivel(p.nivel),
          'loAporta': p.loAporta,
          'esNuestro': p.esNuestro,
          'dataSafety': p.dataSafety,
          if (p.manifiestoApple != null) 'manifiestoApple': p.manifiestoApple,
          if (p.razonApple != null) 'razonApple': p.razonApple,
          'retencion': {
            'enPalabras': p.retencion.enPalabras,
            if (p.retencion.dias != null) 'dias': p.retencion.dias,
          },
          'base': p.base.name,
          'tocaDatoSensible': [for (final d in p.toca) d.name],
          'porQue': p.disponibilidad.porQue,
          // 🔴 Ya resuelto por rubro. El servicio no tiene que reimplementar la lógica de
          // `Disponibilidad.para()` — que es justo la que se habría separado.
          'porRubro': {
            for (final r in Rubro.values) r.name: _estado(p.estadoPara(r)),
          },
          'requisitos': [
            for (final q in p.requisitos) {'queHacer': q.queHacer, 'fuente': q.fuente},
          ],
        },
    ],
    // 🔴 LAS FICHAS DE CADA CAMPO, por el mismo motivo que los permisos: la consola tiene
    // que poder mostrarle a una persona QUÉ SE SABE DE ELLA, en castellano, y la única frase
    // que dice eso bien es la que escribió quien declaró el campo. Copiarlas al front habría
    // dejado noventa y cinco rótulos que se separan del código en la primera semana.
    'gruposDeSenales': [
      for (final g in gruposDeSenales)
        {'prefijo': g.prefijo, 'titulo': g.titulo, 'queRevela': g.queRevela},
    ],
    'campos': {
      for (final entrada in {
        'senales': camposDeSenales,
        'autenticidad': camposDeAutenticidad,
      }.entries)
        entrada.key: [
          for (final c in entrada.value)
            {
              'nombre': c.nombre,
              'queManda': c.queManda,
              if (c.paraQue != null) 'paraQue': c.paraQue,
              'computada': c.computada || c.como != Transformacion.taICual,
              'finalidad': _finalidad(c.paraQue),
              'como': c.como.name,
              if (c.como == Transformacion.tramo) 'tramoDe': c.tramoDe,
              if (grupoDe(c.nombre) != null) 'grupo': grupoDe(c.nombre)!.prefijo,
            },
        ],
    },
    'nuncaSePiden': [
      for (final e in permisosProhibidos.entries)
        {'nombre': e.key, 'porQue': e.value},
    ],
  };

  stdout.writeln(const JsonEncoder.withIndent('  ').convert(salida));
}
