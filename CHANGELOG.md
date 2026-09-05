## 0.2.0 — SOL-002 · comportamiento propio y política de transmisión

**Todo es aditivo. Nada de lo que andaba dejó de andar:** las 223 pruebas del paquete pasan, el
muro de permisos sigue limpio —el módulo nuevo **no declara ni un permiso**— y el catálogo se
sigue generando igual.

### Se mide el comportamiento dentro de la propia aplicación

Sesión (cuándo abre, cuándo cierra, cuánto duró, a qué hora local), formulario (cuándo lo abre,
cuánto tarda en enviarlo, cuántas veces lo abandona y vuelve) y campos (si pega el dato o lo
escribe, y cuántas veces lo corrige). Siete tipos de evento, los del contrato del 2026-09-04.

🔴 **El contenido de lo que la persona escribe NO se captura, y es un límite duro.** Ni el texto,
ni su largo, ni un hash de él. Hay una prueba que lo comprueba con una cédula de verdad.

### La política de transmisión

|  | antes | ahora |
|---|---|---|
| cuándo se mide | al abrir | al abrir |
| cuándo se transmite | **en el mismo acto de medir** | por lote, al abrir |
| qué dispara un envío | **nada: siempre** | sólo un cambio real (10 señales de momento no cuentan) |
| sin conexión | **se perdía** | hasta 1.000 eventos ó 512 KB, se descarta lo más viejo |
| resincronización | **no había** | todo igual cada 7 días |

Medido en el emulador contra un simulador que cuenta peticiones, misma sesión repetida:
**5 llamadas y 3.906 bytes → 4 llamadas y 1.050 bytes.** Las mediciones de señales pasaron de 2
por sesión a 0 mientras el teléfono no cambia, y vuelven en cuanto cambia algo de verdad.

Se vuelve al comportamiento anterior en una línea:
`AkPush.init(…, politicaDeTransmision: PoliticaDeTransmision.comoEstabaAntes)`.

### Un hallazgo del camino

`hd_ram_libre_mb` y `hd_ram_en_las_ultimas` **no están en `SENALES_DE_MOMENTO` del servicio y
tendrían que estar.** Con el delta andando, una sesión sin tocar nada seguía transmitiendo las
105 señales por culpa de uno solo de esos dos campos. Quedan en
`momentosQueElBackTodaviaNoTiene`, aparte de los diez del servicio, hasta que se agreguen allá.

### Superficie nueva

`AkPush.formulario(…)` · `AkPush.estadoDelComportamiento()` ·
`AkPush.transmitirComportamiento()` · `AkPush.politicaDeTransmision` ·
`AkPush.ultimasDecisiones`

## 0.0.1

* TODO: Describe initial release.
