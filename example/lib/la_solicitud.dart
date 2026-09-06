import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hz_collection_sdk/hz_collection_sdk.dart';

/// LA SOLICITUD — el formulario que el SDK mira, y el panel de lo que midió.
///
/// 🔴 No es una pantalla de adorno de la demo: es **la única forma de probar en la pantalla
/// lo que la pantalla hace**. El tiempo de llenado, el abandono y el «pegó o escribió» sólo
/// existen si hay dedos sobre un formulario; probar eso por API sería inventar el evento en
/// vez de medirlo.
///
/// Y del lado del comercio es el molde: **son cinco líneas** las que hay que escribir para
/// que un formulario quede medido, y están todas acá abajo señaladas con `① … ⑤`.
///
/// ══ 🔴 LO QUE ESTA PANTALLA DEMUESTRA QUE NO PASA ══
///
/// El panel de abajo muestra, evento por evento, **todo** lo que el SDK guardó. Si alguna
/// vez apareciera ahí un pedazo de la cédula que se acaba de escribir, el límite estaría
/// roto y se vería a simple vista. Que la persona pueda mirar exactamente qué se llevaron
/// es lo que hace defendible llevárselo.
class LaSolicitud extends StatefulWidget {
  const LaSolicitud({super.key});

  @override
  State<LaSolicitud> createState() => _LaSolicitudState();
}

class _LaSolicitudState extends State<LaSolicitud> {
  /// ① Se declara el formulario. El nombre es un rótulo de la aplicación.
  final ObservadorDeFormulario _f = AkPush.formulario('solicitud');

  EstadoDelComportamiento? _estado;
  bool _enviada = false;

  @override
  void initState() {
    super.initState();
    /// ② Se avisa que la persona entró. Acá arranca el reloj del tiempo de llenado.
    _f.abrir();
    _refrescar();
  }

  @override
  void dispose() {
    /// ⑤ Y al irse de la pantalla se suelta. Si no se envió, esto es un abandono — que es
    /// como se abandona un formulario de verdad: yéndose.
    _f.dispose();
    super.dispose();
  }

  Future<void> _refrescar() async {
    final e = await AkPush.estadoDelComportamiento();
    if (mounted) setState(() => _estado = e);
  }

  Future<void> _enviar() async {
    /// ④ Y que lo envió. `ms` sale de acá: es el tiempo que tardó en llenarlo.
    await _f.enviar();
    setState(() => _enviada = true);
    await _refrescar();
  }

  /// El botón «pegar» que tiene cualquier aplicación de crédito al lado de la cédula.
  ///
  /// No es un truco para la demo: trae el texto del portapapeles y lo deja en el campo de
  /// un solo golpe, que es exactamente lo que hace el «Pegar» del menú largo de Android. El
  /// SDK lo ve igual en los dos casos, porque lo único que mira es que el largo saltó.
  Future<void> _pegar(ObservadorDeCampo campo) async {
    final porta = await Clipboard.getData(Clipboard.kTextPlain);
    final texto = porta?.text ?? '';
    if (texto.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('El portapapeles está vacío — copiá algo primero')));
      }
      return;
    }
    campo.controlador.text = texto;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Solicitud de crédito', style: t.textTheme.titleMedium),
                Text(
                  'Se mide cuánto tardás, si pegás o escribís cada dato y cuántas veces lo '
                  'corregís. Nunca se guarda QUÉ escribiste.',
                  style: t.textTheme.bodySmall,
                ),
                const SizedBox(height: 16),

                /// ③ Cada campo recibe el controlador y el foco que ya vienen observados.
                ///    Es una línea por campo, y la aplicación los usa como cualquier otro.
                _Campo(
                  campo: _f.campo('cedula'),
                  rotulo: 'Cédula',
                  teclado: TextInputType.number,
                  alPegar: () => _pegar(_f.campo('cedula')),
                ),
                _Campo(
                  campo: _f.campo('telefono'),
                  rotulo: 'Teléfono',
                  teclado: TextInputType.phone,
                  alPegar: () => _pegar(_f.campo('telefono')),
                ),
                _Campo(
                  campo: _f.campo('monto'),
                  rotulo: 'Monto que pedís',
                  teclado: TextInputType.number,
                ),
                _Campo(
                  campo: _f.campo('motivo'),
                  rotulo: 'Para qué lo pedís',
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _enviada ? null : _enviar,
                      icon: const Icon(Icons.send),
                      label: Text(_enviada ? 'Enviada' : 'Enviar solicitud'),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _PanelDeLaPolitica(estado: _estado, alRefrescar: _refrescar),
      ],
    );
  }
}

class _Campo extends StatelessWidget {
  const _Campo({
    required this.campo,
    required this.rotulo,
    this.teclado,
    this.alPegar,
  });

  final ObservadorDeCampo campo;
  final String rotulo;
  final TextInputType? teclado;
  final VoidCallback? alPegar;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: TextField(
          controller: campo.controlador,
          focusNode: campo.foco,
          keyboardType: teclado,
          decoration: InputDecoration(
            labelText: rotulo,
            border: const OutlineInputBorder(),
            isDense: true,
            suffixIcon: alPegar == null
                ? null
                : IconButton(
                    tooltip: 'Pegar del portapapeles',
                    icon: const Icon(Icons.content_paste),
                    onPressed: alPegar,
                  ),
          ),
        ),
      );
}

/// LO QUE LA POLÍTICA DECIDIÓ, A LA VISTA.
///
/// Muestra las dos mitades: cuántos eventos de comportamiento hay esperando la próxima
/// apertura, y qué contestó el portero por cada módulo de señales. «No se transmitió: nada
/// cambió» es una respuesta correcta y tiene que poder leerse como tal — sin esta pantalla
/// se ve igual que no haber medido, que es el error que ya costó una tarde.
class _PanelDeLaPolitica extends StatelessWidget {
  const _PanelDeLaPolitica({required this.estado, required this.alRefrescar});

  final EstadoDelComportamiento? estado;
  final Future<void> Function() alRefrescar;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final e = estado;
    final p = AkPush.politicaDeTransmision;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: Text('La política de transmisión', style: t.textTheme.titleMedium)),
              IconButton(
                onPressed: alRefrescar,
                icon: const Icon(Icons.refresh),
                tooltip: 'Volver a mirar',
              ),
            ]),
            const SizedBox(height: 4),
            _Linea('Se mide', 'al abrir la aplicación'),
            _Linea('Se transmite', 'por lote, al abrir — nunca al medir'),
            _Linea('Dispara un envío', 'sólo un cambio real '
                '(${senalesDeMomento.length} señales de momento no cuentan)'),
            _Linea('Sin conexión', 'hasta ${p.topeDeEventos} eventos o '
                '${(p.topeDeBytes / 1024).round()} KB · se descarta el más viejo'),
            _Linea('Resincroniza', 'todo igual cada ${p.resincronizarCadaDias} días'),
            const Divider(height: 24),
            if (e == null)
              const Text('mirando…')
            else ...[
              Text('Eventos guardados esperando la próxima apertura: ${e.encolados}',
                  style: t.textTheme.bodyMedium),
              if (e.descartadosSinAvisar > 0)
                Text('Se descartaron ${e.descartadosSinAvisar} por desborde — viajan '
                    'contados en el próximo SESION_ABRE',
                    style: t.textTheme.bodySmall
                        ?.copyWith(color: Colors.orange.shade900)),
              if (e.ultimoEnvio != null)
                Text('Último lote: ${e.salieronLaUltimaVez} eventos a las '
                    '${TimeOfDay.fromDateTime(e.ultimoEnvio!).format(context)}',
                    style: t.textTheme.bodySmall),
              if (e.ultimoMotivo != null)
                Text(e.ultimoMotivo!,
                    style: t.textTheme.bodySmall
                        ?.copyWith(color: Colors.red.shade800)),
            ],
            const SizedBox(height: 12),
            Text('Qué decidió por cada módulo de señales', style: t.textTheme.labelMedium),
            if (AkPush.ultimasDecisiones.isEmpty)
              Text('todavía no midió ninguno — entrá con una persona',
                  style: t.textTheme.bodySmall)
            else
              for (final d in AkPush.ultimasDecisiones.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(d.value.mandar ? Icons.cloud_upload : Icons.cloud_off,
                        size: 16,
                        color: d.value.mandar
                            ? Colors.blue.shade700
                            : Colors.green.shade700),
                    const SizedBox(width: 6),
                    Expanded(
                        child: Text('${d.key}: ${d.value.porQue}',
                            style: t.textTheme.bodySmall)),
                  ]),
                ),
            const SizedBox(height: 12),
            // 🔴 EL BOTÓN ES LA EXCEPCIÓN, NO EL CAMINO. La política es que el lote sale al
            // abrir, y el SDK ya lo hace solo. Está acá para poder VER el envío sin cerrar
            // y volver a abrir la aplicación — y para el caso real en que el comercio
            // necesita el dato en el momento, con un analista esperando del otro lado.
            OutlinedButton.icon(
              onPressed: () async {
                final n = await AkPush.transmitirComportamiento();
                await alRefrescar();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(n == 0
                          ? 'No había nada que mandar'
                          : 'Salieron $n eventos en un solo lote')));
                }
              },
              icon: const Icon(Icons.bolt),
              label: const Text('Enviar ahora (la excepción)'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Linea extends StatelessWidget {
  const _Linea(this.que, this.como);
  final String que;
  final String como;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 130,
            child: Text(que,
                style: Theme.of(context).textTheme.labelMedium),
          ),
          Expanded(
              child: Text(como, style: Theme.of(context).textTheme.bodySmall)),
        ]),
      );
}
