import 'package:flutter_test/flutter_test.dart';
import 'package:hz_collection_sdk/src/device_info.dart';
import 'package:hz_collection_sdk/src/rastreo/aparato_del_rastreo.dart';
import 'package:hz_collection_sdk/src/version.dart';

void main() {
  group('aparato del rastreo (tramo 3.4)', () {
    test('un emulador va como esEmulador:true, con marca, modelo, sistema y SDK', () {
      const d = DatosDelDispositivo(
        identificadorDePaquete: 'com.x',
        plataforma: 'android',
        desfaseUtcMinutos: -240,
        marca: 'google',
        fabricante: 'Google',
        modelo: 'sdk_gphone64_arm64',
        versionDelSistema: '15',
        esFisico: false,
      );
      expect(aparatoDelRastreo(d, plataforma: 'android'), {
        'plataforma': 'android',
        'marca': 'google',
        'modelo': 'sdk_gphone64_arm64',
        'versionSO': '15',
        'esEmulador': true,
        'versionSdk': versionDelSdk,
      });
    });

    test('un teléfono real va con esEmulador:false; sin marca usa el fabricante', () {
      const d = DatosDelDispositivo(
        identificadorDePaquete: 'com.x',
        plataforma: 'android',
        desfaseUtcMinutos: 0,
        fabricante: 'Xiaomi',
        modelo: ' Redmi 9 ',
        esFisico: true,
      );
      final a = aparatoDelRastreo(d, plataforma: 'android');
      expect(a['marca'], 'Xiaomi');
      expect(a['modelo'], 'Redmi 9');
      expect(a['esEmulador'], false);
    });

    test('lo que no se supo no viaja (ni un true por omisión)', () {
      final a = aparatoDelRastreo(null, plataforma: 'ios');
      expect(a, {'plataforma': 'ios', 'versionSdk': versionDelSdk});
    });

    test('se reenvía sólo si nunca se mandó o se mandó con otra versión del SDK', () {
      expect(hayQueReenviarElAparato(null), isTrue);
      expect(hayQueReenviarElAparato('0.0.1'), isTrue);
      expect(hayQueReenviarElAparato(versionDelSdk), isFalse);
    });
  });
}
