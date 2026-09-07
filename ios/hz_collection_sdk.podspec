#
# El lado iOS del SDK. Existe por una razón concreta: hasta hoy el paquete declaraba
# SOLO la plataforma android, así que en iPhone el canal de señales no tenía a nadie
# escuchando y el módulo devolvía vacío. Medido el 2026-09-01: de 95 campos, cero.
#
# 🔴 NO SE DECLARA NINGÚN PERMISO ACÁ, igual que en el manifiesto de Android. Todo lo que
# mide este plugin es de nivel 0: no muestra un diálogo ni pide nada. El día que algo
# necesite un permiso, va en el Info.plist de LA APLICACIÓN que instala el SDK, con su
# texto, y no acá — para que la ficha de la App Store no se ensucie por nuestra culpa.
#
Pod::Spec.new do |s|
  s.name             = 'hz_collection_sdk'
  s.version          = '0.0.1'
  s.summary          = 'Señales de nivel 0 para iOS.'
  s.description      = 'El lado nativo de iOS del SDK de Collection: mide señales que no piden ningún permiso.'
  s.homepage         = 'https://hazling.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Hazling' => 'juan@hazling.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '12.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
