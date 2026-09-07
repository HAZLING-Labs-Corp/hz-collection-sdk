/// LA CAPA DE TRANSFORMACIÓN — cómo se recolecta sin leer contenido.
///
/// 🔴 ESTO SE ADOPTA ANTES DE RECOLECTAR NADA NUEVO, y ésa es toda la urgencia de este
/// archivo. Es una regla de arquitectura de diez líneas que, tomada hoy, no cuesta nada;
/// tomada dentro de seis meses obliga a revisar cada campo que ya se está mandando y a
/// discutir uno por uno si se puede cambiar. Las reglas de este tipo se imponen al principio
/// o no se imponen.
///
/// **De dónde sale.** De la minimización de datos, que es un principio escrito en la ley —
/// artículo 5.1.c del RGPD, y su equivalente en la LOPDP ecuatoriana y en la LGPD brasileña:
/// sólo se trata el dato **adecuado, pertinente y limitado** a lo necesario. No es de nadie
/// en particular y no hay nada que inventar; la técnica es ésta: cada campo de texto libre
/// pasa por una función antes de entrar al paquete que se sube. Nunca queda como texto.
///
///     display_name  «María Fernanda Solís»  →  3 palabras · 20 caracteres
///     contact_status                        →  0 / 1
///     el número de teléfono                 →  un identificador opaco
///
/// Es la práctica corriente del sector —todo colector serio la aplica— y está implementada
/// acá desde cero, en veinte líneas de Dart que se leen abajo enteras.
///
/// **Qué NO resuelve, para no venderlo de más:** esto reduce lo que se puede reconstruir de
/// una persona a partir de un campo suelto. No la vuelve anónima. Un conjunto de conteos
/// suficientemente grande sigue siendo una huella, y quien lo diga de otra forma está
/// exagerando.
library;

/// Cómo se convierte un valor antes de que salga del teléfono.
///
/// El nombre de cada una dice qué queda, no qué se descarta: es lo que hay que poder
/// contestar cuando alguien pregunta «¿y esto qué manda exactamente?».
enum Transformacion {
  /// Sale tal cual. **Sólo para valores que no vienen de una persona**: el modelo del
  /// teléfono, la versión del sistema, si es un emulador. Un campo que alguien escribió no
  /// puede usar esto.
  taICual,

  /// Queda `1` si hay algo, `0` si está vacío. El contenido se descarta.
  presencia,

  /// Queda la cantidad de caracteres.
  largo,

  /// Queda la cantidad de palabras.
  palabras,

  /// Queda cuántos elementos tiene una lista.
  cuantos,

  /// Queda el valor redondeado a su tramo. Sirve para números que identifican de más si van
  /// exactos —una cantidad, un saldo— y que agrupan igual de bien por tramo.
  tramo,
}

/// Convierte un valor según su transformación.
///
/// 🔴 Devuelve `null` cuando no hay nada que mandar, y eso es distinto de mandar cero. Un
/// cero dice «se midió y dio cero»; un nulo dice «no se midió». Confundirlos hace que una
/// estadística cuente como ceros a la gente de la que no se sabe nada.
Object? transformar(Object? valor, Transformacion como, {int tramoDe = 10}) {
  switch (como) {
    case Transformacion.taICual:
      return valor;

    case Transformacion.presencia:
      if (valor == null) return null;
      final s = valor.toString().trim();
      return s.isEmpty ? 0 : 1;

    case Transformacion.largo:
      if (valor == null) return null;
      return valor.toString().length;

    case Transformacion.palabras:
      if (valor == null) return null;
      final s = valor.toString().trim();
      if (s.isEmpty) return 0;
      // 🔴 SEPARADOR CON SOPORTE UNICODE, y no el `\W` de siempre. Con `\W`, que sólo
      // considera letra a `[A-Za-z0-9_]`, «María» se parte en «Mar» y «a»: el conteo daría
      // 5 palabras para «María Fernanda Solís». En una cartera latinoamericana eso no es un
      // caso borde, es la mayoría — y el error es silencioso, porque el número igual sale.
      // Lo encontró una prueba el 2026-09-01, no una revisión.
      return s
          .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
          .where((p) => p.isNotEmpty)
          .length;

    case Transformacion.cuantos:
      if (valor == null) return null;
      if (valor is Iterable) return valor.length;
      if (valor is Map) return valor.length;
      return null;

    case Transformacion.tramo:
      if (valor == null) return null;
      final n = valor is num ? valor : num.tryParse(valor.toString());
      if (n == null) return null;
      // Se redondea hacia abajo: «más de 40» es una afirmación segura; «alrededor de 45»
      // parece precisión que no hay.
      return (n / tramoDe).floor() * tramoDe;
  }
}

/// La ficha de un campo: de dónde sale y cómo sale.
class CampoRecolectado {
  /// Cómo se llama en el paquete que se sube.
  final String nombre;

  /// Qué se hace con el valor antes de mandarlo.
  final Transformacion como;

  /// 🔴 QUÉ SE MANDA, EN CASTELLANO. Es el texto que se le puede mostrar a una persona que
  /// pregunte qué se sabe de ella, y a un comercio que quiera saber qué está recolectando.
  /// Un campo cuyo «qué manda» no se puede escribir en una frase es un campo que nadie
  /// entiende, incluidos nosotros.
  final String queManda;

  /// 🔴 PARA QUÉ SIRVE — en una frase, qué aporta este dato y por qué se recolecta. Lo pidió
  /// Juan el 2026-09-01: no alcanza con decir QUÉ se manda; hay que poder decirle a la persona
  /// y al comercio para qué. Se muestra junto al «qué manda», en la consola y en la app.
  final String? paraQue;

  /// 🔴 ¿Este valor lo DERIVA nuestro código, o es una lectura directa del sistema?
  /// «computada» = la calculamos (una comparación, un conteo, un tramo, una condición);
  /// «cruda» = sale tal cual del aparato. Lo pidió Juan el 2026-09-01 para mostrarlo en la
  /// consola: quien mira los datos tiene que poder distinguir un hecho del teléfono de una
  /// conclusión nuestra. Toda transformación que no sea `taICual` es computada por definición;
  /// esto marca además las `taICual` que igual derivamos (un booleano calculado, un conteo).
  final bool computada;

  /// Para `tramo`: de cuánto es cada escalón.
  final int tramoDe;

  const CampoRecolectado(
    this.nombre,
    this.como, {
    required this.queManda,
    this.paraQue,
    this.computada = false,
    this.tramoDe = 10,
  });

  /// ¿Este campo puede llevar texto escrito por una persona?
  ///
  /// Lo usa la comprobación: un campo así **no puede** salir tal cual.
  bool get vieneDeUnaPersona => como != Transformacion.taICual;
}

/// Arma el bloque que se sube, aplicando la transformación de cada campo.
///
/// 🔴 RECORRE LOS CAMPOS DECLARADOS, no lo que trae el mapa de entrada. Es al revés de como
/// se escribiría naturalmente, y es a propósito: recorriendo la entrada, cualquier clave que
/// alguien agregue mañana en el lugar de origen viajaría sin declarar y sin transformar.
/// Así, lo que no está declarado no sale — que es el comportamiento seguro.
Map<String, Object?> armarPaquete(
  List<CampoRecolectado> campos,
  Map<String, Object?> crudo,
) {
  final salida = <String, Object?>{};
  for (final c in campos) {
    final v = transformar(crudo[c.nombre], c.como, tramoDe: c.tramoDe);
    if (v != null) salida[c.nombre] = v;
  }
  return salida;
}
