# Alta y envío con Microsoft 365 / Outlook

Rama `feat/alta-microsoft-v2`. Nada desplegado. El OAuth y el envío viven en n8n (fuera del repo): aquí están el esquema, el panel y el contrato de referencia (`n8n/microsoft/graph.js`, con pruebas).

## Flujo
1. `conectar.html` y el panel ofrecen «Google» y «Microsoft 365 / Outlook», y el botón para cambiar de proveedor sale también con la cuenta conectada o caducada.
2. Microsoft no recibe nunca el token del panel: el panel pide a la base un nonce de un solo uso (`client_oauth_iniciar`, lista blanca de proveedores, tope de 10 vivos por cliente) y va a `auth/start?s=<nonce>&p=microsoft`. n8n lo consume con `reunvo_oauth_consumir` (válido 10 minutos, una vez) y lo usa como `state`. n8n valida `p` con lista blanca (`google`, `microsoft`). Recomendado: migrar también el flujo de Google a este nonce.
3. Permisos: `Mail.Send` (único sobre el correo) más `openid`, `email`, `offline_access`. Sin `User.Read`: el email sale del id_token.
4. Se guarda en `client_tokens` (una fila por cliente, clave `client_id`): `proveedor`, `refresh_token`, email en `gmail_email`. **No se guarda access_token.** Cambiar de proveedor sustituye la fila, así que `client_panel` es determinista.
5. Envío: `POST /me/sendMail` con `saveToSentItems`. Refresco: se serializa por cliente (`reunvo_token_lease`/`soltar`), el refresh_token rotado se guarda **antes** de usar el access token.
6. «Caducada»: n8n escribe `estado = 'caducada'` (`reunvo_token_estado`) al recibir `invalid_grant`, y `'ok'` al reconectar. Para Microsoft el panel solo mira `estado`, no `token_expiry`.
7. Aviso al cliente: los mensajes enviados quedan en la carpeta Enviados de su cuenta.

## Antes de activar Microsoft
Los flujos n8n de Gmail deben leer `client_tokens` con `proveedor = 'google'`; si no, intentarían refrescar con Google un token de Microsoft.

## Esquema
`2026-11-28_05_proveedor_microsoft.sql` (tras 03): columnas `proveedor`, `estado`, `refresh_lease_until`; tabla `oauth_estados` (RLS sin políticas); funciones indicadas arriba (solo `client_oauth_iniciar` es pública). Vuelta atrás: `..._05_..._99_vuelta_atras.sql`.

## Lo que necesita Guillem
Ver `docs/GUIA_ENTRA.md`. El secreto va directo a las credenciales de n8n, nunca al chat.

## Límites
- Microsoft 365 limita el envío por buzón (≈30 mensajes/minuto, tope diario por inquilino): con 15 al día no afecta.
- Los envíos de Reunvo siguen EN PAUSA.
