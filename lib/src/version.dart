/// LA VERSIÓN DE ESTE SDK — una constante, generada de `pubspec.yaml`.
///
/// 🔴 EXISTE PORQUE NADIE SABÍA CON QUÉ SDK ESTABA CORRIENDO CADA APP. Lo pidió Juan el
/// 2026-09-11: *«me tienes que decir la última versión del SDK… para mapear cuál es la versión
/// del SDK con que está trabajando la aplicación, o ha trabajado. Eso no lo hemos marcado por
/// ahí»*. Y tenía razón: medido ese día, lo único que viajaba era `appVersion`, que es la versión
/// de **la aplicación del comercio**, no la nuestra. Dos cosas distintas con nombres parecidos.
///
/// Sin esto, la pregunta que de verdad importa cuando algo no llega —*«¿este teléfono tiene el
/// SDK que ya trae el arreglo?»*— no tiene respuesta, y hay que adivinarla por la fecha.
///
/// ── 🔴 POR QUÉ UNA CONSTANTE Y NO LEER `pubspec.yaml` EN CALIENTE ──────────────
///
/// Porque en un binario compilado el `pubspec.yaml` no existe: es un archivo del proyecto, no del
/// paquete instalado. Leerlo funcionaría en desarrollo y devolvería vacío en la calle, que es la
/// peor combinación posible — anda donde se prueba y falla donde importa.
///
/// ⚠️ **Se actualiza a mano al publicar, junto con `pubspec.yaml`.** Lo verifica
/// `bin/verificar-version.dart`, que compara los dos y falla si no coinciden: una constante que
/// se olvida de actualizar miente con total seguridad, que es peor que no tenerla.
library;

/// La versión del SDK, igual que la de `pubspec.yaml`.
const String versionDelSdk = '0.3.0';
