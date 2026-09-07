import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// El identificador del paquete se puede pasar al compilar:
//   flutter run -Ppaquete=com.tuempresa.app
//
// Está así porque el servicio verifica que el paquete que pide la configuración
// esté registrado en tu comercio: con otro devuelve 409. Sin esto, cualquiera
// que clone el repositorio tiene que editar tres archivos antes de poder correr
// el ejemplo — y el que no lea el README se topa con un 409 que no explica nada.
val paqueteDeLaApp = (project.findProperty("paquete") as String?)
    ?: "com.juanpush.android1"

// El nombre que se lee bajo el ícono, por el mismo motivo que el paquete:
//   flutter run -Pnombre=Rodar
// Va como placeholder del manifiesto porque `android:label` se resuelve al empaquetar y no
// puede leer un `--dart-define`, que sólo existe dentro de Dart.
val nombreDeLaApp = (project.findProperty("nombre") as String?)
    ?: "Collection"

// 🔴 LA FIRMA DE RELEASE.
//
// Un APK de release firmado con la llave de DEPURACIÓN se instala en un emulador y se
// atasca en un teléfono de verdad: Play Protect lo bloquea con «no se pudo instalar», sin
// decir por qué. Eso pasó, y perdió una tarde.
//
// La llave vive fuera del repositorio, en `android/key.properties`, que está ignorado: una
// llave de firma en git es una llave que cualquiera con el repositorio puede usar para
// publicar algo con TU identidad de aplicación.
//
// Si el archivo no está, se sigue firmando con la de depuración y se avisa al compilar —
// en vez de fallar la construcción de alguien que sólo quiere correr el ejemplo.
val propiedadesDeFirma = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) FileInputStream(f).use { load(it) }
}
val hayFirmaPropia = propiedadesDeFirma.getProperty("storeFile") != null

android {
    namespace = paqueteDeLaApp
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Lo exige flutter_local_notifications, que es lo que dibuja el aviso
        // cuando la app está abierta. Sin esto la compilación falla con
        // "requires core library desugaring to be enabled".
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = paqueteDeLaApp
        manifestPlaceholders["nombreDeLaApp"] = nombreDeLaApp
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (hayFirmaPropia) {
                keyAlias = propiedadesDeFirma.getProperty("keyAlias")
                keyPassword = propiedadesDeFirma.getProperty("keyPassword")
                storeFile = file(propiedadesDeFirma.getProperty("storeFile"))
                storePassword = propiedadesDeFirma.getProperty("storePassword")

                // 🔴 LOS TRES ESQUEMAS DE FIRMA, Y ESPECIALMENTE EL v1.
                //
                // Con `minSdk 24` Android Gradle apaga el v1 (JAR) por su cuenta: da por
                // hecho que todo lo que corre Android 7 o más entiende el v2. No es cierto
                // para los instaladores de varios fabricantes —Xiaomi, Huawei, Samsung con
                // versiones viejas— que siguen exigiendo el v1 y rechazan el paquete con un
                // «no se pudo instalar la aplicación» que no dice nada más.
                //
                // Se instala perfecto en un emulador y falla en un teléfono de verdad, que
                // es la peor forma de fallar: parece que el APK está bien.
                enableV1Signing = true
                enableV2Signing = true
                enableV3Signing = true
            }
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = if (hayFirmaPropia) {
                signingConfigs.getByName("release")
            } else {
                logger.warn("⚠️  Sin android/key.properties: el APK de release va firmado " +
                    "con la llave de DEPURACIÓN y un teléfono real puede negarse a instalarlo.")
                signingConfigs.getByName("debug")
            }
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
