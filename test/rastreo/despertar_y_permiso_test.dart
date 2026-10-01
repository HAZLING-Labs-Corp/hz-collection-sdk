import 'package:flutter_test/flutter_test.dart';
import 'package:hz_collection_sdk/hz_collection_sdk.dart';

void main() {
  test('CL-37 · despertar por acelerómetro: por omisión 3 s y 1,0 m/s²; el servidor manda y se acota', () {
    final omision = ConfiguracionDeRastreo.fromJson({'activo': true});
    expect((omision.despertarSeg, omision.despertarAceleracion), (3, 1.0));
    final c = ConfiguracionDeRastreo.fromJson({
      'activo': true,
      'despertar': {'seg': 5, 'aceleracion': 1.5},
    });
    expect((c.despertarSeg, c.despertarAceleracion), (5, 1.5));
    final loco = ConfiguracionDeRastreo.fromJson({
      'despertar': {'seg': 0, 'aceleracion': 0},
    });
    expect(loco.despertarSeg, 1, reason: 'piso: no puede ser 0 s');
    expect(loco.despertarAceleracion, 0.3);
    final ida = ConfiguracionDeRastreo.fromJson(c.toJson());
    expect((ida.despertarSeg, ida.despertarAceleracion), (5, 1.5));
  });

  test('CL-36 · permiso de ubicación: por omisión al abrir, con pregunta blanda y textos de ubicación', () {
    final p = ConfiguracionDeRastreo.fromJson({'activo': true}).permiso;
    expect(p.momento, MomentoDelPermiso.arranque);
    expect(p.preguntaBlanda, isTrue);
    expect(p.textos.titulo, contains('recorrido'));
    final mandado = ConfiguracionDeRastreo.fromJson({
      'permiso': {
        'momento': 'laAppDecide',
        'preguntaBlanda': false,
        'reintentarCadaDias': 3,
        'textos': {'titulo': 'Tu ruta', 'cuerpo': 'Para tu póliza'},
      },
    }).permiso;
    expect(mandado.momento, MomentoDelPermiso.laAppDecide);
    expect(mandado.preguntaBlanda, isFalse);
    expect(mandado.reintentarCadaDias, 3);
    expect(mandado.textos.titulo, 'Tu ruta');
    expect(mandado.textos.aceptar, contains('registrar'), reason: 'lo que falta cae a los de ubicación');
    expect(ConfiguracionDeRastreo.fromJson(mandado.toJson().isEmpty ? null : {'permiso': mandado.toJson()}).permiso.textos.titulo, 'Tu ruta');
  });
}
