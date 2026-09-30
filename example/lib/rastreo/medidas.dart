import 'package:flutter/widgets.dart';

/// LAS MEDIDAS DE LA PANTALLA DE RASTREO — el único lugar con números de píxeles.
///
/// Misma regla que `core/theme/app_sizes.dart` de la casa: base 375 px de ancho, escala
/// entre 0,85 y 1,3. Escala el diseño dentro de un tamaño de aparato; no lo cambia.
class Medidas {
  Medidas._(this._f);
  final double _f;

  factory Medidas.de(BuildContext context) {
    final ancho = MediaQuery.sizeOf(context).width;
    return Medidas._((ancho / 375).clamp(0.85, 1.3));
  }

  double get xs => 4 * _f;
  double get s => 8 * _f;
  double get m => 12 * _f;
  double get l => 16 * _f;
  double get xl => 24 * _f;
  double get radio => 12 * _f;
  double get icono => 20 * _f;
  double get botonAlto => 48 * _f;

  /// El ancho máximo del contenido en una tableta: más ancho que esto, una línea de
  /// diagnóstico se vuelve ilegible.
  double get anchoMaximo => 640 * _f;
}

extension MedidasDeContexto on BuildContext {
  Medidas get medidas => Medidas.de(this);
}
