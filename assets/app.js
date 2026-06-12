/* ============================================================
   Reunvo — App del cliente · lógica compartida
   ============================================================ */

const REUNVO = {
  SUPABASE_URL: "https://quywrltqzoyyorbsuiwc.supabase.co",
  SUPABASE_ANON_KEY: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InF1eXdybHRxem95eW9yYnN1aXdjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzA0MDYzMTQsImV4cCI6MjA4NTk4MjMxNH0.Tz_CvS_ngJZIn4SOjahKuEqEJOrWOltfti7tEQt0_Rk",
  OAUTH_START_URL: "https://guillepalacin1.app.n8n.cloud/webhook/auth/start"
};

/* ---------- Token del cliente ----------
   Viaja en el fragment (#t=...): no aparece en logs ni en Referer.
   Se conserva en sessionStorage para navegar entre páginas. */
function getToken() {
  const m = location.hash.match(/[#&]t=([a-f0-9]+)/i);
  if (m) {
    sessionStorage.setItem("reunvo_t", m[1]);
    return m[1];
  }
  return sessionStorage.getItem("reunvo_t");
}

/* Añade el token a los enlaces internos marcados con data-keep-token */
function propagarToken(token) {
  if (!token) return;
  document.querySelectorAll("a[data-keep-token]").forEach(a => {
    a.href = a.getAttribute("href").split("#")[0] + "#t=" + token;
  });
}

/* ---------- RPC panel_cliente ---------- */
async function panelCliente(token) {
  const res = await fetch(REUNVO.SUPABASE_URL + "/rest/v1/rpc/panel_cliente", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "apikey": REUNVO.SUPABASE_ANON_KEY,
      "Authorization": "Bearer " + REUNVO.SUPABASE_ANON_KEY
    },
    body: JSON.stringify({ p_token: token })
  });
  if (!res.ok) throw new Error("rpc_error_" + res.status);
  return res.json();
}

/* ---------- Utilidades de presentación ---------- */
function fmtFecha(iso) {
  if (!iso) return "—";
  const d = new Date(iso);
  const hoy = new Date();
  const ayer = new Date(hoy); ayer.setDate(hoy.getDate() - 1);
  const mismaFecha = (a, b) =>
    a.getDate() === b.getDate() && a.getMonth() === b.getMonth() && a.getFullYear() === b.getFullYear();
  const hora = d.toLocaleTimeString("es-ES", { hour: "2-digit", minute: "2-digit" });
  if (mismaFecha(d, hoy))  return "hoy, " + hora;
  if (mismaFecha(d, ayer)) return "ayer, " + hora;
  return d.toLocaleDateString("es-ES", { day: "numeric", month: "short" }) + ", " + hora;
}

const ESTADOS = {
  draft_created: "Borrador",
  pending:       "En preparación",
  sent:          "Enviado",
  error:         "Incidencia"
};
function fmtEstado(s) { return ESTADOS[s] || "Borrador"; }

/* Muestra el estado de token inválido y oculta el contenido */
function mostrarErrorToken() {
  document.querySelectorAll("[data-app]").forEach(el => el.hidden = true);
  const err = document.querySelector("[data-error-token]");
  if (err) err.hidden = false;
}
