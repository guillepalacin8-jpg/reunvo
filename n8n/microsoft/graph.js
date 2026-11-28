/* Contrato de referencia para los flujos n8n de Microsoft. Funciones puras: sin secretos
   (client_id/secret se pasan como argumentos; el secreto vive solo en las credenciales de n8n).
   Permisos delegados mínimos: Mail.Send (enviar), offline_access (refresh_token), User.Read (leer el email de la cuenta). */
const AUTH = "https://login.microsoftonline.com/common/oauth2/v2.0";
const SCOPES = "https://graph.microsoft.com/Mail.Send offline_access https://graph.microsoft.com/User.Read";

function buildAuthUrl({ clientId, redirectUri, state }) {
  const q = new URLSearchParams({ client_id: clientId, response_type: "code", redirect_uri: redirectUri,
    response_mode: "query", scope: SCOPES, state, prompt: "select_account" });
  return `${AUTH}/authorize?${q}`;
}

/* Respuesta de /token -> fila para client_tokens. El refresh_token rota: si no llega uno, se conserva el anterior. */
function tokenRow(resp, previous = {}, now = Date.now()) {
  if (!resp || resp.error || !resp.access_token) {
    const e = new Error("token_error:" + (resp && resp.error || "sin_respuesta")); e.code = resp && resp.error; throw e;
  }
  return {
    proveedor: "microsoft",
    access_token: resp.access_token,
    refresh_token: resp.refresh_token || previous.refresh_token || null,
    token_expiry: new Date(now + (resp.expires_in || 3600) * 1000 - 60000).toISOString()
  };
}

async function exchange(fetchFn, { clientId, clientSecret, redirectUri, code }) {
  return post(fetchFn, { client_id: clientId, client_secret: clientSecret, grant_type: "authorization_code", code, redirect_uri: redirectUri, scope: SCOPES });
}
async function refresh(fetchFn, { clientId, clientSecret, refreshToken }) {
  return post(fetchFn, { client_id: clientId, client_secret: clientSecret, grant_type: "refresh_token", refresh_token: refreshToken, scope: SCOPES });
}
async function post(fetchFn, form) {
  const r = await fetchFn(`${AUTH}/token`, { method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" }, body: new URLSearchParams(form) });
  return r.json();
}

/* invalid_grant / interaction_required = el cliente revocó o caducó: el panel debe mostrar «caducada». */
function esCaducado(err) { return ["invalid_grant", "interaction_required", "consent_required"].includes(err && err.code); }

function sendMailPayload({ to, subject, html, saveToSentItems = true }) {
  return { message: { subject, body: { contentType: "HTML", content: html }, toRecipients: [{ emailAddress: { address: to } }] }, saveToSentItems };
}
async function sendMail(fetchFn, accessToken, mail) {
  const r = await fetchFn("https://graph.microsoft.com/v1.0/me/sendMail", { method: "POST",
    headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" }, body: JSON.stringify(sendMailPayload(mail)) });
  if (r.status !== 202) { const e = new Error("graph_" + r.status); e.status = r.status; throw e; }
  return true;
}
module.exports = { SCOPES, buildAuthUrl, tokenRow, exchange, refresh, esCaducado, sendMailPayload, sendMail };
