import 'package:flutter/material.dart';
import 'package:hz_collection_sdk/hz_collection_sdk.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'llavero.dart';
import 'nucleo.dart';

/// EL SELECTOR DE COMERCIO — una sola aplicación para todos los comercios de prueba
///
/// Escrito el 2026-09-06, a pedido de Juan: *«tengo una sola app; ahora tengo un nuevo
/// comercio, tengo que pegarle su API key para poder recibir, tengo que pegarle su URL. No
/// quiero eso»*.
///
/// ══ QUÉ SE CAMBIA CUANDO SE CAMBIA DE COMERCIO ══
///
/// Tres cosas, y las tres tienen que moverse juntas o el resultado es peor que no cambiar:
///
/// | la llave y la dirección de Collection | a dónde reporta el aparato |
/// | la dirección del núcleo               | de dónde salen las personas |
/// | la sesión abierta                     | la persona de un comercio no existe en otro |
///
/// 🔴 **Cambiar la llave y dejar el núcleo es el error más caro**, porque no falla: se
/// ven las personas del comercio anterior, se entra con una de ellas, el registro sale
/// bien, y todo parece funcionar mientras los datos se escriben en el comercio equivocado.
///
/// ══ POR QUÉ SE GUARDA EL SLUG Y NO LA FICHA ══
///
/// Lo único que se recuerda entre arranques es **cuál** comercio estaba elegido. La llave,
/// la dirección y el núcleo se vuelven a pedir al llavero cada vez: si la llave se rotó o
/// el comercio cambió de núcleo, una copia guardada en el teléfono seguiría usando la
/// vieja y el síntoma sería un 401 sin explicación.
class ComercioActivo {
  static const _clave = 'app.comercioElegido';

  /// El comercio en uso. `null` = la aplicación está andando con la llave con la que se
  /// compiló, sin pasar por el llavero.
  static ComercioDePrueba? actual;

  static Future<String?> slugRecordado() async {
    try {
      return (await SharedPreferences.getInstance()).getString(_clave);
    } catch (_) {
      // Un almacén que no abre no puede impedir que la app arranque: se cae al comercio
      // de compilación, que es el comportamiento de siempre.
      return null;
    }
  }

  static Future<void> recordar(String slug) async {
    try {
      await (await SharedPreferences.getInstance()).setString(_clave, slug);
    } catch (_) {}
  }

  /// ══ APLICAR UN COMERCIO ══
  ///
  /// `arranqueInicial` distingue los dos casos, y la diferencia importa:
  ///
  /// · **en el arranque** el SDK todavía no está andando: se llama `init()`, y no hay
  ///   ninguna baja que dar ni token que descartar.
  /// · **cambiando en caliente** hay un comercio en uso: se llama `cambiarDeComercio()`,
  ///   que da de baja el teléfono en el anterior —si no, queda registrado en los dos y
  ///   recibe los avisos de ambos— y descarta el token, que sólo vale en el proyecto de
  ///   Firebase que lo emitió.
  static Future<void> aplicar(
    ComercioDePrueba c, {
    required bool arranqueInicial,
  }) async {
    // El núcleo se fija ANTES de arrancar el SDK: la pantalla de entrada puede pedir el
    // directorio en cuanto aparece, y con el núcleo viejo traería las personas del
    // comercio anterior.
    nucleoUrl = c.nucleoUrl;
    // La llave de consulta del núcleo es de cada núcleo. El llavero todavía no la
    // entrega —el núcleo de cada comercio la emite— así que se limpia: sin llave, la
    // pantalla de entrada pide usuario y clave, que es el camino que siempre funcionó.
    nucleoLlave = '';
    // La sesión del núcleo anterior no vale en el nuevo, y una sesión de otro sistema
    // devuelve 401 que en la pantalla se lee como «el núcleo no contesta».
    Nucleo.token = null;

    if (arranqueInicial) {
      await AkPush.init(llave: c.llave, url: c.urlBase, pedirPermisoAlIniciar: false);
    } else {
      await AkPush.cambiarDeComercio(llave: c.llave, url: c.urlBase);
    }

    actual = c;
    await recordar(c.slug);
  }
}

/// La pantalla. Se abre desde el botón de la cabecera y al arrancar, si hay llavero y
/// todavía no se eligió ninguno.
class SelectorDeComercio extends StatefulWidget {
  const SelectorDeComercio({super.key, this.puedeCancelar = true});

  /// En el arranque no se puede cancelar: sin comercio elegido no hay nada que mostrar.
  final bool puedeCancelar;

  @override
  State<SelectorDeComercio> createState() => _SelectorDeComercioState();
}

class _SelectorDeComercioState extends State<SelectorDeComercio> {
  List<ComercioDePrueba>? _comercios;
  ErrorDelLlavero? _error;
  String? _aplicando;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _comercios = null;
      _error = null;
    });
    try {
      final lista = await Llavero.comercios();
      if (!mounted) return;
      setState(() => _comercios = lista);
    } on ErrorDelLlavero catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  Future<void> _elegir(ComercioDePrueba c) async {
    setState(() => _aplicando = c.slug);
    final esElPrimero = ComercioActivo.actual == null;
    try {
      await ComercioActivo.aplicar(c, arranqueInicial: esElPrimero);
      if (!mounted) return;
      Navigator.of(context).pop(c);
    } on AkPushError catch (e) {
      if (!mounted) return;
      setState(() => _aplicando = null);
      // Se dice el código y el detalle: en esta pantalla el error casi siempre es uno de
      // dos —la llave no sirve, o el paquete no está registrado en ese comercio— y los dos
      // se arreglan en la consola, no en la app.
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${c.nombre}: ${e.message}${e.details != null ? "\n${e.details}" : ""}'),
        duration: const Duration(seconds: 8),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _aplicando = null);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${c.nombre}: $e'), duration: const Duration(seconds: 8)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Elegí el comercio'),
        automaticallyImplyLeading: widget.puedeCancelar,
        actions: [
          IconButton(
            onPressed: _cargar,
            icon: const Icon(Icons.refresh),
            tooltip: 'Volver a pedir la lista',
          ),
        ],
      ),
      body: _error != null
          ? _Problema(error: _error!, alReintentar: _cargar)
          : _comercios == null
              ? const Center(child: CircularProgressIndicator())
              : _comercios!.isEmpty
                  ? const _SinComercios()
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Text(
                          'Esta aplicación sirve para cualquiera de estos comercios. Al '
                          'cambiar, el teléfono se da de baja en el anterior y se registra '
                          'en el nuevo.',
                          style: t.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 12),
                        for (final c in _comercios!)
                          _Fila(
                            comercio: c,
                            activo: ComercioActivo.actual?.slug == c.slug,
                            aplicando: _aplicando == c.slug,
                            alElegir: () => _elegir(c),
                          ),
                      ],
                    ),
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila({
    required this.comercio,
    required this.activo,
    required this.aplicando,
    required this.alElegir,
  });

  final ComercioDePrueba comercio;
  final bool activo;
  final bool aplicando;
  final VoidCallback alElegir;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    // 🔴 Un comercio al que le falta algo NO se esconde ni se deshabilita en silencio: se
    // muestra con lo que le falta escrito. Esconderlo deja a alguien buscando en la consola
    // por qué su comercio «no aparece en la app», que es el peor lugar donde buscar.
    final usable = comercio.listo || comercio.llave.isNotEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(
          activo ? Icons.radio_button_checked : Icons.radio_button_unchecked,
          color: activo ? t.colorScheme.primary : null,
        ),
        title: Text(comercio.nombre, style: t.textTheme.titleMedium),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text('${comercio.slug} · ${comercio.paquete}', style: t.textTheme.bodySmall),
            Text('reporta a ${comercio.urlBase}', style: t.textTheme.bodySmall),
            Text(
              comercio.nucleoUrl.isEmpty
                  ? 'sin núcleo: no va a haber lista de personas'
                  : 'personas de ${comercio.nucleoUrl}',
              style: t.textTheme.bodySmall,
            ),
            for (final f in comercio.falta)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('· $f',
                    style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.error)),
              ),
          ],
        ),
        trailing: aplicando
            ? const SizedBox(
                width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : activo
                ? const Text('en uso')
                : null,
        onTap: aplicando || activo || !usable ? null : alElegir,
        isThreeLine: true,
      ),
    );
  }
}

class _Problema extends StatelessWidget {
  const _Problema({required this.error, required this.alReintentar});
  final ErrorDelLlavero error;
  final VoidCallback alReintentar;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.link_off, size: 48, color: t.colorScheme.error),
            const SizedBox(height: 12),
            Text(error.mensaje, style: t.textTheme.titleMedium, textAlign: TextAlign.center),
            if (error.detalle != null) ...[
              const SizedBox(height: 8),
              Text(error.detalle!,
                  style: t.textTheme.bodySmall, textAlign: TextAlign.center),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: alReintentar,
              icon: const Icon(Icons.refresh),
              label: const Text('Volver a intentar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SinComercios extends StatelessWidget {
  const _SinComercios();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.storefront_outlined, size: 48),
            const SizedBox(height: 12),
            Text('Ningún comercio está marcado de demostración',
                style: t.textTheme.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            // El vacío EXPLICA y dice el remedio exacto. «Sin resultados» dejaría a
            // cualquiera mirando una pantalla en blanco sin saber qué hacer.
            Text(
              'Se marcan desde Collection, uno por uno:\n\n'
              'npm run demostracion -- marcar --slug <slug> --nucleo <url>\n'
              'npm run demostracion -- llave  --slug <slug> --llave <su llave>',
              style: t.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
