/// CADA CUÁNTO SE VUELVE A MEDIR EL APARATO — la decisión, sola y pura.
///
/// ═══════════════════════════════════════════════════════════════════════════════
///
/// 🔴 POR QUÉ EXISTE ESTE ARCHIVO, MEDIDO Y NO SUPUESTO.
///
/// Hasta el 2026-09-06 los módulos corrían **una sola vez, al iniciar sesión**. Mirando la base
/// de un comercio real aparecieron tres personas: una con 127 señales y **dos con 18** — sólo el
/// bloque básico del aparato, ninguna de las 109 de los módulos. Los tres motores decían «0 de
/// 38 reglas evaluables» sobre esas dos, para siempre, y la consola lo mostraba como «no sumó
/// puntos», que se lee como que las miramos y salieron mal.
///
/// La causa quedó a la vista en el registro de otro comercio, donde el barrido sí se completó:
///
///     18:18:28    18 campos   primera_vez
///     18:18:58   107 campos   cambio        ← treinta segundos después
///
/// La medición llega en dos tandas. Si la segunda no sale —la aplicación se cerró, se cambió de
/// comercio, el canal nativo devolvió vacío— **no había una tercera oportunidad nunca**.
///
/// ── Y LA OTRA MITAD, QUE ES LA PREGUNTA DE JUAN ────────────────────────────────
///
///   *«El dispositivo puede estar hoy con la pantalla prendida, pero mañana apagada, o en cinco
///   minutos cambió. ¿Cómo manejo eso?»*
///
/// Con una sola medición en la vida, la consola muestra el estado del día en que la persona se
/// registró y lo muestra como si fuera el de ahora. Las señales no envejecen todas igual —la
/// marca del teléfono no cambia nunca, la pantalla encendida cambia en segundos— pero el
/// barrido sí es uno solo, así que la cadencia se fija por el que más se mueve.
library;

/// Cada cuánto se vuelve a medir cuando el barrido anterior estuvo bien.
///
/// 🔴 Quince minutos es donde empatan las dos cosas que se pelean: por debajo se gasta radio y
/// batería reescribiendo señales que no cambiaron; por encima, el estado que muestra la consola
/// envejece más de lo que alguien toleraría al abrir una ficha. No es un número sagrado — es el
/// que se puede defender, y está en un solo lugar para poder discutirlo.
const Duration cadaCuantoSeRemide = Duration(minutes: 15);

/// Cada cuánto se reintenta cuando el barrido anterior quedó corto.
///
/// Mucho más seguido, y a propósito: un barrido corto no es un estado válido que haya que
/// respetar, es un accidente que hay que corregir antes de que esa persona quede inevaluable.
const Duration cadaCuantoSeReintenta = Duration(minutes: 1);

/// Por debajo de cuántos campos se considera que el barrido quedó corto.
///
/// 🔴 Cuarenta y no cero. Cero sólo atraparía el caso en que no llegó absolutamente nada, y el
/// caso real es peor y más silencioso: llegan los 18 del bloque básico y ninguno de los módulos.
/// Un aparato con los módulos andando entrega más de cien; el corte queda holgado por arriba de
/// lo básico y muy por debajo de lo normal, así que no se dispara con un iPhone —que mide menos
/// por plataforma— ni deja pasar el bloque básico solo.
const int camposQueDelatanUnBarridoCorto = 40;

/// ¿Toca volver a medir?
///
/// Pura a propósito: no toca el reloj del sistema ni la fachada, así que la decisión se prueba
/// sin montar una aplicación de Flutter. Es la misma regla que el resto del proyecto aplica a
/// todo lo que decide algo.
///
/// - [ultimoBarrido] en `null` significa que nunca se midió: siempre toca.
/// - [camposDelUltimoBarrido] es cuántos entregó, no cuántos se transmitieron. La política de
///   transmisión puede callarse con razón un barrido perfecto, y eso no lo hace corto.
bool tocaRemedir({
  required DateTime ahora,
  DateTime? ultimoBarrido,
  required int camposDelUltimoBarrido,
}) {
  if (ultimoBarrido == null) return true;
  final pasado = ahora.difference(ultimoBarrido);
  final quedoCorto = camposDelUltimoBarrido < camposQueDelatanUnBarridoCorto;
  return pasado >= (quedoCorto ? cadaCuantoSeReintenta : cadaCuantoSeRemide);
}
