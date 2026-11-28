const assert = require("assert");
const g = require("./graph.js");
const mk = (status, body) => async () => ({ status, json: async () => body });
(async () => {
  const u = new URL(g.buildAuthUrl({ clientId: "cid", redirectUri: "https://x/cb", state: "S" }));
  assert.equal(u.searchParams.get("scope").includes("Mail.Send"), true);
  assert.equal(/Mail\.Read|Mail\.ReadWrite/.test(u.searchParams.get("scope")), false, "sin permisos de lectura");
  const now = Date.UTC(2026, 10, 28);
  let row = g.tokenRow({ access_token: "a", refresh_token: "r1", expires_in: 3600 }, {}, now);
  assert.equal(row.proveedor, "microsoft"); assert.equal(row.token_expiry, new Date(now + 3540000).toISOString());
  row = g.tokenRow({ access_token: "a2", expires_in: 3600 }, { refresh_token: "r1" }, now);
  assert.equal(row.refresh_token, "r1", "conserva el refresh si no rota");
  row = g.tokenRow({ access_token: "a3", refresh_token: "r2", expires_in: 3600 }, { refresh_token: "r1" }, now);
  assert.equal(row.refresh_token, "r2", "guarda el rotado");
  let err; try { g.tokenRow({ error: "invalid_grant" }); } catch (e) { err = e; }
  assert.equal(g.esCaducado(err), true);
  assert.equal(g.esCaducado(new Error("x")), false);
  let seen; const f = async (url, o) => { seen = { url, o }; return { status: 202, json: async () => ({}) }; };
  assert.equal(await g.sendMail(f, "tok", { to: "a@example.invalid", subject: "s", html: "<p>h</p>" }), true);
  assert.equal(seen.url, "https://graph.microsoft.com/v1.0/me/sendMail");
  assert.equal(seen.o.headers.Authorization, "Bearer tok");
  assert.equal(JSON.parse(seen.o.body).message.toRecipients[0].emailAddress.address, "a@example.invalid");
  let e2; try { await g.sendMail(mk(401, {}), "bad", { to: "a@example.invalid", subject: "s", html: "" }); } catch (e) { e2 = e; }
  assert.equal(e2.status, 401);
  assert.equal((await g.refresh(mk(200, { error: "invalid_grant" }), { clientId: "c", clientSecret: "s", refreshToken: "r" })).error, "invalid_grant");
  console.log("graph: OK");
})().catch(e => { console.error(e); process.exit(1); });
