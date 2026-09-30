#!/usr/bin/env node
/**
 * EL DOBLE DE LA INGESTA — para probar el SDK sin el back de B.
 *
 * Implementa lo mínimo de PM-025 §4.1 y §4.5, con la MISMA verificación que tiene que hacer
 * la ingesta de verdad, para que un verde acá signifique algo allá:
 *
 *   GET  /api/v1/configuracion?paquete=…   → { rastreo: {…§4.5} }  (números por variable)
 *   POST /api/v1/instalaciones · /sujetos  → { ok: true }           (el enrolamiento del núcleo)
 *   POST /api/v1/rastreo/claves            → verifica claveId = SHA-256(SPKI DER) y la guarda
 *   POST /api/v1/rastreo/lotes             → verifica forma, hash canónico, firma ES256 con la
 *                                            pública registrada, cadena hashAnterior, t futuro
 *                                            (por punto), e idempotencia por (instalacionId, loteId)
 *
 * Los códigos y los `error` son los de la ingesta de B (RESUMEN-B §3.2 y §8): 401
 * hash_no_coincide / firma_invalida / clave_desconocida · 409 cadena_rota con ultimoHash ·
 * 202 con `rechazados` · 201/200/409 ya_tiene_clave al registrar.
 *
 * El canónico es el de JavaScript: `JSON.stringify` del cuerpo sin `hash` ni `firma` con las
 * claves ordenadas en todos los niveles. Es exactamente lo que el SDK firma.
 *
 *   node example/tool/doble_ingesta.mjs                 # puerto 8080
 *   PUERTO=8090 LOTE_SEG=60 RAPIDO_LOTE_SEG=60 QUIETO_MIN=1 node example/tool/doble_ingesta.mjs
 *   SIN_TABLA=true …  (sin `cadencia`: el SDK usa el respaldo 10/20/300)
 *   FALLAR=429:2 node example/tool/doble_ingesta.mjs    # los 2 primeros lotes → 429 Retry-After: 20
 *   ACTIVO=false node example/tool/doble_ingesta.mjs     # prueba el apagado
 *   SALIDA=/ruta/lotes.jsonl                             # cada lote aceptado, una línea
 *
 * Sin dependencias: sólo `node:` (probado con Node 20).
 */
import http from 'node:http';
import crypto from 'node:crypto';
import fs from 'node:fs';

const PUERTO = Number(process.env.PUERTO ?? 8080);
const SALIDA = process.env.SALIDA ?? null;
const env = (k, d) => (process.env[k] === undefined ? d : Number(process.env[k]));
// PM-025 §4.5 con el «Cambio del 30-09-2026»: la tabla de cadencia por estado.
// LOTE_SEG y RAPIDO_LOTE_SEG achican los lotes para probar rápido en el emulador.
const RASTREO = {
  activo: process.env.ACTIVO !== 'false',
  perfil: process.env.ACTIVO === 'false' ? null : 'persona-en-movimiento',
  arranqueKmh: env('ARRANQUE_KMH', 10),
  quietoMin: env('QUIETO_MIN', 5),
  golpe: { g: 4, quietoSeg: 60 },
  estadoForzado: process.env.FORZADO ?? null,
  lotePuntos: env('LOTE_PUNTOS', 40),
  cadencia: process.env.SIN_TABLA === 'true' ? undefined : [
    { estado: 'emergencia', si: { forzado: true }, muestreoSeg: 2, presenciaSeg: 5, loteSeg: 15 },
    { estado: 'rapido', si: { velKmhMayorA: 40 }, muestreoSeg: 5, presenciaSeg: 15, loteSeg: env('RAPIDO_LOTE_SEG', 120) },
    { estado: 'rodando', si: { enMovimiento: true }, muestreoSeg: 10, presenciaSeg: 20, loteSeg: env('LOTE_SEG', 300) },
    { estado: 'nocheQuieto', si: { quietoMinMayorA: 30, horaEntre: ['22:00', '06:00'] }, muestreoSeg: 0, presenciaSeg: 0, latidoMin: 180 },
    { estado: 'detenido', si: { quietoMinMayorA: 5 }, muestreoSeg: 0, presenciaSeg: 0, latidoMin: 30 },
  ],
};
let [fallarCodigo, fallarVeces] = (process.env.FALLAR ?? '').split(':').map(Number);
fallarVeces = fallarVeces || 0;

const claves = new Map();      // instalacionId → { claveId, publica (KeyObject) }
const lotes = new Map();       // `${inst}|${loteId}` → respuesta dada
const ultimoHash = new Map();  // instalacionId → hash del último aceptado
const ultimoLote = new Map();
const sincronizado = new Map();
const cuenta = { lotes: 0, bytes: 0, puntos: 0, rechazos: 0 };

const ordenar = (v) =>
  Array.isArray(v) ? v.map(ordenar)
    : v && typeof v === 'object'
      ? Object.fromEntries(Object.keys(v).sort().map((k) => [k, ordenar(v[k])]))
      : v;
const canonico = (v) => JSON.stringify(ordenar(v));
const sha256 = (s) => crypto.createHash('sha256').update(s).digest('hex');
const hora = () => new Date().toISOString().slice(11, 19);
const log = (...a) => console.log(hora(), ...a);

function responder(res, codigo, cuerpo, cabeceras = {}) {
  const s = cuerpo === undefined ? '' : JSON.stringify(cuerpo);
  res.writeHead(codigo, { 'content-type': 'application/json', ...cabeceras });
  res.end(s);
}

const numero = (x) => typeof x === 'number' && Number.isFinite(x);
function validarForma(b) {
  const faltan = ['instalacionId', 'loteId', 'claveId', 'alg', 'hashAnterior', 'hash', 'firma', 'reloj', 'puntos']
    .filter((k) => !(k in b));
  if (faltan.length) return `faltan: ${faltan.join(', ')}`;
  const sobran = Object.keys(b).filter((k) => !['instalacionId', 'loteId', 'claveId', 'alg', 'hashAnterior', 'hash', 'firma', 'reloj', 'puntos'].includes(k));
  if (sobran.length) return `sobran: ${sobran.join(', ')}`;
  if (b.alg !== 'ES256') return 'alg no es ES256';
  if (!/^[0-9a-f-]{36}$/.test(b.loteId)) return 'loteId no es un uuid';
  const r = b.reloj;
  if (!r || !numero(r.mono) || !numero(r.arranques) || !(r.gnss === null || numero(r.gnss))) return 'reloj mal formado';
  if (!Array.isArray(b.puntos) || b.puntos.length === 0) return 'sin puntos';
  for (const [i, p] of b.puntos.entries()) {
    for (const k of ['t', 'lat', 'lon', 'acc', 'v', 'h', 'alt', 'bat']) if (!numero(p[k])) return `punto ${i}: ${k} no es número`;
    if (typeof p.mock !== 'boolean') return `punto ${i}: mock no es booleano`;
    if (Object.keys(p).length !== 9) return `punto ${i}: tiene ${Object.keys(p).length} campos, no 9`;
    if (p.bat < 0 || p.bat > 100) return `punto ${i}: bat fuera de 0-100`;
  }
  return null;
}

function lote(req, res, crudo) {
  let b;
  try { b = JSON.parse(crudo); } catch { return responder(res, 400, { ok: false, message: 'JSON inválido' }); }
  const forma = validarForma(b);
  if (forma) { cuenta.rechazos++; log('400', forma); return responder(res, 400, { ok: false, message: forma }); }

  const clave = `${b.instalacionId}|${b.loteId}`;
  if (lotes.has(clave)) {
    log('200 idempotente', b.loteId);
    return responder(res, 200, lotes.get(clave));
  }
  if (fallarVeces > 0) {
    fallarVeces--;
    log(`${fallarCodigo} forzado (quedan ${fallarVeces})`, b.loteId);
    return responder(res, fallarCodigo, { ok: false, message: 'falla forzada' }, fallarCodigo === 429 ? { 'retry-after': '20' } : {});
  }

  const { hash, firma, ...sin } = b;
  const texto = canonico(sin);
  if (sha256(texto) !== hash) { cuenta.rechazos++; log('401 hash', b.loteId); return responder(res, 401, { ok: false, error: 'hash_no_coincide', message: 'el hash no es el del cuerpo canónico' }); }
  const k = claves.get(b.instalacionId);
  if (!k || k.claveId !== b.claveId) { cuenta.rechazos++; log('401 clave desconocida', b.claveId.slice(0, 12)); return responder(res, 401, { ok: false, error: 'clave_desconocida', message: 'clave no registrada para esta instalación' }); }
  const valida = crypto.verify('sha256', Buffer.from(texto, 'utf8'), { key: k.publica, dsaEncoding: 'der' }, Buffer.from(firma, 'base64'));
  if (!valida) { cuenta.rechazos++; log('401 firma', b.loteId); return responder(res, 401, { ok: false, error: 'firma_invalida', message: 'firma inválida' }); }

  const anterior = ultimoHash.get(b.instalacionId) ?? '0';
  if (b.hashAnterior !== anterior) { cuenta.rechazos++; log('409 cadena', b.hashAnterior.slice(0, 12), '≠', anterior.slice(0, 12)); return responder(res, 409, { ok: false, error: 'cadena_rota', message: 'cadena rota: hashAnterior no es el último aceptado', ultimoHash: anterior, ultimoLoteId: ultimoLote.get(b.instalacionId) ?? null }); }

  // Como la ingesta de B (RESUMEN-B §6.2): el t futuro se rechaza POR PUNTO; el lote entra.
  const recibido = Date.now();
  const buenos = b.puntos.filter((p) => p.t <= recibido + 5 * 60 * 1000);
  const rechazados = b.puntos.length - buenos.length;

  const maxT = Math.max(...buenos.map((p) => p.t), 0);
  sincronizado.set(b.instalacionId, Math.max(sincronizado.get(b.instalacionId) ?? 0, maxT));
  const respuesta = { recibido, sincronizadoHasta: sincronizado.get(b.instalacionId), ...(rechazados ? { rechazados } : {}) };
  lotes.set(clave, respuesta);
  ultimoHash.set(b.instalacionId, hash);
  ultimoLote.set(b.instalacionId, b.loteId);
  cuenta.lotes++; cuenta.bytes += Buffer.byteLength(crudo); cuenta.puntos += b.puntos.length;
  const mocks = b.puntos.filter((p) => p.mock).length;
  if (rechazados) log(`   ${rechazados} punto(s) con t futuro rechazados`);
  log(`202 lote ${b.loteId.slice(0, 8)} · ${b.puntos.length} puntos · ${Buffer.byteLength(crudo)} B · mock ${mocks} · ` +
      `v máx ${(Math.max(...b.puntos.map((p) => p.v)) * 3.6).toFixed(0)} km/h · anterior ${b.hashAnterior.slice(0, 8)} · ` +
      `reloj ${JSON.stringify(b.reloj)}`);
  if (SALIDA) fs.appendFileSync(SALIDA, JSON.stringify({ recibido, bytes: Buffer.byteLength(crudo), cuerpo: b }) + '\n');
  return responder(res, 202, respuesta);
}

function registrarClave(res, crudo) {
  let b;
  try { b = JSON.parse(crudo); } catch { return responder(res, 400, { ok: false }); }
  const pub = b.clavePublica;
  if (!b.instalacionId || !pub || b.alg !== 'ES256') return responder(res, 400, { ok: false, error: 'clave_invalida', message: 'faltan instalacionId, clavePublica o alg' });
  const der = Buffer.from(pub, 'base64');
  const claveId = crypto.createHash('sha256').update(der).digest('hex');
  if (b.claveId && b.claveId !== claveId) return responder(res, 400, { ok: false, message: 'claveId no es la huella de la pública' });
  let publica;
  try {
    publica = crypto.createPublicKey({ key: der, format: 'der', type: 'spki' });
    if (publica.asymmetricKeyDetails?.namedCurve !== 'prime256v1') throw new Error('no es P-256');
  } catch (e) { return responder(res, 400, { ok: false, message: `pública inválida: ${e.message}` }); }
  // Como B: 201 nueva · 200 la misma · 409 ya_tiene_clave (la primera gana).
  const ya = claves.get(b.instalacionId);
  if (ya && ya.claveId !== claveId) return responder(res, 409, { ok: false, error: 'ya_tiene_clave' });
  claves.set(b.instalacionId, { claveId, publica });
  log(ya ? '200 clave' : '201 clave', claveId.slice(0, 16), 'de', b.instalacionId);
  return responder(res, ya ? 200 : 201, { claveId, estado: 'vigente' });
}

const servidor = http.createServer((req, res) => {
  const chunks = [];
  req.on('data', (c) => chunks.push(c));
  req.on('end', () => {
    const crudo = Buffer.concat(chunks).toString('utf8');
    const url = new URL(req.url, 'http://x');
    if (!/^Bearer \S+/.test(req.headers.authorization ?? '')) return responder(res, 401, { ok: false, message: 'falta la llave' });
    if (req.method === 'GET' && url.pathname === '/api/v1/configuracion') {
      log('200 configuracion', url.searchParams.get('paquete'), RASTREO.activo ? 'activo' : 'APAGADO');
      return responder(res, 200, { ok: true, version: 1, comercio: 'doble', rastreo: RASTREO });
    }
    if (req.method === 'POST' && (url.pathname === '/api/v1/instalaciones' || url.pathname === '/api/v1/sujetos')) {
      log('200', url.pathname);
      return responder(res, 200, { ok: true });
    }
    if (req.method === 'POST' && url.pathname === '/api/v1/rastreo/claves') return registrarClave(res, crudo);
    if (req.method === 'POST' && url.pathname === '/api/v1/rastreo/lotes') return lote(req, res, crudo);
    if (req.method === 'GET' && url.pathname === '/doble/cuenta') return responder(res, 200, { ...cuenta, instalaciones: [...ultimoHash.keys()] });
    responder(res, 404, { message: 'no existe' });
  });
});
servidor.listen(PUERTO, () => log(`doble de la ingesta en :${PUERTO} · rastreo ${JSON.stringify(RASTREO)}`));
