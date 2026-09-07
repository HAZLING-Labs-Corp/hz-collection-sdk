import 'package:flutter/material.dart';

import 'politica.dart';

/// EL MODAL QUE PREGUNTA POR LA UBICACIÓN — LO DIBUJA EL SDK
///
/// ══ POR QUÉ VIVE ACÁ Y NO EN CADA APLICACIÓN ══
///
/// Porque si vive en la aplicación, cada comercio que instala el SDK tiene que
/// escribir esta pantalla, y no la va a escribir: va a llamar directo a
/// `pedirUbicacion()`, el sistema va a mostrar su diálogo seco —«¿Permitir que
/// la app acceda a la ubicación?»— sin ninguna explicación previa, y la mayoría
/// va a decir que no.
///
/// 🔴 Y en Android eso no tiene vuelta atrás: dos negativas y el sistema deja de
/// mostrar el diálogo para siempre. No hay segunda oportunidad de explicarse. La
/// única pantalla que decide si esa persona comparte su zona es ésta, así que la
/// pone el SDK y viene bien hecha de fábrica.
///
/// Decisión de Juan, 2026-08-31: *«esto es un SDK... no voy a obligar al usuario
/// a poner un botón. Tiene que ser como notificaciones: que le levanten una
/// opción que le pregunte, ¿deseas darme acceso a tu ubicación?»*
///
/// ══ LOS TEXTOS LOS PONE EL COMERCIO, DESDE LA CONSOLA ══
///
/// No van compilados. Si se ve que nadie acepta, el texto se corrige en la
/// consola y la próxima persona que abre la aplicación ya ve el nuevo — sin
/// publicar una versión en la tienda, que tarda días y que además no actualiza a
/// quien no actualiza.
///
/// Si el comercio no escribió nada, se usan estos textos, que están redactados
/// para que se entienda qué se pide y qué NO se pide.
class ModalDeUbicacion extends StatelessWidget {
  const ModalDeUbicacion({
    super.key,
    required this.textos,
    this.marca,
    this.esSiempre = false,
  });

  final TextosDeUbicacion textos;

  /// Si esta hoja es la SEGUNDA pregunta —la de «siempre»— y no la primera.
  ///
  /// 🔴 Cambia el ícono y agrega el renglón que dice a dónde va el botón. Es la diferencia
  /// que evita el peor final de este flujo: la persona acepta, el sistema la deposita en una
  /// pantalla de Ajustes que no pidió, no entiende qué fue a buscar y se vuelve. El permiso
  /// queda igual que antes y nadie se entera de por qué.
  final bool esSiempre;

  /// El color del comercio, si lo declaró. Sin esto el modal sale con el color
  /// del tema de la aplicación, que ya suele ser el correcto.
  final Color? marca;

  /// Lo levanta y devuelve si la persona dijo que sí.
  ///
  /// Es una hoja de abajo y no un `AlertDialog` a propósito: el diálogo cuadrado
  /// del sistema es el mismo que usan los avisos de error, y se descarta con el
  /// mismo reflejo. Una hoja que sube ocupa la mitad de la pantalla, deja lugar
  /// para explicar, y no se parece a nada que la persona quiera sacarse de encima.
  static Future<bool> mostrar(
    BuildContext context, {
    required TextosDeUbicacion textos,
    Color? marca,
  }) async {
    final r = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      // Se puede cerrar deslizando: encerrar a alguien en una pantalla de permiso
      // es la forma más rápida de que desinstale la aplicación. Cerrar cuenta como
      // «ahora no», y se le vuelve a ofrecer cuando la política lo diga.
      isDismissible: true,
      backgroundColor: Colors.transparent,
      builder: (c) => ModalDeUbicacion(textos: textos, marca: marca),
    );
    return r == true;
  }

  /// LA SEGUNDA PREGUNTA: «SIEMPRE», QUE NO ES LA MISMA QUE «MIENTRAS USÁS LA APLICACIÓN».
  ///
  /// ══ 🔴 POR QUÉ ES OTRA HOJA Y NO LA MISMA CON OTRO TEXTO ══
  ///
  /// Porque Android las trata como dos permisos distintos y **prohíbe pedirlos juntos**:
  /// desde Android 11 el diálogo de «permitir siempre» ni se muestra — el sistema abre la
  /// pantalla de Ajustes de la aplicación y la persona tiene que elegir «Permitir siempre»
  /// ahí, a mano, entre otras opciones. iOS 13+ hace lo mismo.
  ///
  /// Reusar la hoja de la zona para esto tiene dos finales malos y ninguno bueno: le pide
  /// que acepte de nuevo algo que ya aceptó, y la deja parada en una pantalla de Ajustes sin
  /// saber qué fue a buscar. Por eso esta hoja dice explícitamente a dónde la manda el botón.
  ///
  /// Se llama **después** de que la de la zona quedó concedida. Antes no sirve de nada: sin
  /// el permiso de uso, el sistema no ofrece el de siempre.
  static Future<bool> mostrarSiempre(
    BuildContext context, {
    required TextosDeSiempre textos,
    Color? marca,
  }) async {
    final r = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      backgroundColor: Colors.transparent,
      builder: (c) => ModalDeUbicacion(
        esSiempre: true,
        marca: marca,
        textos: TextosDeUbicacion(
          titulo: textos.titulo,
          cuerpo: textos.cuerpo,
          aceptar: textos.aceptar,
          ahoraNo: textos.ahoraNo,
          motivos: textos.motivos,
        ),
      ),
    );
    return r == true;
  }

  /// EL OTRO CASO: EL PERMISO ESTÁ, PERO EL TELÉFONO TIENE LA UBICACIÓN APAGADA.
  ///
  /// Pantalla aparte y texto aparte, porque el problema es otro y el botón lleva a otro
  /// lado —a los ajustes de ubicación del teléfono, no a los permisos de la aplicación,
  /// que en este caso ya están bien. Reusar el modal de arriba haría que la persona
  /// vuelva a aceptar algo que ya aceptó y siga sin funcionar.
  static Future<bool> mostrarServicioApagado(BuildContext context) async {
    final tema = Theme.of(context);
    final r = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (c) => SafeArea(
        child: Container(
          decoration: BoxDecoration(
            color: tema.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    color: tema.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: tema.colorScheme.tertiary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.location_off_outlined,
                    size: 28, color: tema.colorScheme.tertiary),
              ),
              const SizedBox(height: 20),
              Text('Falta un paso',
                  style: tema.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              Text(
                'Ya nos diste permiso, gracias. Pero este teléfono tiene la ubicación '
                'apagada, así que todavía no podemos saber en qué zona estás. Se prende '
                'desde los ajustes del teléfono.',
                style: tema.textTheme.bodyMedium?.copyWith(
                  color: tema.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Prender la ubicación'),
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                style: TextButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  foregroundColor: tema.colorScheme.onSurfaceVariant,
                ),
                child: const Text('Ahora no'),
              ),
            ],
          ),
        ),
      ),
    );
    return r == true;
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final color = marca ?? tema.colorScheme.primary;

    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: tema.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  color: tema.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              // Otro ícono para la segunda pregunta: dos hojas idénticas seguidas se leen
              // como un error de la aplicación —«¿no le dije que sí ya?»— y la segunda se
              // descarta sin leer.
              child: Icon(
                esSiempre ? Icons.update_outlined : Icons.place_outlined,
                size: 28,
                color: color,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              textos.titulo,
              style: tema.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              textos.cuerpo,
              style: tema.textTheme.bodyMedium?.copyWith(
                color: tema.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            // 🔴 Lo que la persona de verdad quiere saber antes de decir que sí, y que
            // casi ninguna aplicación se toma el trabajo de decir: qué tan preciso es,
            // cuándo se lee, y si se puede deshacer. Las tres respuestas son buenas en
            // este SDK —zona, sólo con la app abierta, revocable— así que decirlas
            // ayuda, y además son ciertas: no se pide precisión alta ni segundo plano.
            ...textos.motivos.map(
              (m) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check_circle_outline, size: 18, color: color),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(m, style: tema.textTheme.bodyMedium),
                    ),
                  ],
                ),
              ),
            ),
            // 🔴 A DÓNDE LLEVA EL BOTÓN, DICHO ANTES DE TOCARLO. El sistema no muestra un
            // diálogo para «siempre»: abre los Ajustes. Quien no lo sabe se vuelve sin tocar
            // nada, y desde afuera eso se ve idéntico a un «no».
            if (esSiempre) ...[
              Text(
                'Al tocar el botón se abren los ajustes del teléfono. Ahí elegí '
                '«Permitir siempre».',
                style: tema.textTheme.bodySmall?.copyWith(
                  color: tema.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
            ],
            const SizedBox(height: 6),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                backgroundColor: color,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(textos.aceptar),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              style: TextButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                foregroundColor: tema.colorScheme.onSurfaceVariant,
              ),
              child: Text(textos.ahoraNo),
            ),
          ],
        ),
      ),
    );
  }
}
