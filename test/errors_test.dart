import 'package:hz_collection_sdk/hz_collection_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AkPushError', () {
    test('solo son reintentables los que mejoran esperando', () {
      expect(AkPushError(AkPushErrorCode.network, 'x').retryable, isTrue);
      expect(AkPushError(AkPushErrorCode.serviceUnavailable, 'x').retryable, isTrue);
    });

    test('un dato mal no se arregla reintentando', () {
      for (final c in [
        AkPushErrorCode.unauthorized,
        AkPushErrorCode.appMismatch,
        AkPushErrorCode.permissionDenied,
        AkPushErrorCode.firebaseInit,
        AkPushErrorCode.notInitialized,
        AkPushErrorCode.firmaDeIdentidad,
        AkPushErrorCode.rutaNoEncontrada,
      ]) {
        expect(AkPushError(c, 'x').retryable, isFalse, reason: c.name);
      }
    });

    test('el detalle acompaña al mensaje', () {
      final e = AkPushError(
        AkPushErrorCode.appMismatch,
        'No coincide',
        details: 'registrado com.acme.app',
      );
      expect(e.toString(), contains('appMismatch'));
      expect(e.toString(), contains('registrado com.acme.app'));
    });
  });
}
