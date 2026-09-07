import 'package:hz_collection_sdk/hz_collection_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t = DateTime(2026, 8, 30, 18);

  group('el punto del embudo', () {
    test('nunca se le preguntó', () {
      expect(const Consentimiento().punto, 'sin_preguntar');
    });

    test('dijo «ahora no» en el modal — el del sistema no se gastó', () {
      final c = const Consentimiento().conModal(acepto: false, cuando: t);
      expect(c.punto, 'dijo_ahora_no');
      expect(c.sistemaRespondioEl, isNull,
          reason: 'el diálogo del sistema nunca llegó a mostrarse');
    });

    test('🔴 dijo que sí al modal y que NO al del sistema', () {
      // Es el caso que motivó separar las dos preguntas. Con un solo campo
      // «se le preguntó», esta persona quedaba marcada igual que quien nunca
      // vio nada — y son situaciones opuestas.
      final c = const Consentimiento()
          .conModal(acepto: true, cuando: t)
          .conSistema(acepto: false, cuando: t);
      expect(c.punto, 'denego_en_el_sistema');
      expect(c.aceptoElModal, isTrue, reason: 'al modal le dijo que sí');
      expect(c.acepto, isFalse, reason: 'pero al sistema le dijo que no');
    });

    test('aceptó las dos', () {
      final c = const Consentimiento()
          .conModal(acepto: true, cuando: t)
          .conSistema(acepto: true, cuando: t);
      expect(c.punto, 'acepto');
    });

    test('dijo que sí al modal y el sistema todavía no contestó', () {
      expect(const Consentimiento().conModal(acepto: true, cuando: t).punto,
          'esperando_al_sistema');
    });
  });

  group('volver a preguntar', () {
    test('una respuesta nueva al modal descarta la del sistema anterior', () {
      // Empieza un intento nuevo: lo que el sistema contestó la vez pasada ya no
      // describe a ésta, y dejarlo haría que el punto mintiera.
      final c = const Consentimiento()
          .conModal(acepto: true, cuando: t)
          .conSistema(acepto: false, cuando: t)
          .conModal(acepto: true, cuando: t.add(const Duration(days: 8)));
      expect(c.acepto, isNull);
      expect(c.punto, 'esperando_al_sistema');
    });
  });

  group('sobrevive al disco', () {
    test('ida y vuelta sin perder nada', () {
      final ida = const Consentimiento()
          .conModal(acepto: true, cuando: t)
          .conSistema(acepto: false, cuando: t);
      final vuelta = Consentimiento.fromJson(ida.toJson());
      expect(vuelta.punto, ida.punto);
      expect(vuelta.aceptoElModal, ida.aceptoElModal);
      expect(vuelta.acepto, ida.acepto);
    });

    test('un guardado ilegible no rompe: se empieza de cero', () {
      expect(Consentimiento.fromJson(null).punto, 'sin_preguntar');
    });
  });
}
