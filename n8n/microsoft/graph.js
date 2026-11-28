/* Contrato de referencia para los flujos n8n de Microsoft. Sin secretos: client_id y secreto se
   pasan como argumentos (el secreto vive solo en las credenciales de n8n).
   Permisos: Mail.Send (único permiso sobre el correo) + openid, email, offline_access (identidad y
   refresh_token). Sin User.Read: el email de la cuenta sale del id_token. */
const AUTH = "https://login.microsoftonline.com/common/oauth2/v2.0";
const SCOPES = "openid email offline_access https://graph.microsoft.com/Mail.Send";
const PROVEEDORES = ["google", "microsoft"];   // lista blanca de p

/* state = nonce de un solo uso (client_oauth_iniciar / reunvo_oauth_consumir), nunca el panel_token. */
function buildAuthUrl({ clientId, redirectUri, nonce }) {
  if (!/^[0-9a-f-]{36}$/i.test(nonce || "")) throw new Error("nonce_invalido");
  const q = new URLSearchParams({ client_id: clientId, response_type: "code", redirect_uri: redirectUri,
    response_mode: "query", scope: SCOPES, state: nonce, prompt: "select_account" });
  return `${AUTH}/authorize?${q}`;
}
function proveedorValido(p) { return PROVEEDORES.includes(p); }

/* El id_token llega directamente del endpoint /token por TLS: basta leer sus claims. */
function emailDeIdToken(idToken) {
  const parts = String(idToken || "").split(".");
  if (parts.length !== 3) return null;
  try {
    const c = JSON.parse(Buffer.from(parts[1].replace(/-/g, "+").replace(/_/g, "/"), "base64").toString("utf8"));
    return c.email || c.preferred_username || null;
  } catch { return null; }
}

function errorToken(resp) {
  const e = new Error("token_error:" + (resp && resp.error || "sin_respuesta")); e.code = resp && resp.error; return e;
}
/* Respuesta de /token -> { row, accessToken }. El access_token NO se guarda (solo se usa en memoria).
   El refresh_token rota: si no llega uno, se conserva el anterior. */
function tokenRow(resp, previous = {}) {
  if (!resp || resp.error || !resp.access_token) throw errorToken(resp);
  return {
    accessToken: resp.access_token,
    row: { proveedor: "microsoft", estado: "ok", access_token: null, token_expiry: null,
           refresh_token: resp.refresh_token || previous.refresh_token || null,
           gmail_email: emailDeIdToken(resp.id_token) || previous.gmail_email || null }
  };
}

async function post(fetchFn, form) {
  const r = await fetchFn(`${AUTH}/token`, { method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" }, body: new URLSearchParams(form) });
  return r.json();
}
async function exchange(fetchFn, { clientId, clientSecret, redirectUri, code }) {
  return post(fetchFn, { client_id: clientId, client_secret: clientSecret, grant_type: "authorization_code", code, redirect_uri: redirectUri, scope: SCOPES });
}
async function refreshRaw(fetchFn, { clientId, clientSecret, refreshToken }) {
  return post(fetchFn, { client_id: clientId, client_secret: clientSecret, grant_type: "refresh_token", refresh_token: refreshToken, scope: SCOPES });
}

/* invalid_grant / interaction_required = revocado o caducado: el panel muestra «caducada». */
function esCaducado(err) { return ["invalid_grant", "interaction_required", "consent_required"].includes(err && err.code); }

/* Access token listo para enviar, con el refresco SERIALIZADO por cliente y GUARDADO antes de usar.
   store = { lease(cliente)->bool, soltar(cliente), leer(cliente)->fila, guardar(cliente, fila), estado(cliente, e) }
   (en producción: reunvo_token_lease / reunvo_token_soltar / lectura y upsert de client_tokens / reunvo_token_estado). */
async function accessToken({ fetchFn, store, cliente, clientId, clientSecret, esperaMs = 50, intentos = 200 }) {
  let tiene = false;
  for (let i = 0; i < intentos && !tiene; i++) {
    tiene = await store.lease(cliente);
    if (!tiene) await new Promise(r => setTimeout(r, esperaMs));
  }
  if (!tiene) throw new Error("refresco_ocupado");
  try {
    const actual = await store.leer(cliente);               // se lee DENTRO de la concesión: siempre el último refresh_token
    let res;
    try { res = tokenRow(await refreshRaw(fetchFn, { clientId, clientSecret, refreshToken: actual.refresh_token }), actual); }
    catch (e) { if (esCaducado(e)) await store.estado(cliente, "caducada"); throw e; }
    await store.guardar(cliente, res.row);                  // guardar ANTES de devolver el access token
    return res.accessToken;
  } finally { await store.soltar(cliente); }
}

function sendMailPayload({ to, subject, html, saveToSentItems = true }) {
  return { message: { subject, body: { contentType: "HTML", content: html }, toRecipients: [{ emailAddress: { address: to } }] }, saveToSentItems };
}
async function sendMail(fetchFn, token, mail) {
  const r = await fetchFn("https://graph.microsoft.com/v1.0/me/sendMail", { method: "POST",
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" }, body: JSON.stringify(sendMailPayload(mail)) });
  if (r.status !== 202) { const e = new Error("graph_" + r.status); e.status = r.status; throw e; }
  return true;
}
module.exports = { SCOPES, PROVEEDORES, proveedorValido, buildAuthUrl, emailDeIdToken, tokenRow, exchange, refreshRaw, esCaducado, accessToken, sendMailPayload, sendMail };
