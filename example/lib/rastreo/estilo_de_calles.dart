/// EL ESTILO DE CALLES — el mismo de la consola web (`src/lib/flota/estilo-de-calles.ts`): sólo
/// calles, en gris, bien definidas, con su nombre; sin edificios ni comercios. Vectorial, de los
/// mosaicos de OpenFreeMap (sin llave). Cambiar de proveedor es cambiar este archivo.
library;

import 'dart:convert';
import 'dart:io';

const _fondo = '#f1f1ef';
const _agua = '#dfe3e6';
const _borde = '#c9ccd0';
const _via = '#ffffff';
const _texto = '#6d7278';

dynamic _ancho(double z12, double z16, double z19) => [
      'interpolate', ['exponential', 1.6], ['zoom'], 11, z12 * 0.35, 12, z12, 16, z16, 19, z19,
    ];

List<Map<String, dynamic>> _vias(String id, List<String> clases, List<double> borde, List<double> via, int minzoom) {
  final filtro = [
    'all',
    ['in', ['get', 'class'], ['literal', clases]],
    ['!=', ['get', 'brunnel'], 'tunnel'],
  ];
  Map<String, dynamic> capa(String sufijo, String color, List<double> a) => {
        'id': '$id-$sufijo',
        'type': 'line',
        'source': 'calles',
        'source-layer': 'transportation',
        'minzoom': minzoom,
        'filter': filtro,
        'layout': {'line-cap': 'round', 'line-join': 'round'},
        'paint': {'line-color': color, 'line-width': _ancho(a[0], a[1], a[2])},
      };
  return [capa('borde', _borde, borde), capa('via', _via, via)];
}

Map<String, dynamic> estiloDeCalles() => {
      'version': 8,
      'glyphs': 'https://tiles.openfreemap.org/fonts/{fontstack}/{range}.pbf',
      'sources': {
        'calles': {'type': 'vector', 'url': 'https://tiles.openfreemap.org/planet'},
      },
      'layers': [
        {'id': 'base-fondo', 'type': 'background', 'paint': {'background-color': _fondo}},
        {'id': 'agua', 'type': 'fill', 'source': 'calles', 'source-layer': 'water', 'paint': {'fill-color': _agua}},
        ..._vias('via-menor', ['tertiary', 'minor', 'service', 'residential', 'unclassified', 'living_street'], [3.4, 11, 26], [2.4, 9.4, 23], 13),
        ..._vias('via-media', ['primary', 'secondary'], [5, 15, 34], [3.8, 13, 31], 11),
        ..._vias('via-mayor', ['motorway', 'trunk'], [6.5, 18, 38], [5, 16, 35], 8),
        {
          'id': 'rotulo-calle',
          'type': 'symbol',
          'source': 'calles',
          'source-layer': 'transportation_name',
          'minzoom': 14.5,
          'layout': {
            'symbol-placement': 'line',
            'text-field': ['coalesce', ['get', 'name:es'], ['get', 'name']],
            'text-font': ['Noto Sans Regular'],
            'text-size': ['interpolate', ['linear'], ['zoom'], 14.5, 10, 18, 13],
            'text-max-angle': 30,
          },
          'paint': {'text-color': _texto, 'text-halo-color': '#ffffff', 'text-halo-width': 1.6},
        },
        {
          'id': 'rotulo-zona',
          'type': 'symbol',
          'source': 'calles',
          'source-layer': 'place',
          'minzoom': 11,
          'maxzoom': 17,
          'filter': ['in', ['get', 'class'], ['literal', ['suburb', 'neighbourhood', 'quarter', 'city', 'town']]],
          'layout': {
            'text-field': ['coalesce', ['get', 'name:es'], ['get', 'name']],
            'text-font': ['Noto Sans Regular'],
            'text-size': ['interpolate', ['linear'], ['zoom'], 11, 9, 16, 12],
            'text-transform': 'uppercase',
            'text-letter-spacing': 0.1,
            'text-max-width': 6,
          },
          'paint': {'text-color': '#a7abb0', 'text-halo-color': _fondo, 'text-halo-width': 1.2},
        },
      ],
    };

/// MapLibre nativo sólo lee el estilo por dirección: se escribe a un archivo y se pasa `file://`.
Future<String> archivoDelEstilo() async {
  final f = File('${Directory.systemTemp.path}/estilo_de_calles.json');
  await f.writeAsString(jsonEncode(estiloDeCalles()));
  return 'file://${f.path}';
}
