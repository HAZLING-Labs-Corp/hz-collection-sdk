/// PUNTO DE ENTRADA PARA PROBAR — el mismo ejemplo, con el brazo que lo toca
/// ═══════════════════════════════════════════════════════════════════════════
///
/// Escrito el 2026-09-15 para poder caminar la app en el simulador de iOS.
///
/// 🔴 POR QUÉ HACE FALTA UN ARCHIVO APARTE, Y NO UNA BANDERA EN `main.dart`.
///
/// El emulador de Android se toca por fuera —`adb shell input tap`— y por eso ahí no hizo falta
/// nada. El simulador de iOS **no acepta toques por línea de comandos**: `simctl` tiene
/// `screenshot` y `launch`, y no tiene `tap`; `idb` no está instalado en esta máquina.
///
/// La única forma de manejarlo desde afuera es `flutter_driver`, y el driver exige
/// `enableFlutterDriverExtension()` ANTES de `runApp`. Eso abre un canal de control remoto
/// dentro de la aplicación — algo que en la app de verdad no se pone nunca. De ahí el archivo
/// aparte: se compila con `-t lib/main_probado.dart` sólo para probar, y `main.dart` queda
/// intacto, sin una sola línea de prueba adentro.
///
/// No duplica nada: importa `DemoApp` del ejemplo y corre exactamente la misma aplicación.
library;

import 'package:flutter/material.dart';
import 'package:flutter_driver/driver_extension.dart';

import 'main.dart';

void main() {
  enableFlutterDriverExtension();
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DemoApp());
}
