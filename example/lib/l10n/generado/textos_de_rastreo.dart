import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'textos_de_rastreo_es.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of TextosDeRastreo
/// returned by `TextosDeRastreo.of(context)`.
///
/// Applications need to include `TextosDeRastreo.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generado/textos_de_rastreo.dart';
///
/// return MaterialApp(
///   localizationsDelegates: TextosDeRastreo.localizationsDelegates,
///   supportedLocales: TextosDeRastreo.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the TextosDeRastreo.supportedLocales
/// property.
abstract class TextosDeRastreo {
  TextosDeRastreo(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static TextosDeRastreo of(BuildContext context) {
    return Localizations.of<TextosDeRastreo>(context, TextosDeRastreo)!;
  }

  static const LocalizationsDelegate<TextosDeRastreo> delegate =
      _TextosDeRastreoDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('es')];

  /// No description provided for @titulo.
  ///
  /// In es, this message translates to:
  /// **'Rastreo · diagnóstico'**
  String get titulo;

  /// No description provided for @si.
  ///
  /// In es, this message translates to:
  /// **'Sí'**
  String get si;

  /// No description provided for @no.
  ///
  /// In es, this message translates to:
  /// **'No'**
  String get no;

  /// No description provided for @sinDato.
  ///
  /// In es, this message translates to:
  /// **'—'**
  String get sinDato;

  /// No description provided for @seccionEnrolamiento.
  ///
  /// In es, this message translates to:
  /// **'Enrolamiento'**
  String get seccionEnrolamiento;

  /// No description provided for @sujeto.
  ///
  /// In es, this message translates to:
  /// **'Sujeto'**
  String get sujeto;

  /// No description provided for @instalacion.
  ///
  /// In es, this message translates to:
  /// **'Instalación'**
  String get instalacion;

  /// No description provided for @clave.
  ///
  /// In es, this message translates to:
  /// **'Clave del aparato'**
  String get clave;

  /// No description provided for @claveEnHardware.
  ///
  /// In es, this message translates to:
  /// **'Clave en hardware'**
  String get claveEnHardware;

  /// No description provided for @claveRegistrada.
  ///
  /// In es, this message translates to:
  /// **'Registrada en la ingesta'**
  String get claveRegistrada;

  /// No description provided for @enrolar.
  ///
  /// In es, this message translates to:
  /// **'Enrolar'**
  String get enrolar;

  /// No description provided for @enrolado.
  ///
  /// In es, this message translates to:
  /// **'Enrolado. Clave {clave}'**
  String enrolado(String clave);

  /// No description provided for @enrolamientoIncompleto.
  ///
  /// In es, this message translates to:
  /// **'Enrolamiento incompleto: {detalle}'**
  String enrolamientoIncompleto(String detalle);

  /// No description provided for @seccionConfiguracion.
  ///
  /// In es, this message translates to:
  /// **'Configuración del servidor'**
  String get seccionConfiguracion;

  /// No description provided for @activo.
  ///
  /// In es, this message translates to:
  /// **'Activo'**
  String get activo;

  /// No description provided for @perfil.
  ///
  /// In es, this message translates to:
  /// **'Perfil'**
  String get perfil;

  /// No description provided for @respuesta.
  ///
  /// In es, this message translates to:
  /// **'Respuesta'**
  String get respuesta;

  /// No description provided for @quietoTras.
  ///
  /// In es, this message translates to:
  /// **'Apaga el GPS tras'**
  String get quietoTras;

  /// No description provided for @arranque.
  ///
  /// In es, this message translates to:
  /// **'Arranca sobre'**
  String get arranque;

  /// No description provided for @lote.
  ///
  /// In es, this message translates to:
  /// **'Lote'**
  String get lote;

  /// No description provided for @minutos.
  ///
  /// In es, this message translates to:
  /// **'{n} min'**
  String minutos(int n);

  /// No description provided for @kmh.
  ///
  /// In es, this message translates to:
  /// **'{n} km/h'**
  String kmh(int n);

  /// No description provided for @releer.
  ///
  /// In es, this message translates to:
  /// **'Releer'**
  String get releer;

  /// No description provided for @techoLote.
  ///
  /// In es, this message translates to:
  /// **'Techo de un lote'**
  String get techoLote;

  /// No description provided for @puntos.
  ///
  /// In es, this message translates to:
  /// **'{n} puntos'**
  String puntos(int n);

  /// No description provided for @forzado.
  ///
  /// In es, this message translates to:
  /// **'Estado forzado'**
  String get forzado;

  /// No description provided for @cadenciaRespaldo.
  ///
  /// In es, this message translates to:
  /// **'El servidor no mandó tabla de cadencia: rige el respaldo (10 s · lote 300 s).'**
  String get cadenciaRespaldo;

  /// No description provided for @cadenciaAhora.
  ///
  /// In es, this message translates to:
  /// **'Cadencia ahora'**
  String get cadenciaAhora;

  /// No description provided for @filaConGps.
  ///
  /// In es, this message translates to:
  /// **'cada {m} s · lote {l} s'**
  String filaConGps(int m, int l);

  /// No description provided for @filaSinGps.
  ///
  /// In es, this message translates to:
  /// **'GPS apagado · latido {min} min'**
  String filaSinGps(int min);

  /// No description provided for @seccionPermisos.
  ///
  /// In es, this message translates to:
  /// **'Permisos'**
  String get seccionPermisos;

  /// No description provided for @ubicacion.
  ///
  /// In es, this message translates to:
  /// **'Ubicación'**
  String get ubicacion;

  /// No description provided for @permisoSiempre.
  ///
  /// In es, this message translates to:
  /// **'Siempre'**
  String get permisoSiempre;

  /// No description provided for @permisoEnUso.
  ///
  /// In es, this message translates to:
  /// **'Sólo mientras se usa'**
  String get permisoEnUso;

  /// No description provided for @permisoNo.
  ///
  /// In es, this message translates to:
  /// **'No'**
  String get permisoNo;

  /// No description provided for @gps.
  ///
  /// In es, this message translates to:
  /// **'GPS del teléfono'**
  String get gps;

  /// No description provided for @prendido.
  ///
  /// In es, this message translates to:
  /// **'Prendido'**
  String get prendido;

  /// No description provided for @apagado.
  ///
  /// In es, this message translates to:
  /// **'Apagado'**
  String get apagado;

  /// No description provided for @actividadFisica.
  ///
  /// In es, this message translates to:
  /// **'Actividad física'**
  String get actividadFisica;

  /// No description provided for @pedirPermisos.
  ///
  /// In es, this message translates to:
  /// **'Pedir permisos'**
  String get pedirPermisos;

  /// No description provided for @seccionBateria.
  ///
  /// In es, this message translates to:
  /// **'Batería'**
  String get seccionBateria;

  /// No description provided for @nivel.
  ///
  /// In es, this message translates to:
  /// **'Nivel'**
  String get nivel;

  /// No description provided for @porciento.
  ///
  /// In es, this message translates to:
  /// **'{n} %'**
  String porciento(int n);

  /// No description provided for @cargando.
  ///
  /// In es, this message translates to:
  /// **'Cargando'**
  String get cargando;

  /// No description provided for @sinRestricciones.
  ///
  /// In es, this message translates to:
  /// **'Sin restricciones de batería'**
  String get sinRestricciones;

  /// No description provided for @ahorro.
  ///
  /// In es, this message translates to:
  /// **'Ahorro de energía'**
  String get ahorro;

  /// No description provided for @aparato.
  ///
  /// In es, this message translates to:
  /// **'Aparato'**
  String get aparato;

  /// No description provided for @versionAndroid.
  ///
  /// In es, this message translates to:
  /// **'Android API {n}'**
  String versionAndroid(int n);

  /// No description provided for @ajustesDeBateria.
  ///
  /// In es, this message translates to:
  /// **'Ajustes de batería'**
  String get ajustesDeBateria;

  /// No description provided for @seccionCaptura.
  ///
  /// In es, this message translates to:
  /// **'Captura'**
  String get seccionCaptura;

  /// No description provided for @captura.
  ///
  /// In es, this message translates to:
  /// **'Captura'**
  String get captura;

  /// No description provided for @capturaPropia.
  ///
  /// In es, this message translates to:
  /// **'Propia'**
  String get capturaPropia;

  /// No description provided for @capturaTransistor.
  ///
  /// In es, this message translates to:
  /// **'Transistor'**
  String get capturaTransistor;

  /// No description provided for @activa.
  ///
  /// In es, this message translates to:
  /// **'Activa'**
  String get activa;

  /// No description provided for @estado.
  ///
  /// In es, this message translates to:
  /// **'Estado'**
  String get estado;

  /// No description provided for @motivo.
  ///
  /// In es, this message translates to:
  /// **'Motivo'**
  String get motivo;

  /// No description provided for @estadoQuieto.
  ///
  /// In es, this message translates to:
  /// **'Quieto (GPS apagado)'**
  String get estadoQuieto;

  /// No description provided for @estadoConfirmando.
  ///
  /// In es, this message translates to:
  /// **'Confirmando movimiento'**
  String get estadoConfirmando;

  /// No description provided for @estadoRodando.
  ///
  /// In es, this message translates to:
  /// **'Rodando (GPS preciso)'**
  String get estadoRodando;

  /// No description provided for @iniciar.
  ///
  /// In es, this message translates to:
  /// **'Iniciar rastreo'**
  String get iniciar;

  /// No description provided for @detener.
  ///
  /// In es, this message translates to:
  /// **'Detener'**
  String get detener;

  /// No description provided for @noArranco.
  ///
  /// In es, this message translates to:
  /// **'No arrancó: {motivo}'**
  String noArranco(String motivo);

  /// No description provided for @seccionCola.
  ///
  /// In es, this message translates to:
  /// **'Cola en el teléfono'**
  String get seccionCola;

  /// No description provided for @enCola.
  ///
  /// In es, this message translates to:
  /// **'Puntos en cola'**
  String get enCola;

  /// No description provided for @tamano.
  ///
  /// In es, this message translates to:
  /// **'Tamaño'**
  String get tamano;

  /// No description provided for @kb.
  ///
  /// In es, this message translates to:
  /// **'{n} KB'**
  String kb(String n);

  /// No description provided for @loteEnVuelo.
  ///
  /// In es, this message translates to:
  /// **'Lote en vuelo'**
  String get loteEnVuelo;

  /// No description provided for @aceptados.
  ///
  /// In es, this message translates to:
  /// **'Lotes aceptados'**
  String get aceptados;

  /// No description provided for @rechazados.
  ///
  /// In es, this message translates to:
  /// **'Lotes rechazados'**
  String get rechazados;

  /// No description provided for @descartados.
  ///
  /// In es, this message translates to:
  /// **'Puntos descartados por techo'**
  String get descartados;

  /// No description provided for @proximoIntento.
  ///
  /// In es, this message translates to:
  /// **'Próximo intento'**
  String get proximoIntento;

  /// No description provided for @fallosSeguidos.
  ///
  /// In es, this message translates to:
  /// **'Fallos seguidos'**
  String get fallosSeguidos;

  /// No description provided for @enviarAhora.
  ///
  /// In es, this message translates to:
  /// **'Mandar ahora'**
  String get enviarAhora;

  /// No description provided for @seccionUltimoLote.
  ///
  /// In es, this message translates to:
  /// **'Último lote enviado'**
  String get seccionUltimoLote;

  /// No description provided for @cuando.
  ///
  /// In es, this message translates to:
  /// **'Cuándo'**
  String get cuando;

  /// No description provided for @codigo.
  ///
  /// In es, this message translates to:
  /// **'Código'**
  String get codigo;

  /// No description provided for @ningunLote.
  ///
  /// In es, this message translates to:
  /// **'Todavía no se mandó ninguno'**
  String get ningunLote;

  /// No description provided for @seccionHuecos.
  ///
  /// In es, this message translates to:
  /// **'Huecos en las últimas 24 h'**
  String get seccionHuecos;

  /// No description provided for @sinHuecos.
  ///
  /// In es, this message translates to:
  /// **'Sin huecos'**
  String get sinHuecos;

  /// No description provided for @hueco.
  ///
  /// In es, this message translates to:
  /// **'{desde} → {hasta} · {seg} s'**
  String hueco(String desde, String hasta, int seg);

  /// No description provided for @seccionProblemas.
  ///
  /// In es, this message translates to:
  /// **'Problemas'**
  String get seccionProblemas;

  /// No description provided for @sinProblemas.
  ///
  /// In es, this message translates to:
  /// **'Sin problemas'**
  String get sinProblemas;

  /// No description provided for @seccionSimular.
  ///
  /// In es, this message translates to:
  /// **'Simular recorrido'**
  String get seccionSimular;

  /// No description provided for @simularExplicacion.
  ///
  /// In es, this message translates to:
  /// **'Inyecta una ruta de ~4 km como si fuera el GPS: 40 s parado, 30 km/h, 60 km/h, y parado al final hasta que se apague el GPS.'**
  String get simularExplicacion;

  /// No description provided for @simular.
  ///
  /// In es, this message translates to:
  /// **'Simular recorrido'**
  String get simular;

  /// No description provided for @detenerSimulacion.
  ///
  /// In es, this message translates to:
  /// **'Detener simulación'**
  String get detenerSimulacion;

  /// No description provided for @simulando.
  ///
  /// In es, this message translates to:
  /// **'Simulando: segundo {i} de {n}'**
  String simulando(int i, int n);

  /// No description provided for @simulacionIos.
  ///
  /// In es, this message translates to:
  /// **'En el simulador de iOS la ruta se inyecta desde la Mac:'**
  String get simulacionIos;

  /// No description provided for @avisoTitulo.
  ///
  /// In es, this message translates to:
  /// **'Registrando tu recorrido'**
  String get avisoTitulo;

  /// No description provided for @avisoCuerpo.
  ///
  /// In es, this message translates to:
  /// **'Se apaga solo cuando te detienes.'**
  String get avisoCuerpo;

  /// No description provided for @permisoSiempreTitulo.
  ///
  /// In es, this message translates to:
  /// **'Un paso más: ubicación todo el tiempo'**
  String get permisoSiempreTitulo;

  /// No description provided for @permisoSiempreCuerpo.
  ///
  /// In es, this message translates to:
  /// **'Para seguir tu recorrido con la pantalla apagada, elige «Permitir todo el tiempo» en los ajustes de ubicación de la app.'**
  String get permisoSiempreCuerpo;

  /// No description provided for @permisoAbrirAjustes.
  ///
  /// In es, this message translates to:
  /// **'Abrir ajustes'**
  String get permisoAbrirAjustes;

  /// No description provided for @permisoDenegado.
  ///
  /// In es, this message translates to:
  /// **'La ubicación está bloqueada. Actívala desde los ajustes de la app para registrar tu recorrido.'**
  String get permisoDenegado;

  /// No description provided for @mapaVerMapa.
  ///
  /// In es, this message translates to:
  /// **'Ver mi mapa'**
  String get mapaVerMapa;

  /// No description provided for @mapaTitulo.
  ///
  /// In es, this message translates to:
  /// **'Mi recorrido'**
  String get mapaTitulo;

  /// No description provided for @mapaBorrar.
  ///
  /// In es, this message translates to:
  /// **'Borrar el recorrido'**
  String get mapaBorrar;

  /// No description provided for @mapaSeguir.
  ///
  /// In es, this message translates to:
  /// **'Seguirme'**
  String get mapaSeguir;

  /// No description provided for @mapaSinPuntos.
  ///
  /// In es, this message translates to:
  /// **'Esperando tu primer punto. Empieza a caminar.'**
  String get mapaSinPuntos;

  /// No description provided for @mapaDistancia.
  ///
  /// In es, this message translates to:
  /// **'Distancia: {valor} {unidad}'**
  String mapaDistancia(String valor, String unidad);

  /// No description provided for @mapaDuracion.
  ///
  /// In es, this message translates to:
  /// **'Duración: {min} min {seg} s'**
  String mapaDuracion(int min, int seg);

  /// No description provided for @mapaPuntos.
  ///
  /// In es, this message translates to:
  /// **'{n} puntos'**
  String mapaPuntos(int n);

  /// No description provided for @mapaUltimo.
  ///
  /// In es, this message translates to:
  /// **'Último punto: {cuando}'**
  String mapaUltimo(String cuando);

  /// No description provided for @mapaSimulado.
  ///
  /// In es, this message translates to:
  /// **'Ubicación simulada'**
  String get mapaSimulado;

  /// No description provided for @mapaLotes.
  ///
  /// In es, this message translates to:
  /// **'Lotes enviados: {ok} aceptados, {mal} rechazados'**
  String mapaLotes(int ok, int mal);

  /// No description provided for @mapaHaceSeg.
  ///
  /// In es, this message translates to:
  /// **'hace {n} s'**
  String mapaHaceSeg(int n);

  /// No description provided for @mapaHaceMin.
  ///
  /// In es, this message translates to:
  /// **'hace {n} min'**
  String mapaHaceMin(int n);

  /// No description provided for @mapaHaceHoras.
  ///
  /// In es, this message translates to:
  /// **'hace {n} h'**
  String mapaHaceHoras(int n);

  /// No description provided for @simularCaminata.
  ///
  /// In es, this message translates to:
  /// **'Simular caminata desde aquí'**
  String get simularCaminata;

  /// No description provided for @caminataExplicacion.
  ///
  /// In es, this message translates to:
  /// **'Una vuelta a pie de ~1,5 km por las calles reales que salen de donde está el teléfono, a paso humano, con 20 s parado al salir y parado al volver.'**
  String get caminataExplicacion;

  /// No description provided for @caminataSinRuta.
  ///
  /// In es, this message translates to:
  /// **'No se pudo armar la caminata: el enrutador no contestó o no hay posición.'**
  String get caminataSinRuta;

  /// No description provided for @simularMoto.
  ///
  /// In es, this message translates to:
  /// **'Simular moto: ir a El Silencio y volver'**
  String get simularMoto;

  /// No description provided for @motoExplicacion.
  ///
  /// In es, this message translates to:
  /// **'Una moto por las calles reales desde aquí hasta El Silencio y de vuelta: 20 a 60 km/h, semáforos cada ~1,2 km, un minuto en el destino.'**
  String get motoExplicacion;

  /// No description provided for @simMedioAPie.
  ///
  /// In es, this message translates to:
  /// **'A pie'**
  String get simMedioAPie;

  /// No description provided for @simMedioDosRuedas.
  ///
  /// In es, this message translates to:
  /// **'Moto'**
  String get simMedioDosRuedas;

  /// No description provided for @simMedioCarro.
  ///
  /// In es, this message translates to:
  /// **'Carro'**
  String get simMedioCarro;

  /// No description provided for @simMinutos.
  ///
  /// In es, this message translates to:
  /// **'{n} min'**
  String simMinutos(int n);

  /// No description provided for @simularRecorridoReal.
  ///
  /// In es, this message translates to:
  /// **'Simular recorrido'**
  String get simularRecorridoReal;

  /// No description provided for @simRealExplicacion.
  ///
  /// In es, this message translates to:
  /// **'Una vuelta por las calles reales desde donde está el teléfono, del medio y la duración que elijas: velocidades creíbles, semáforos, y parado al salir y al volver.'**
  String get simRealExplicacion;
}

class _TextosDeRastreoDelegate extends LocalizationsDelegate<TextosDeRastreo> {
  const _TextosDeRastreoDelegate();

  @override
  Future<TextosDeRastreo> load(Locale locale) {
    return SynchronousFuture<TextosDeRastreo>(lookupTextosDeRastreo(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['es'].contains(locale.languageCode);

  @override
  bool shouldReload(_TextosDeRastreoDelegate old) => false;
}

TextosDeRastreo lookupTextosDeRastreo(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'es':
      return TextosDeRastreoEs();
  }

  throw FlutterError(
    'TextosDeRastreo.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
