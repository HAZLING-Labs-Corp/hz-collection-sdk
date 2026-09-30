/// EL LADO NATIVO DEL RASTREO — la clave del aparato, los relojes, la energía y la
/// actividad. Canal `hz_collection_sdk/rastreo` (Kotlin: `RastreoNativo.kt`; Swift:
/// `RastreoNativo.swift`).
///
/// ══ 🔴 LA CLAVE NO SALE NUNCA DEL APARATO ══
///
/// Se crea en el Android Keystore (con StrongBox si el teléfono lo tiene) o en el Secure
/// Enclave del iPhone, **no exportable**. Dart nunca ve la privada: le pasa los bytes al
/// nativo y recibe la firma. Por eso `claveId` se calcula acá, en Dart, sobre la PÚBLICA
/// (SHA-256 del SPKI DER): es la misma cuenta en las dos plataformas y en la ingesta.
///
/// Reinstalar la aplicación borra la clave → instalación nueva → enrolamiento nuevo
/// (PM-024 §11.6). No se intenta sobrevivir a eso: una clave que sobrevive a la
/// desinstalación es una clave que se puede copiar.
library;

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import 'detector_de_movimiento.dart';
import 'lote.dart';

const _canal = MethodChannel('hz_collection_sdk/rastreo');
const _actividades = EventChannel('hz_collection_sdk/rastreo/actividad');

/// La clave ES256 del aparato, en el almacén seguro del sistema.
class ClaveDelAparato implements FirmadorDeLotes {
  ClaveDelAparato._(this.claveId, this.publicaSpkiBase64, this.enHardware);

  @override
  final String claveId;

  /// La pública, SPKI DER en base64 — lo que se registra en la ingesta.
  final String publicaSpkiBase64;

  /// Si el sistema dice que vive en hardware (TEE / StrongBox / Secure Enclave). En el
  /// emulador y en el simulador es `false`, y eso se muestra: no es un defecto, es la
  /// verdad del aparato.
  final bool enHardware;

  static const alias = 'hz_collection_rastreo_es256';

  /// Crea la clave si no existe, y la devuelve.
  static Future<ClaveDelAparato> asegurar() async {
    final r = (await _canal.invokeMapMethod<String, dynamic>('clave.asegurar', {'alias': alias}))!;
    final publica = r['publica'] as String;
    return ClaveDelAparato._(
      claveIdDe(publica),
      publica,
      r['hardware'] == true,
    );
  }

  /// La huella de una pública SPKI DER en base64: SHA-256 hex de los bytes DER.
  static String claveIdDe(String spkiBase64) =>
      sha256.convert(base64.decode(spkiBase64)).toString();

  @override
  Future<String> firmar(List<int> bytes) async {
    final f = await _canal.invokeMethod<String>(
        'clave.firmar', {'alias': alias, 'datos': Uint8List.fromList(bytes)});
    if (f == null || f.isEmpty) throw StateError('El aparato no devolvió la firma');
    return f;
  }

  /// Para las pruebas de la app de ejemplo. Borra la clave: la instalación queda sin
  /// poder firmar hasta enrolar de nuevo.
  static Future<void> borrar() => _canal.invokeMethod('clave.borrar', {'alias': alias});
}

/// El reloj monotónico y los arranques. Ver `RelojDelLote`.
class RelojDelAparato {
  /// `mono` en ms desde el arranque (contando el sueño), y el contador de arranques del
  /// sistema si lo tiene (Android 7+: `Settings.Global.BOOT_COUNT`; iPhone no tiene).
  static Future<({int mono, int? arranques})> leer() async {
    final r = (await _canal.invokeMapMethod<String, dynamic>('reloj'))!;
    final a = (r['arranques'] as num?)?.toInt();
    return (mono: (r['mono'] as num).toInt(), arranques: (a == null || a < 0) ? null : a);
  }
}

/// Lo que el sistema dice de la energía: sin esto no se entiende por qué un Xiaomi deja de
/// grabar a los 20 minutos.
class EnergiaDelAparato {
  const EnergiaDelAparato({
    this.sinOptimizacion,
    this.ahorroDeEnergia,
    this.fabricante,
    this.modelo,
    this.android,
  });

  /// Android: la aplicación está exenta de la optimización de batería («Sin restricciones»).
  final bool? sinOptimizacion;
  final bool? ahorroDeEnergia;
  final String? fabricante;
  final String? modelo;
  final int? android;

  static Future<EnergiaDelAparato> leer() async {
    try {
      final r = await _canal.invokeMapMethod<String, dynamic>('energia') ?? const {};
      return EnergiaDelAparato(
        sinOptimizacion: r['sinOptimizacion'] as bool?,
        ahorroDeEnergia: r['ahorro'] as bool?,
        fabricante: r['fabricante'] as String?,
        modelo: r['modelo'] as String?,
        android: (r['sdk'] as num?)?.toInt(),
      );
    } catch (_) {
      return const EnergiaDelAparato();
    }
  }

  /// Abre la pantalla del sistema para pedir la exención. En Android es la única forma
  /// sin declarar `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` (que Play restringe): abrir la
  /// lista y que la persona la elija a mano.
  static Future<void> abrirAjustesDeBateria() async {
    try {
      await _canal.invokeMethod('energia.abrirAjustes');
    } catch (_) {}
  }
}

/// El reconocimiento de actividad del sistema.
class ActividadDelAparato {
  /// Si el permiso está (Android 10+: `ACTIVITY_RECOGNITION`; iPhone: Movimiento).
  static Future<bool> tienePermiso() async {
    try {
      return await _canal.invokeMethod<bool>('actividad.permiso') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Pide el permiso. Devuelve si quedó concedido.
  static Future<bool> pedirPermiso() async {
    try {
      return await _canal.invokeMethod<bool>('actividad.pedirPermiso') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Las transiciones de actividad. Un error en el flujo (sin permiso, sin Play Services)
  /// no es fatal: la detección sigue con la salida de zona y la velocidad.
  static Stream<TipoDeActividad> flujo() => _actividades
      .receiveBroadcastStream()
      .map((e) => _traducir('$e'));

  static TipoDeActividad _traducir(String s) => switch (s) {
        'vehiculo' => TipoDeActividad.vehiculo,
        'bici' => TipoDeActividad.bici,
        'aPie' => TipoDeActividad.aPie,
        'corriendo' => TipoDeActividad.corriendo,
        'quieto' => TipoDeActividad.quieto,
        _ => TipoDeActividad.desconocida,
      };
}
