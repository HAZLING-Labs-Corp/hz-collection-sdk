import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hz_collection_sdk/hz_collection_sdk.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// QUÉ SE RECOLECTÓ DE ESTE APARATO — a la vista de quien lo presta.
///
/// 🔴 No es una pantalla de depuración. Un colector de datos que no le deja ver a la
/// persona qué recolectó es exactamente lo que la gente desconfía, y con razón. Que esté
/// acá, en la misma aplicación y sin buscarla, es lo que hace defendible pedir el permiso.
///
/// Del lado del comercio sirve para otra cosa: es el molde de la pantalla «tus datos» que
/// va a tener que mostrar el día que alguien se la pida.
class LoRecolectado extends StatefulWidget {
  const LoRecolectado({super.key});

  @override
  State<LoRecolectado> createState() => _LoRecolectadoState();
}

class _LoRecolectadoState extends State<LoRecolectado> {
  Map<String, dynamic>? _delAparato;
  Map<String, Object?> _senales = const {};
  Diagnostico? _diag;

  @override
  void initState() {
    super.initState();
    _leer();
  }

  Future<void> _leer() async {
    final d = await DatosDelDispositivo.recolectar();
    final g = await AkPush.diagnostico();
    // Las ~95 señales de nivel 0. Es lo mismo que se le manda al servidor, ya transformado:
    // acá se muestra CRUDO lo que sale, para que la persona vea exactamente qué se recolecta.
    Map<String, Object?> sen = const {};
    try { sen = await ModuloDeSenales().medir(); } catch (_) {/* sólo Android */}
    if (mounted) setState(() { _delAparato = d.toJson(); _senales = sen; _diag = g; });
  }

  /// Los seis campos que el SDK manda duplicados en inglés y castellano. Se muestran una
  /// sola vez: ver dos veces el mismo dato con otro nombre hace dudar de todo lo demás.
  static const _duplicados = {'ancho','alto','densidad','oscuro','textoGrande','idiomas'};

  /// El nombre técnico traducido. Lo que la persona lee tiene que ser lo que entiende,
  /// no el nombre de la propiedad.
  static const _nombres = {
    'model':'Modelo', 'manufacturer':'Fabricante', 'brand':'Marca',
    'osVersion':'Versión de Android', 'apiLevel':'Nivel de Android',
    'appVersion':'Versión de la app', 'deviceId':'Identificador del aparato',
    'isPhysicalDevice':'¿Es un teléfono de verdad?', 'locale':'Idioma',
    'preferredLocales':'Idiomas preferidos', 'screenWidth':'Ancho de pantalla',
    'screenHeight':'Alto de pantalla', 'screenDensity':'Densidad de pantalla',
    'darkMode':'Modo oscuro', 'largeText':'Texto agrandado',
    'utcOffsetMinutes':'Huso horario (minutos)', 'timeZoneAbbreviation':'Zona horaria',
    'identificadorDePaquete':'Paquete de la app', 'plataforma':'Plataforma',
  };

  String _valor(dynamic v) {
    if (v == null) return '—';
    if (v is bool) return v ? 'Sí' : 'No';
    if (v is List) return v.isEmpty ? '—' : v.join(', ');
    return '$v';
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final d = _delAparato;
    if (d == null) return const Center(child: CircularProgressIndicator());

    final campos = d.entries.where((e) => !_duplicados.contains(e.key)).toList()
      ..sort((a, b) => (_nombres[a.key] ?? a.key).compareTo(_nombres[b.key] ?? b.key));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Del aparato', style: t.textTheme.titleMedium),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 12),
          child: Text(
            'Esto se lee solo, sin pedirte ningún permiso. Son ${campos.length} datos '
            'y ninguno dice quién sos.',
            style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
          ),
        ),
        Card(
          margin: EdgeInsets.zero,
          child: Column(children: [
            for (final e in campos)
              ListTile(
                dense: true,
                title: Text(_nombres[e.key] ?? e.key, style: t.textTheme.bodyMedium),
                trailing: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 190),
                  child: Text(_valor(e.value),
                      textAlign: TextAlign.end,
                      style: t.textTheme.bodyMedium
                          ?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 24),
        _Senales(medido: _senales),
        const SizedBox(height: 24),
        Text('De la sesión', style: t.textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(14),
            // El diagnóstico ya está escrito para leerse: dice qué pasa y cuál es el
            // eslabón roto, en castellano. No hace falta reescribirlo acá.
            child: SelectableText(_diag?.toString() ?? '—',
                style: t.textTheme.bodySmall?.copyWith(fontFamily: 'monospace')),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

/// DÓNDE ESTUVO ESTE TELÉFONO — con el mapa, no con una lista de números.
///
/// Muestra lo que el SDK leería AHORA. No es el historial del servidor: eso vive del otro
/// lado y esta aplicación no tiene con qué pedirlo. Sirve para lo que hace falta acá —
/// comprobar que la lectura funciona y ver con qué precisión.
class DondeEstuvo extends StatefulWidget {
  const DondeEstuvo({super.key});

  @override
  State<DondeEstuvo> createState() => _DondeEstuvoState();
}

class _DondeEstuvoState extends State<DondeEstuvo>
    with WidgetsBindingObserver {
  Position? _pos;
  String? _motivo;
  bool _buscando = false;
  WebViewController? _mapa;

  /// 🔴 EL TECHO QUE IMPIDE QUE ESTA PANTALLA SE QUEDE PEGADA.
  ///
  /// Reportado por Juan el 2026-09-05: dio el permiso, encendió el GPS, y la pantalla
  /// «se queda pegada». Cualquiera de las cuatro llamadas de abajo —el permiso, el
  /// interruptor del sistema, la última posición conocida, la lectura fresca— depende
  /// de los servicios de Google, y en un teléfono donde alguno no contesta el `await`
  /// no vuelve nunca: el spinner se queda girando sin nada que lo corte.
  ///
  /// Con esto, pase lo que pase hay una respuesta en pantalla antes de medio minuto.
  static const _techo = Duration(seconds: 25);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _mirar();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 🔴 AL VOLVER DE LOS AJUSTES SE VUELVE A MIRAR.
  ///
  /// La otra mitad de lo que reportó Juan: dar el permiso o encender el GPS pasa
  /// FUERA de la aplicación, y al volver esta pantalla seguía mostrando el estado
  /// de antes —«sin permiso», o el mapa vacío— como si nada hubiera cambiado. Quien
  /// acaba de encender la ubicación y ve lo mismo concluye que no sirvió.
  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    if (estado == AppLifecycleState.resumed && !_buscando && _pos == null) {
      _mirar();
    }
  }

  /// Arma el mapa alrededor de un punto. Extraído para poder pintarlo con la última
  /// posición conocida al instante y volver a pintarlo con la fresca cuando llegue.
  void _pintar(Position p) {
    final c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse(
        // Un recuadro alrededor del punto: al zoom fijo, una posición aproximada se ve como
        // si fuera exacta, y eso es afirmar de más.
        'https://www.openstreetmap.org/export/embed.html'
        '?bbox=${p.longitude - 0.02},${p.latitude - 0.02},'
        '${p.longitude + 0.02},${p.latitude + 0.02}'
        '&layer=mapnik&marker=${p.latitude},${p.longitude}'));
    if (mounted) setState(() { _pos = p; _mapa = c; _buscando = false; });
  }

  Future<void> _mirar() async {
    setState(() { _buscando = true; _motivo = null; });
    try {
      await _buscar().timeout(_techo);
    } on TimeoutException {
      /* Si la última posición conocida ya pintó el mapa, el techo no es un fallo que
         haya que contar: lo que venció fue la lectura fresca, y lo que se ve sirve. */
      if (mounted && _pos == null) {
        setState(() {
          _buscando = false;
          _motivo = 'el teléfono no contestó en ${_techo.inSeconds} segundos. '
              'Suele pasar bajo techo o con los servicios de ubicación recién '
              'encendidos: probá de nuevo cerca de una ventana.';
        });
      }
    } catch (e) {
      if (mounted) setState(() { _motivo = 'falló: $e'; _buscando = false; });
    }
  }

  /// El trabajo de verdad. Va aparte para poder ponerle un techo entero arriba: si se
  /// le pusiera un timeout a cada llamada por separado, tres que tarden poco menos que
  /// su límite igual suman más de lo que nadie espera mirando un spinner.
  Future<void> _buscar() async {
      if (!await AkPush.tieneUbicacion) {
        setState(() { _motivo = 'sin permiso'; _buscando = false; });
        return;
      }
      if (!await Geolocator.isLocationServiceEnabled()) {
        setState(() { _motivo = 'el teléfono tiene la ubicación apagada'; _buscando = false; });
        return;
      }
      // 🔴 LA ÚLTIMA POSICIÓN CONOCIDA PRIMERO. Es instantánea —el sistema ya la tiene—
      // y alcanza para dibujar la zona en el acto. Antes se esperaba un fix nuevo con dos
      // timeouts de 12 segundos encadenados, y en un teléfono adentro de un edificio eso son
      // 24 segundos de spinner con el mapa sin abrir nunca. Medido en el teléfono de Juan el
      // 2026-09-01: el permiso estaba dado y la ubicación prendida, y el mapa igual no salía.
      final ultima = await Geolocator.getLastKnownPosition();
      if (ultima != null) _pintar(ultima);

      // Y recién ahí, una lectura fresca con UN solo intento corto. Si no llega a tiempo, se
      // queda la última conocida, que para «tu zona» es más que suficiente.
      Position? p = ultima;
      try {
        p = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 8)));
      } catch (_) {/* se queda la última conocida */}

      if (p == null) {
        setState(() { _motivo = 'el sistema no devolvió ninguna posición'; _buscando = false; });
        return;
      }
      _pintar(p);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    if (_buscando) return const Center(child: CircularProgressIndicator());

    if (_pos == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.location_off_outlined, size: 40, color: t.colorScheme.outline),
            const SizedBox(height: 12),
            Text('Sin ubicación', style: t.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(_motivo ?? 'todavía no se pudo leer',
                textAlign: TextAlign.center,
                style: t.textTheme.bodyMedium
                    ?.copyWith(color: t.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () async {
                // 🔴 Directo al permiso del sistema, SIN volver a mostrar el modal blando.
                // Ese modal ya salió al iniciar sesión; repetirlo acá es el «pide como cinco
                // permisos» que se sintió confuso. El botón que la persona ya tocó ES la
                // intención — no hace falta preguntarle otra vez si quiere.
                if (_motivo == 'sin permiso') await AkPush.pedirPermiso();
                await _mirar();
              },
              icon: const Icon(Icons.refresh),
              label: Text(_motivo == 'sin permiso' ? 'Dar permiso' : 'Probar de nuevo'),
            ),
          ]),
        ),
      );
    }

    final p = _pos!;
    return Column(children: [
      Expanded(child: _mapa == null
          ? const SizedBox()
          : WebViewWidget(controller: _mapa!)),
      Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Tu zona', style: t.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            '${p.latitude.toStringAsFixed(4)}, ${p.longitude.toStringAsFixed(4)}  ·  '
            'con un margen de ${p.accuracy.round()} metros',
            style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Text(
            'Es la zona, no la dirección: se pide precisión baja a propósito.',
            style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline),
          ),
          const SizedBox(height: 12),
          Row(children: [
            OutlinedButton.icon(
              onPressed: _mirar,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Volver a leer'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: () async {
                final fue = await AkPush.reportarUbicacion(forzar: true);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(fue ? 'Se mandó al servidor' : 'No se pudo mandar'),
                ));
              },
              icon: const Icon(Icons.cloud_upload_outlined, size: 18),
              label: const Text('Mandar ahora'),
            ),
          ]),
        ]),
      ),
    ]);
  }
}


/// LAS 95 SEÑALES, AGRUPADAS, CON PARA QUÉ SIRVE CADA UNA.
///
/// 🔴 Es la misma información que ve el comercio en la consola, con las mismas frases —salen
/// de las fichas del SDK, no se escriben acá—. Que la persona pueda leer, en la propia app,
/// qué se recolecta de ella y PARA QUÉ, es lo que hace defendible pedirlo. Lo pidió Juan el
/// 2026-09-01: no alcanza con listar los datos, hay que decir para qué sirven.
class _Senales extends StatelessWidget {
  const _Senales({required this.medido});
  final Map<String, Object?> medido;

  String _valor(Object? v) {
    if (v == null) return '—';
    if (v is bool) return v ? 'Sí' : 'No';
    return '$v';
  }

  static final _ficha = {for (final c in camposDeSenales) c.nombre: c};

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final claves = medido.keys.toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Señales del teléfono', style: t.textTheme.titleMedium),
      Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 12),
        child: Text(
          claves.isEmpty
              ? 'Se leen sin pedirte ningún permiso. En este teléfono todavía no se midieron.'
              : 'Se leen sin pedirte ningún permiso: son ${claves.length} señales y ninguna dice '
                'quién sos. Dicen cómo está armado y configurado el aparato — y para qué sirve cada una.',
          style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
        ),
      ),
      for (final g in gruposDeSenales)
        if (claves.any((k) => k.startsWith(g.prefijo)))
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ExpansionTile(
              initiallyExpanded: g == gruposDeSenales.first,
              title: Text(g.titulo, style: t.textTheme.titleSmall),
              subtitle: Text(g.queRevela, style: t.textTheme.bodySmall),
              childrenPadding: const EdgeInsets.only(bottom: 8),
              children: [
                for (final k in claves.where((k) => k.startsWith(g.prefijo)))
                  ListTile(
                    dense: true,
                    title: Text(_ficha[k]?.queManda ?? k, style: t.textTheme.bodyMedium),
                    // 🔴 PARA QUÉ SIRVE, bajo el qué manda. Es lo que Juan pidió ver en la app.
                    subtitle: _ficha[k]?.paraQue == null
                        ? null
                        : Text(_ficha[k]!.paraQue!,
                            style: t.textTheme.bodySmall
                                ?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                    trailing: Text(_valor(medido[k]),
                        style: t.textTheme.bodyMedium
                            ?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                  ),
              ],
            ),
          ),
    ]);
  }
}
