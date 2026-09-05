/// Recibir notificaciones push con una llave y una línea.
///
/// El PAQUETE se llama `hz_collection_sdk` — el producto es Collection—, pero
/// la clase pública sigue siendo `AkPush`.
///
/// 🔴 PENDIENTE, A PROPÓSITO: la consola muestra `AkPush.init({...})` como
/// ejemplo copiable en su pantalla de integración, y renombrar la clase acá
/// sin coordinar ese cambio con la consola rompe ese ejemplo para todo el
/// que lo copie mientras tanto. Cuando se renombre, es un cambio coordinado
/// entre los dos lados, no algo que se resuelve solo de este lado.
library;

export 'src/ak_push.dart' show AkPush, manejadorDeSegundoPlano;
export 'src/decision_de_dibujo.dart' show DecidirDibujo, DecisionDeDibujo;
export 'src/diagnostico.dart'
    show
        Diagnostico,
        Eslabon,
        EstadoDeFirebase,
        EstadoDeLaConfiguracion,
        EstadoDelRegistro,
        EstadoDelToken,
        EstadoDeUbicacion;
export 'src/errors.dart' show AkPushError, AkPushErrorCode;
export 'src/consentimiento.dart' show Consentimiento;
export 'src/politica.dart'
    show
        PoliticaDeNotificaciones,
        MomentoDelPermiso,
        TextosDeLaPregunta,
        AccionDePermiso,
        Disparador,
        decidirQueHacer;
export 'src/sesion.dart'
    show ResultadoDeSesion, HuellaDelRegistro, PlanDeSesion, planearInicioDeSesion, motivoDeSesion;
// `EstadoDelPermiso` es el tipo que devuelven AkPush.estadoDelPermiso() y
// AkPush.pedirPermiso(): sin este export nadie puede nombrarlo para guardarlo en
// una variable. `GestorDePermiso` queda adentro, detrás de la fachada.
export 'src/permiso.dart' show EstadoDelPermiso;
// QUÉ SE RECOLECTA DE ESTE APARATO, para que la aplicación lo pueda MOSTRAR.
//
// 🔴 No es un extra de la demo: un colector de datos que no le deja ver a la persona
// qué recolectó es exactamente lo que la gente desconfía. Y del lado del comercio, es
// lo que le permite armar su propia pantalla de «tus datos» sin pedirnos nada.
export 'src/device_info.dart' show DatosDelDispositivo;
// La campanita hecha, y el estado de los avisos en castellano. Quien quiera dibujar
// su propia campana usa `EstadoDeAvisos` + `AkPush.avisos` + `AkPush.resolverAvisos()`;
// quien no quiera dibujar nada pone `AkPush.campanita()` y listo.
export 'src/campanita.dart' show CampanitaDeAvisos, EstadoDeAvisos;
export 'src/modal_de_ubicacion.dart' show ModalDeUbicacion;
export 'src/politica.dart'
    show PoliticaDeUbicacion, TextosDeUbicacion, MomentoDeUbicacion;
export 'src/push_message.dart' show AccionDePush, PushMessage;
export 'src/remote_config.dart' show AkPushConfig, InfoDeModulo;
// El sujeto — quien se loguea — y su documento y organización. Es la raíz del
// modelo nuevo: sin este export nadie puede armar un `Documento` para pasarlo
// a `AkPush.alIniciarSesion`.
export 'src/sujeto.dart'
    show TipoDeSujeto, ClaseDeDocumento, Documento, Organizacion;
// `AvisoConRuta` va en el `show` o los atajos `mensaje.tieneRuta` y
// `mensaje.ruta` no existen para quien integra: una extensión que no se exporta
// no se aplica del otro lado.
export 'src/ruta.dart' show AvisoConRuta, IntencionPendiente, RutaDelAviso;

// Las señales de nivel 0 y sus fichas, para que una app pueda MOSTRARLE a la persona todo
// lo que se recolecta —con qué manda y para qué sirve—, agrupado. Sin esto, «tus datos» de
// la app sólo podría mostrar el puñado de campos del aparato, no las 95 señales.
export 'src/modulos/modulo_senales.dart' show ModuloDeSenales;
export 'src/modulos/modulo_autenticidad.dart' show ModuloDeAutenticidad;
export 'src/permisologia/campos.dart'
    show camposDeSenales, camposDeAutenticidad, gruposDeSenales, GrupoDeSenales, grupoDe;
export 'src/permisologia/transformar.dart' show CampoRecolectado, Transformacion;

// ── EL COMPORTAMIENTO DENTRO DE LA PROPIA APLICACIÓN ─────────────────────────
//
// Sin estos `show`, quien integra no puede nombrar lo que le devuelve
// `AkPush.formulario(...)` y por lo tanto no puede guardarlo en un campo de su pantalla —
// que es la única forma de usarlo. Un tipo que no se exporta no existe del otro lado.
//
// 🔴 `EventoDeComportamiento` y `ColaDeEventos` NO se exportan a propósito: son de adentro.
// Quien integra declara formularios y campos; los eventos los arma el SDK, y dejar que se
// armen de afuera es dejar que alguien invente un tipo de evento que el contrato no tiene.
export 'src/comportamiento/comportamiento.dart'
    show ObservadorDeFormulario, ObservadorDeCampo, EstadoDelComportamiento;
// Los siete nombres del contrato, para que una aplicación pueda mostrarlos o filtrarlos sin
// escribirlos a mano — que es cómo aparece el octavo nombre que nadie del otro lado conoce.
export 'src/comportamiento/evento.dart' show TipoDeEvento;
// Los cinco números de la política, con su motivo escrito al lado. Se exporta también para
// poder volver al comportamiento de antes en una línea:
// `AkPush.init(..., politicaDeTransmision: PoliticaDeTransmision.comoEstabaAntes)`.
export 'src/transmision/politica_de_transmision.dart'
    show
        PoliticaDeTransmision,
        DecisionDeEnvio,
        senalesDeMomento,
        momentosQueElBackTodaviaNoTiene,
        senalesDeMomentoDe;
