/// EL ESTADO DE LA MEDICIÓN, EN UNA PALABRA — para que la app no tenga que combinar cuatro cosas
/// (la configuración, el apagado del servidor, el permiso y el consentimiento) para decirle a la
/// persona si se la está midiendo y, si no, por qué.
///
/// Es puro: [estadoDeMedicionDe] recibe lo que `Rastreo` ya sabe y decide. Se prueba sin teléfono.
library;

/// Por qué se mide o no se mide, en el orden en que la app lo tiene que resolver.
enum EstadoDeMedicion {
  /// La captura está prendida: se mide.
  midiendo,

  /// El servidor no quiere medir: la configuración dice `activo: false`, o contestó
  /// `403 rastreo_apagado` (el comercio) o `403 medicion_apagada` (la medición de esta persona).
  apagadoPorElServidor,

  /// La persona apagó la ubicación del teléfono (el servicio de ubicación, no el permiso).
  apagadoPorLaPersona,

  /// La app no tiene permiso de ubicación.
  sinPermiso,

  /// La persona no dijo que sí a la pregunta del rastreo (la negó o nunca se le preguntó).
  sinConsentimiento,

  /// El rastreo no está corriendo: no se llamó `iniciar`, o se llamó `detener`.
  detenido,
}

/// Lo que la persona contestó a la pregunta del rastreo, en este aparato.
enum EstadoDelConsentimiento {
  /// Nunca quedó anotada una respuesta.
  nuncaPreguntado,

  /// Dijo que sí y quedó anotado en Collection.
  concedido,

  /// Dijo que no y quedó anotado en Collection.
  negado,
}

/// Decide el estado. La precedencia va de lo que la persona puede arreglar a lo que no:
/// consentimiento → permiso → ubicación apagada → servidor → detenido → midiendo.
///
/// [permisoConcedido] y [ubicacionPrendida] en `null` quieren decir «todavía no se leyó»: no
/// se afirma que falten.
EstadoDeMedicion estadoDeMedicionDe({
  required EstadoDelConsentimiento consentimiento,
  required bool? permisoConcedido,
  required bool? ubicacionPrendida,
  required bool configuracionActiva,
  required bool apagadoPorElServidor,
  required bool corriendo,
  required bool capturaActiva,
}) {
  if (consentimiento != EstadoDelConsentimiento.concedido) return EstadoDeMedicion.sinConsentimiento;
  if (permisoConcedido == false) return EstadoDeMedicion.sinPermiso;
  if (ubicacionPrendida == false) return EstadoDeMedicion.apagadoPorLaPersona;
  if (apagadoPorElServidor || (corriendo && !configuracionActiva)) return EstadoDeMedicion.apagadoPorElServidor;
  if (!corriendo || !capturaActiva) return EstadoDeMedicion.detenido;
  return EstadoDeMedicion.midiendo;
}
