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
// 🔴 `ModoDeLectura` va en el `show` o el comercio no puede ni nombrar el modo que le
// devuelve `AkPush.modoDeUbicacion` — y sin poder nombrarlo no puede comprobar si el
// segundo plano quedó andando, que es justo lo que hay que comprobar.
export 'src/politica.dart'
    show
        PoliticaDeUbicacion,
        TextosDeUbicacion,
        TextosDeSiempre,
        MomentoDeUbicacion,
        ModoDeLectura;
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

// ── RASTREO — la persona con su aparato, mientras se mueve ───────────────────
//
// Es un módulo aparte de la fachada `AkPush` a propósito: mide todo el día en el fondo, con
// su propia clave, su propia cola y su propio reloj, y una aplicación puede usarlo sin
// avisos push (y al revés). Ver `lib/src/rastreo/rastreo.dart`.
//
// `CapturaDeRastreo` y sus eventos se exportan para que una aplicación pueda enchufar otra
// captura —la de Transistor, en la app de ejemplo— sin que este paquete dependa de ella.
export 'src/rastreo/rastreo.dart'
    show Rastreo, ResultadoDeEnrolamiento, DiagnosticoDeRastreo;
// Tramo 6.2: si se mide y, si no, por qué; y el consentimiento con sus tres casos.
export 'src/rastreo/estado_de_medicion.dart' show EstadoDeMedicion, EstadoDelConsentimiento;
export 'src/rastreo/configuracion_de_rastreo.dart' show ConfiguracionDeRastreo;
export 'src/rastreo/etiquetas/etiquetas_ble.dart' show EtiquetaBle, ConfiguracionDeEtiquetas, Avistamiento, AnuncioBle;
export 'src/rastreo/etiquetas/escaner_ble.dart' show EscanerBle, EscanerReactivo;
export 'src/rastreo/etiquetas/vigia_de_etiquetas.dart' show VigiaDeEtiquetas;
export 'src/rastreo/cadencia.dart'
    show FilaDeCadencia, CondicionDeCadencia, SituacionDelAparato, evaluarCadencia;
export 'src/rastreo/captura.dart'
    show
        CapturaDeRastreo,
        CapturaPropia,
        TextosDelAvisoDeRastreo,
        EventoDeCaptura,
        PuntoCapturado,
        CambioDeEstado,
        ProblemaDeCaptura;
export 'src/rastreo/punto.dart' show PuntoDeRastreo;
// El detector va exportado para que otra captura (la de Transistor) grabe con el MISMO
// criterio que la propia: si no, D-04 compararía dos criterios además de dos capturas.
export 'src/rastreo/detector_de_movimiento.dart'
    show EstadoDeMovimiento, TipoDeActividad, DetectorDeMovimiento, Lectura, Decision;
export 'src/rastreo/cola_de_rastreo.dart' show Hueco;
export 'src/rastreo/emisor_de_lotes.dart' show ResultadoDelEmisor;
export 'src/rastreo/medidor_de_hilo.dart' show MedidorDeHilo;
export 'src/rastreo/nativo_de_rastreo.dart'
    show EnergiaDelAparato, ActividadDelAparato, EtiquetasDelAparato, ClaveDelAparato;
// Tramo 3.3: el suceso que la app recibe en `Rastreo.sucesos` («¿estás bien?»), los umbrales
// del golpe que llegan en la configuración, y el motivo de un rato sin GPS del diagnóstico.
export 'src/rastreo/golpe/sucesos_del_aparato.dart' show SucesoDelAparato, TipoDeSuceso;
export 'src/rastreo/golpe/detector_de_golpe.dart' show UmbralesDeGolpe;
export 'src/rastreo/sin_gps.dart' show MotivoSinGps;
