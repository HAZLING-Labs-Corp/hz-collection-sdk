/// LOS PROPÓSITOS — para qué sirve cada señal, en una lista limpia y corta.
/// ═══════════════════════════════════════════════════════════════════════════════
///
/// 🔴 POR QUÉ ESTO EXISTE, Y POR QUÉ NO REEMPLAZA A LA CATEGORÍA.
///
/// La **categoría** de una señal es lo que el catálogo escribe antes de los dos puntos en
/// `paraQue` — «Antifraude alto», «Autenticidad leve», «Puntaje (NBER)»—. Nació como un matiz
/// para quien lee la ficha, y quedó siendo la llave de los pesos: el portón sólo mira las que
/// empiezan por `Antifraude` o `Autenticidad`, y elegibilidad pesa por `Alcance`, `Perfil`,
/// `Antigüedad` y `Puntaje`, cada una con su número.
///
/// Medido el 2026-09-11 sobre los 125 campos: hay **26 categorías distintas**, y seis de ellas
/// no son categorías sino restos de una frase sin dos puntos — una dice literalmente «Igual que
/// la versión, en número, para comparar con precisión.».
///
/// Juan pidió configurar la app **por categoría y según el rubro**, que es lo correcto: el grupo
/// —`hd_`, `acc_`— dice de qué habla la señal, y la categoría dice para qué sirve, que es lo que
/// se conecta con a qué se dedica el comercio. Pero ofrecerle 26 opciones, seis de ellas basura,
/// sería peor que los grupos.
///
/// 🔴 Y NO SE PUEDEN FUSIONAR LAS CRUDAS. Juntar `Antigüedad` dentro de `Perfil` cambiaría el
/// peso de esa señal y con él el puntaje de personas reales. Un cambio de presentación no puede
/// mover un número que decide sobre alguien.
///
/// Por eso el propósito es una capa **de arriba**: agrupa para mostrar y elegir, y la categoría
/// cruda sigue mandando en el cálculo, intacta.
library;

/// Un propósito: cómo se llama, y qué gana el comercio que lo prende.
class Proposito {
  final String clave;
  final String titulo;

  /// Qué decide prender esto, en las palabras de quien administra un comercio. No qué mide:
  /// qué le sirve.
  final String paraQueLeSirve;

  const Proposito(this.clave, this.titulo, this.paraQueLeSirve);
}

const List<Proposito> propositos = [
  Proposito('antifraude', 'Detectar fraude',
      'Si el aparato está manipulado, emulado o controlado a distancia. Es lo que separa a una '
      'persona de una granja de teléfonos.'),
  Proposito('autenticidad', 'Comprobar que el aparato es real',
      'Si el teléfono es un teléfono y la aplicación se instaló desde la tienda. Es la base de '
      'todo lo demás: sobre un aparato falso, ninguna otra señal significa nada.'),
  Proposito('alcance', 'Poder llegarle a la persona',
      'Si hoy se le puede escribir y por dónde. Sin esto, una campaña se manda a gente que no '
      'la va a recibir.'),
  Proposito('puntaje', 'Estimar su riesgo de crédito',
      'Las señales que se relacionan con cómo paga. Es lo que alimenta los motores de cartera '
      'cuando todavía no hay historial propio.'),
  Proposito('perfil', 'Saber con quién está hablando',
      'Gama del aparato, antigüedad, idioma. Sirve para segmentar y para entender a quién se '
      'le está ofreciendo algo.'),
  Proposito('comportamiento', 'Ver cómo usa la aplicación',
      'Qué hace adentro y cuándo. Es lo que permite avisarle en el momento en que está por '
      'hacer algo, y no seis horas después.'),
  Proposito('contexto', 'Entender la medición',
      'Cuándo se midió, con qué versión, si los datos son coherentes entre sí. No dice nada de '
      'la persona: dice si lo demás se puede creer.'),
];

/// De la categoría cruda del catálogo al propósito.
///
/// 🔴 SE ESCRIBE ENTERA Y SE COMPRUEBA. `bin/verificar-propositos.dart` recorre los 125 campos y
/// falla si aparece una categoría que no está acá. Sin ese control, una señal nueva entraría con
/// su categoría propia y **desaparecería de la pantalla de configuración** sin ningún error: el
/// comercio no la vería, no podría apagarla, y se seguiría midiendo.
const Map<String, String> propositoDeLaCategoria = {
  'Antifraude': 'antifraude',
  'Antifraude clásico': 'antifraude',
  'Antifraude alto': 'antifraude',
  'Antifraude clave': 'antifraude',
  'Autenticidad': 'autenticidad',
  'Autenticidad leve': 'autenticidad',
  'Autenticidad y perfil': 'autenticidad',
  'Autenticidad, la base de todo': 'autenticidad',
  'Alcance': 'alcance',
  'Alcance y perfil': 'alcance',
  'Entregabilidad': 'alcance',
  'Entregabilidad clave': 'alcance',
  'Puntaje': 'puntaje',
  'Puntaje (NBER)': 'puntaje',
  'Puntaje y antigüedad': 'puntaje',
  'Riesgo': 'puntaje',
  'Perfil': 'perfil',
  'Antigüedad': 'perfil',
  'Segmentación': 'perfil',
  'Comportamiento': 'comportamiento',
  'Actividad y momento': 'comportamiento',
  'Contexto': 'contexto',
  'Coherencia': 'contexto',
  'Coherencia y segmentación': 'contexto',
  'Señal': 'contexto',
  // 🔴 Ésta no es una categoría: es un `paraQue` sin dos puntos, así que la frase entera quedó
  // como categoría. Se mapea para que el control no falle por algo que ya estaba mal, y se
  // deja anotado que lo que hay que arreglar es la ficha de ese campo, no esta tabla.
  'Igual que la versión, en número, para comparar con precisión.': 'contexto',
};

/// La categoría cruda de un campo: lo que está antes de los dos puntos en `paraQue`.
///
/// Misma regla que `categoriaDe` en el servicio del portón, y a propósito: si las dos leyeran
/// distinto, la pantalla mostraría una agrupación y el cálculo usaría otra.
String categoriaCruda(String? paraQue) {
  final t = (paraQue ?? '').trim();
  final i = t.indexOf(':');
  return (i == -1 ? t : t.substring(0, i)).trim();
}

/// El propósito de un campo. `null` si su categoría no está mapeada — que es exactamente lo que
/// el control busca.
String? propositoDe(String? paraQue) => propositoDeLaCategoria[categoriaCruda(paraQue)];
