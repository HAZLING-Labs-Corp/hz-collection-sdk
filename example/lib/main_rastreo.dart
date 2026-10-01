/// LA APP DE PRUEBA DEL RASTREO — un punto de entrada aparte, para no tocar la demo de
/// avisos de `main.dart`.
///
///     flutter run -t lib/main_rastreo.dart \
///       --dart-define=AKPUSH_KEY=pk_… \
///       --dart-define=AKPUSH_URL=http://10.0.2.2:3085/api/v1 \
///       --dart-define=RASTREO_URL_INGESTA=http://10.0.2.2:8080/api/v1 \
///       --dart-define=RASTREO_SUJETO=sujeto-prueba-1 \
///       --dart-define=RASTREO_CAPTURA=propia        # o transistor
///
/// El sujeto es FIJO a propósito: es una app de prueba, y enrolar siempre al mismo permite
/// buscarlo en la base sin anotar nada.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hz_collection_sdk/hz_collection_sdk.dart' show MedidorDeHilo;

import 'l10n/generado/textos_de_rastreo.dart';
import 'rastreo/pantalla_de_rastreo.dart';
import 'rastreo/vigia_del_hilo.dart';

/// `10.0.2.2` es cómo el emulador de Android llega al localhost de la máquina.
const _llave = String.fromEnvironment('AKPUSH_KEY', defaultValue: 'pk_demo.local');
const _url = String.fromEnvironment('AKPUSH_URL', defaultValue: 'http://10.0.2.2:8080/api/v1');
const _urlIngesta = String.fromEnvironment('RASTREO_URL_INGESTA');
const _sujeto = String.fromEnvironment('RASTREO_SUJETO', defaultValue: 'sujeto-prueba-1');
const _captura = String.fromEnvironment('RASTREO_CAPTURA', defaultValue: 'propia');

/// Las medidas de hilo (`HzRastreoHilo` en logcat): en debug siempre; en profile o release,
/// con `--dart-define=RASTREO_MEDIR=true`.
const _medir = bool.fromEnvironment('RASTREO_MEDIR');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (kDebugMode || _medir) {
    MedidorDeHilo.activo = true;
    VigiaDelHilo().arrancar();
  }
  runApp(const AppDeRastreo());
}

class AppDeRastreo extends StatelessWidget {
  const AppDeRastreo({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        onGenerateTitle: (c) => TextosDeRastreo.of(c).titulo,
        locale: const Locale('es'),
        supportedLocales: TextosDeRastreo.supportedLocales,
        localizationsDelegates: const [
          TextosDeRastreo.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2D5F8A)),
          useMaterial3: true,
        ),
        home: const PantallaDeRastreo(
          llave: _llave,
          url: _url,
          urlIngesta: _urlIngesta == '' ? null : _urlIngesta,
          sujeto: _sujeto,
          capturaInicial: _captura,
        ),
      );
}
