/// EL APARATO QUE MANDA EL RASTREO AL ENROLAR — marca, modelo, sistema, emulador y SDK.
///
/// Tramo 3.4 (01-10-2026). Hasta acá el enrolamiento mandaba sólo `{plataforma}` y el servidor
/// reponía `isPhysicalDevice: true` por omisión: un emulador figuraba como teléfono real y la
/// pantalla Salud de la consola no tenía con qué agrupar por marca y modelo.
///
/// Ahora va `{plataforma, marca, modelo, versionSO, esEmulador, versionSdk}`, leído con
/// `device_info_plus` (el mismo [DatosDelDispositivo] que usa el alta de avisos). El servidor
/// los traduce al nombre del catálogo antes del muro del comercio, así que el comercio sigue
/// decidiendo qué se guarda. Lo que no se pudo leer NO viaja: ausente es «no se supo».
library;

import '../device_info.dart';
import '../version.dart';

/// Clave en preferencias: con qué versión del SDK se mandó el aparato por última vez.
const claveDeVersionDelAparato = 'akpush.rastreo.aparatoSdk';

/// El cuerpo `aparato` del enrolamiento. Puro: se prueba sin plataforma.
Map<String, dynamic> aparatoDelRastreo(DatosDelDispositivo? d, {required String plataforma}) {
  String? t(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();
  final marca = t(d?.marca) ?? t(d?.fabricante);
  return {
    'plataforma': d?.plataforma ?? plataforma,
    if (marca != null) 'marca': marca,
    if (t(d?.modelo) != null) 'modelo': t(d?.modelo),
    if (t(d?.versionDelSistema) != null) 'versionSO': t(d?.versionDelSistema),
    // El dato real del sistema, no un `true` por omisión: si no se supo, no viaja.
    if (d?.esFisico != null) 'esEmulador': !d!.esFisico!,
    'versionSdk': versionDelSdk,
  };
}

/// ¿Hay que volver a mandar el aparato? Sí, si nunca se mandó o se mandó con otro SDK.
bool hayQueReenviarElAparato(String? versionConQueSeMando) => versionConQueSeMando != versionDelSdk;
