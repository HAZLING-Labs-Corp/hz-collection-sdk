# Herramientas

## `simulador-de-servicio.js`

El receptor de mentira que se usó para medir la política de transmisión. **Cuenta peticiones y
bytes**, que es lo que ninguna prueba unitaria puede decir: si el SDK llama una vez o veinte, y
cuánto sube.

```bash
node herramientas/simulador-de-servicio.js      # queda escuchando en 3086
```

Su panel:

| | |
|---|---|
| `GET /__conteo` | cuántas peticiones y cuántos bytes van |
| `POST /__reset?corrida=X` | empezar a contar de nuevo |
| `POST /__red?estado=caida` | simular que no hay red, para ver qué hace la cola |

**No toca ninguna base ni manda nada real.** Se guarda acá porque vivía en un directorio temporal
de sesión y con él se perdían los números: sin el instrumento, la medición de `5 → 4 llamadas` y
`3.906 → 1.050 bytes` no se puede repetir.
