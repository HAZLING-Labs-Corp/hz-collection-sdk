/// LOS VEHÍCULOS VISTOS DESDE ARRIBA — los mismos que dibuja la consola web
/// (`src/components/flota/vehiculos.ts`). Juan, 2026-10-01: «no quiero una moto dentro de un
/// círculo. Quiero que parezca realmente una motico del tamaño de las calles. Algo delicado,
/// bonito, con color».
///
/// Apuntan hacia arriba (rumbo 0°) en un cuadro de 48×48; quien los usa los gira con el rumbo y
/// los escala con el zoom ([escalaPorZoom]) para que vayan del ancho de la calle.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// El tamaño según el zoom: a zoom 17 la moto mide unos 29 px de largo (40 era «burda grande» y
/// 20 «burda pequeñita», Juan, 2026-10-01). Los mismos escalones que la consola.
double escalaPorZoom(double zoom) {
  const escalones = <(double, double)>[(12, 0.4), (15, 0.5), (16, 0.6), (17, 0.72), (18, 1.05), (19, 1.55), (20, 2.2)];
  if (zoom <= escalones.first.$1) return escalones.first.$2;
  for (var i = 1; i < escalones.length; i++) {
    final (z1, e1) = escalones[i - 1];
    final (z2, e2) = escalones[i];
    if (zoom <= z2) return e1 + (e2 - e1) * (zoom - z1) / (z2 - z1);
  }
  return escalones.last.$2;
}

enum Vehiculo { moto, carro }

/// ¿El medio del perfil se dibuja como vehículo? Si no, es una persona.
Vehiculo? vehiculoDe(String? medio) => switch (medio) {
      'dosRuedas' || 'bici' => Vehiculo.moto,
      'carro' || 'bus' => Vehiculo.carro,
      _ => null,
    };

class PintorDeVehiculo extends CustomPainter {
  const PintorDeVehiculo(this.vehiculo);
  final Vehiculo vehiculo;

  static const lado = 48.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / lado, size.height / lado);
    canvas.translate(lado / 2, lado / 2);
    switch (vehiculo) {
      case Vehiculo.moto:
        _moto(canvas);
      case Vehiculo.carro:
        _carro(canvas);
    }
    canvas.restore();
  }

  RRect _rr(double cx, double cy, double w, double h, double r) =>
      RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(cx, cy), width: w, height: h), Radius.circular(r));

  Shader _lomo(double ancho, Color borde, Color centro) =>
      LinearGradient(colors: [borde, centro, borde]).createShader(Rect.fromLTWH(-ancho / 2, -24, ancho, 48));

  void _sombra(Canvas c, double w, double h, double r) {
    c.drawRRect(
      _rr(1, 2, w, h, r),
      Paint()
        ..color = const Color(0x55000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.2),
    );
  }

  void _moto(Canvas c) {
    _sombra(c, 11, 38, 5);
    final llanta = Paint()..color = const Color(0xFF1F2124);
    c.drawRRect(_rr(0, 15.5, 5.6, 10, 2.6), llanta);
    c.drawRRect(_rr(0, -15.5, 5, 9, 2.4), llanta);
    final cuerpo = Path()
      ..moveTo(0, -13.5)
      ..cubicTo(4.5, -12, 5.6, -6, 5.2, -2)
      ..cubicTo(5, 4, 4.4, 9, 3, 13.5)
      ..lineTo(-3, 13.5)
      ..cubicTo(-4.4, 9, -5, 4, -5.2, -2)
      ..cubicTo(-5.6, -6, -4.5, -12, 0, -13.5)
      ..close();
    c.drawPath(cuerpo, Paint()..shader = _lomo(11, const Color(0xFFB3261E), const Color(0xFFFF5A4E)));
    c.drawPath(cuerpo, Paint()..style = PaintingStyle.stroke..strokeWidth = 0.6..color = const Color(0x73500000));
    c.drawOval(Rect.fromCenter(center: const Offset(0, -13.6), width: 4.2, height: 2.2), Paint()..color = const Color(0xFFFFF6CC));
    c.drawRRect(_rr(0, 13.4, 4.2, 1.3, 0.6), Paint()..color = const Color(0xFFFF1744));
    c.drawRRect(_rr(0, 8.6, 5.4, 6, 2.4), Paint()..color = const Color(0xFF26282B));
    final manubrio = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.5
      ..color = const Color(0xFF3C4247);
    c.drawPath(Path()..moveTo(-8, -8.6)..quadraticBezierTo(0, -10.4, 8, -8.6), manubrio);
    final puno = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2
      ..color = const Color(0xFF111111);
    c.drawLine(const Offset(-8.4, -8.4), const Offset(-6.8, -8.9), puno);
    c.drawLine(const Offset(8.4, -8.4), const Offset(6.8, -8.9), puno);
    final espejo = Paint()..color = const Color(0xFFA7B3BB);
    c.drawCircle(const Offset(-7.6, -11), 1.2, espejo);
    c.drawCircle(const Offset(7.6, -11), 1.2, espejo);
    final brazo = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.3
      ..color = const Color(0xFF263238);
    c.drawPath(Path()..moveTo(-5, 0)..quadraticBezierTo(-7, -4, -7.2, -8.4), brazo);
    c.drawPath(Path()..moveTo(5, 0)..quadraticBezierTo(7, -4, 7.2, -8.4), brazo);
    c.drawOval(Rect.fromCenter(center: const Offset(0, 1.4), width: 12.8, height: 7.6),
        Paint()..shader = _lomo(13, const Color(0xFF1C262B), const Color(0xFF3F515A)));
    const centroCasco = Offset(0, -1.6);
    c.drawCircle(
      centroCasco,
      4.3,
      Paint()
        ..shader = const RadialGradient(center: Alignment(-0.3, -0.4), colors: [Color(0xFFFFFFFF), Color(0xFFC9D1D6)])
            .createShader(Rect.fromCircle(center: centroCasco, radius: 4.6)),
    );
    c.drawCircle(centroCasco, 4.3, Paint()..style = PaintingStyle.stroke..strokeWidth = 0.6..color = const Color(0x59000000));
    final visera = Path()
      ..addArc(Rect.fromCircle(center: centroCasco, radius: 4.3), math.pi * 1.18, math.pi * 0.64)
      ..lineTo(0, -3.4)
      ..close();
    c.drawPath(visera, Paint()..color = const Color(0xFF1A2A4A));
    c.drawLine(const Offset(0, -3.2), const Offset(0, 2.6), Paint()..strokeWidth = 1.2..color = const Color(0xFFE53935));
  }

  void _carro(Canvas c) {
    _sombra(c, 19, 41, 6.5);
    final llanta = Paint()..color = const Color(0xFF1F2124);
    for (final (x, y) in const [(-9.4, -11.5), (9.4, -11.5), (-9.4, 11.5), (9.4, 11.5)]) {
      c.drawRRect(_rr(x, y, 2.4, 6.4, 1), llanta);
    }
    final carroceria = _rr(0, 0, 18, 40, 6.5);
    c.drawRRect(carroceria, Paint()..shader = _lomo(18, const Color(0xFF0D47A1), const Color(0xFF4F9DF0)));
    c.drawRRect(carroceria, Paint()..style = PaintingStyle.stroke..strokeWidth = 0.6..color = const Color(0x80001440));
    final espejo = Paint()..color = const Color(0xFF1565C0);
    c.drawOval(Rect.fromCenter(center: const Offset(-9.8, -5.6), width: 3.2, height: 2), espejo);
    c.drawOval(Rect.fromCenter(center: const Offset(9.8, -5.6), width: 3.2, height: 2), espejo);
    final vidrio = Paint()
      ..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF2B3A4A), Color(0xFF0F1720)])
          .createShader(const Rect.fromLTWH(-8, -11, 16, 8));
    c.drawPath(
      Path()
        ..moveTo(-7.2, -9.4)
        ..quadraticBezierTo(0, -11.2, 7.2, -9.4)
        ..lineTo(6.3, -3.6)
        ..lineTo(-6.3, -3.6)
        ..close(),
      vidrio,
    );
    c.drawLine(const Offset(-4.6, -8.6), const Offset(-2.4, -4.6), Paint()..strokeWidth = 0.8..color = const Color(0x47FFFFFF));
    c.drawRRect(_rr(0, 2.4, 12.4, 11.4, 2.2), Paint()..shader = _lomo(12.4, const Color(0xFF1259B0), const Color(0xFF3D8CE6)));
    c.drawPath(
      Path()
        ..moveTo(-6.2, 8.4)
        ..lineTo(6.2, 8.4)
        ..lineTo(6.8, 12.6)
        ..quadraticBezierTo(0, 13.6, -6.8, 12.6)
        ..close(),
      vidrio,
    );
    final faro = Paint()..color = const Color(0xFFFFF6CC);
    c.drawOval(Rect.fromCenter(center: const Offset(-5.6, -19), width: 4.4, height: 2), faro);
    c.drawOval(Rect.fromCenter(center: const Offset(5.6, -19), width: 4.4, height: 2), faro);
    final freno = Paint()..color = const Color(0xFFE53935);
    c.drawRRect(_rr(-5.6, 19.2, 4, 1.2, 0.5), freno);
    c.drawRRect(_rr(5.6, 19.2, 4, 1.2, 0.5), freno);
  }

  @override
  bool shouldRepaint(covariant PintorDeVehiculo old) => old.vehiculo != vehiculo;
}
