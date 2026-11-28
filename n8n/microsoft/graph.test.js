const assert = require("assert");
const g = require("./graph.js");
const b64 = o => Buffer.from(JSON.stringify(o)).toString("base64").replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const idt = email => `h.${b64({ email })}.s`;
(async () => {
  // Permisos: Mail.Send único sobre correo; sin User.Read ni lectura
  assert.equal(g.SCOPES, "openid email offline_access https://graph.microsoft.com/Mail.Send");
  assert.equal(/User\.Read|Mail\.Read/.test(g.SCOPES), false);
  // state = nonce, nunca el token del panel
  const nonce = "123e4567-e89b-12d3-a456-426614174000";
  const u = new URL(g.buildAuthUrl({ clientId: "cid", redirectUri: "https://x/cb", nonce }));
  assert.equal(u.searchParams.get("state"), nonce);
  assert.throws(() => g.buildAuthUrl({ clientId: "c", redirectUri: "r", nonce: "abcdef0123456789" }), /nonce_invalido/);
  // lista blanca de proveedores
  assert.equal(g.proveedorValido("microsoft"), true); assert.equal(g.proveedorValido("yahoo"), false); assert.equal(g.proveedorValido(undefined), false);
  // email desde el id_token; no se guarda el access_token
  const { row, accessToken } = g.tokenRow({ access_token: "A1", refresh_token: "R1", id_token: idt("a@example.invalid"), expires_in: 3600 });
  assert.equal(row.gmail_email, "a@example.invalid"); assert.equal(row.access_token, null); assert.equal(row.token_expiry, null);
  assert.equal(accessToken, "A1"); assert.equal(row.estado, "ok");
  assert.equal(g.tokenRow({ access_token: "A", id_token: idt("b@example.invalid") }, { refresh_token: "R0" }).row.refresh_token, "R0");
  assert.equal(g.emailDeIdToken("basura"), null);
  // refresco: rotación estricta (un refresh_token solo vale una vez) y 6 llamadas concurrentes
  let vigente = "R0", n = 0;
  const fetchFn = async (url, o) => {
    const f = Object.fromEntries(o.body);
    await new Promise(r => setTimeout(r, 5));
    if (f.refresh_token !== vigente) return { json: async () => ({ error: "invalid_grant" }) };
    n++; vigente = "R" + n;
    return { json: async () => ({ access_token: "A" + n, refresh_token: vigente, id_token: idt("a@example.invalid"), expires_in: 3600 }) };
  };
  const filas = { c1: { refresh_token: "R0", estado: "ok", lease: false } }; const orden = [];
  const store = {
    lease: async c => { if (filas[c].lease) return false; filas[c].lease = true; return true; },
    soltar: async c => { filas[c].lease = false; },
    leer: async c => ({ ...filas[c] }),
    guardar: async (c, r) => { orden.push("guardar:" + r.refresh_token); Object.assign(filas[c], r); },
    estado: async (c, e) => { filas[c].estado = e; }
  };
  const toks = await Promise.all([1, 2, 3, 4, 5, 6].map(() => g.accessToken({ fetchFn, store, cliente: "c1", clientId: "i", clientSecret: "s" })));
  assert.equal(new Set(toks).size, 6, "una llamada de token por refresco, serializadas");
  assert.equal(filas.c1.refresh_token, "R6"); assert.equal(filas.c1.estado, "ok"); assert.equal(filas.c1.access_token, null);
  assert.deepEqual(orden, ["guardar:R1", "guardar:R2", "guardar:R3", "guardar:R4", "guardar:R5", "guardar:R6"]);
  // guardar ANTES de usar: si guardar falla, no se devuelve ningún access token
  const malo = { ...store, guardar: async () => { throw new Error("db_caida"); } };
  filas.c1.lease = false;
  await assert.rejects(g.accessToken({ fetchFn, store: malo, cliente: "c1", clientId: "i", clientSecret: "s" }), /db_caida/);
  assert.equal(filas.c1.lease, false, "la concesión se suelta siempre");
  // invalid_grant -> estado 'caducada' (no se mira token_expiry)
  vigente = "OTRO"; filas.c1.lease = false;
  await assert.rejects(g.accessToken({ fetchFn, store, cliente: "c1", clientId: "i", clientSecret: "s" }), e => g.esCaducado(e));
  assert.equal(filas.c1.estado, "caducada");
  // envío
  let seen; const f = async (url, o) => { seen = { url, o }; return { status: 202, json: async () => ({}) }; };
  assert.equal(await g.sendMail(f, "tok", { to: "a@example.invalid", subject: "s", html: "<p>h</p>" }), true);
  assert.equal(seen.url, "https://graph.microsoft.com/v1.0/me/sendMail"); assert.equal(JSON.parse(seen.o.body).saveToSentItems, true);
  await assert.rejects(g.sendMail(async () => ({ status: 401, json: async () => ({}) }), "x", { to: "a@example.invalid", subject: "s", html: "" }), e => e.status === 401);
  console.log("graph: OK");
})().catch(e => { console.error(e); process.exit(1); });
