import 'package:hz_collection_sdk/hz_collection_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PushMessage', () {
    test('pushLogId es lo que habilita la medición', () {
      const sinId = PushMessage(data: {});
      expect(sinId.pushLogId, isNull);

      const conId = PushMessage(data: {'pushLogId': '6a94'});
      expect(conId.pushLogId, '6a94');
    });

    test('reconoce el código del aviso y la señal', () {
      const m = PushMessage(data: {'code_event': 'NC-9', 'type': 'PAGARE_PENDING'});
      expect(m.codeEvent, 'NC-9');
      expect(m.signal, 'PAGARE_PENDING');
    });

    test('un aviso sin nada de eso no rompe nada', () {
      const m = PushMessage(data: {}, title: 'Hola');
      expect(m.pushLogId, isNull);
      expect(m.codeEvent, isNull);
      expect(m.signal, isNull);
      expect(m.title, 'Hola');
    });
  });
}
