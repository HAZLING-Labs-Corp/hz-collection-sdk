/**
 * SIMULADOR DEL SERVICIO DE COLLECTION — para MEDIR, no para servir.
 *
 * Contesta exactamente las rutas que llama el SDK, con las mismas formas que devuelve
 * `hz-collection-tiers-back`, y CUENTA cada petición. Existe por tres razones:
 *
 *  1. El número de llamadas de red por sesión es lo que hay que demostrar, y contra el back
 *     de verdad ese número hay que deducirlo de los registros. Acá se cuenta exacto.
 *  2. `POST /api/v1/comportamiento` todavía no existe del lado del back — lo está
 *     construyendo otro frente esta misma noche. Acá está, tal cual el contrato.
 *  3. Se puede tirar la red a voluntad (`/__red`) sin tocar el emulador, que es como se
 *     prueba la cola sin conexión en dos segundos en vez de en dos minutos.
 *
 * No toca ninguna base. No guarda nada fuera de este directorio.
 */
const http = require('http');
const fs = require('fs');
const path = require('path');

const PUERTO = Number(process.env.PUERTO || 3086);
const DIR = __dirname;
const BITACORA = path.join(DIR, 'peticiones.jsonl');
const EVENTOS = path.join(DIR, 'comportamiento.jsonl');

let red = 'arriba';
let contador = Object.create(null);
let corrida = 'sin-nombre';

/**
 * El catálogo, calcado de `src/modulos/catalogo.ts` del back. Se copia tal cual —
 * incluido que `aparato` NO está — porque el simulador tiene que mentir lo menos posible:
 * si acá se activara un módulo que el back no tiene, la medición diría que el SDK hace una
 * llamada que en la vida real no hace.
 */
const MODULOS = {
  avisos:       { nivel: 1, cadencia: 'evento',    permisos: ['POST_NOTIFICATIONS'],    estado: 'activo' },
  ubicacion:    { nivel: 1, cadencia: 'periodica', permisos: ['ACCESS_COARSE_LOCATION'], estado: 'activo' },
  senales:      { nivel: 0, cadencia: 'episodica', permisos: [],                        estado: 'activo' },
  autenticidad: { nivel: 0, cadencia: 'episodica', permisos: [],                        estado: 'activo' },
  rastreo:      { nivel: 3, cadencia: 'continua',  permisos: ['ACCESS_BACKGROUND_LOCATION'], estado: 'declarado' }
};

/**
 * Una configuración de Firebase con la FORMA correcta y valores inventados. Alcanza para
 * que `Firebase.initializeApp` no reviente —no valida contra la red— y el token queda en
 * nulo, que es un estado que el SDK ya sabe manejar.
 */
const FIREBASE = {
  projectId: 'collection-simulador',
  appId: '1:123456789012:android:0123456789abcdef012345',
  apiKey: 'AIzaSySimuladorLocalNoEsUnaLlaveDeVerdad',
  messagingSenderId: '123456789012'
};

function anotar(req, bytes) {
  const clave = `${req.method} ${req.url.split('?')[0]}`;
  contador[clave] = (contador[clave] || 0) + 1;
  fs.appendFileSync(BITACORA, JSON.stringify({
    corrida, t: new Date().toISOString(), metodo: req.method,
    ruta: req.url.split('?')[0], bytes
  }) + '\n');
}

function json(res, codigo, cuerpo) {
  const texto = JSON.stringify(cuerpo);
  res.writeHead(codigo, { 'content-type': 'application/json' });
  res.end(texto);
}

const servidor = http.createServer((req, res) => {
  let crudo = '';
  req.on('data', (c) => { crudo += c; });
  req.on('end', () => {
    const ruta = req.url.split('?')[0];

    // ── El panel de control del simulador. No cuenta como tráfico del SDK ──────────
    if (ruta === '/__conteo') {
      return json(res, 200, { corrida, red, total: Object.values(contador).reduce((a, b) => a + b, 0), por_ruta: contador });
    }
    if (ruta === '/__reset') {
      contador = Object.create(null);
      corrida = (req.url.split('corrida=')[1] || 'sin-nombre');
      return json(res, 200, { ok: true, corrida });
    }
    if (ruta === '/__red') {
      red = req.url.includes('caida') ? 'caida' : 'arriba';
      return json(res, 200, { ok: true, red });
    }

    anotar(req, Buffer.byteLength(crudo));

    // ── La red caída: el servicio no contesta nada ────────────────────────────────
    if (red === 'caida') {
      res.writeHead(503, { 'content-type': 'application/json' });
      return res.end(JSON.stringify({ ok: false, message: 'simulador: la red está caída' }));
    }

    if (req.method === 'GET' && ruta === '/api/v1/configuracion') {
      return json(res, 200, {
        firebase: FIREBASE,
        version: 7,
        comercio: 'juan_push',
        politica: { momento: 'login', obligatorio: false, preguntaBlanda: false, reintentarCadaDias: 7 },
        ubicacion: { activa: false },
        modulos: MODULOS
      });
    }

    if (req.method === 'POST' && ruta === '/api/v1/comportamiento') {
      let cuerpo = {};
      try { cuerpo = JSON.parse(crudo || '{}'); } catch (_) {}
      const eventos = Array.isArray(cuerpo.eventos) ? cuerpo.eventos : [];
      for (const e of eventos) {
        fs.appendFileSync(EVENTOS, JSON.stringify({
          corrida, recibido: new Date().toISOString(),
          sujetoId: cuerpo.sujetoId ?? null, instalacionId: cuerpo.instalacionId ?? null, ...e
        }) + '\n');
      }
      return json(res, 200, { ok: true, recibidos: eventos.length });
    }

    const conocidas = [
      '/api/v1/instalaciones', '/api/v1/sujetos', '/api/v1/dispositivos',
      '/api/v1/senales', '/api/v1/ubicacion', '/api/v1/consentimiento',
      '/api/v1/interacciones'
    ];
    if (conocidas.includes(ruta)) return json(res, 200, { ok: true });
    if (req.method === 'DELETE' && ruta.startsWith('/api/v1/dispositivos/')) return json(res, 200, { ok: true });

    return json(res, 404, { ok: false, message: `el simulador no conoce ${req.method} ${ruta}` });
  });
});

servidor.listen(PUERTO, () => console.log(`simulador escuchando en ${PUERTO}`));
