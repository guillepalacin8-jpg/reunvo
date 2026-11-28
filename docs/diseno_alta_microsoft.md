# Alta y envío con Microsoft 365 / Outlook

Rama `feat/alta-microsoft`. Nada desplegado. El OAuth y el envío viven en n8n (fuera del repo): aquí están el esquema, el panel y el contrato de referencia (`n8n/microsoft/graph.js`, con pruebas).

## Flujo
1. `conectar.html` y el panel ofrecen «Google» y «Microsoft 365 / Outlook». El botón llama a `auth/start?t=<token>&p=google|microsoft` (sin `p`, Google).
2. Microsoft: Entra v2 `/common` (cuentas de trabajo y personales), permisos delegados mínimos `Mail.Send`, `offline_access`, `User.Read` (este último solo para leer el email de la cuenta). Sin permisos de lectura de correo.
3. n8n guarda en `client_tokens` con `proveedor = 'microsoft'`: `refresh_token`, `token_expiry` y el email (columna `gmail_email`, que se reutiliza).
4. Envío: `POST https://graph.microsoft.com/v1.0/me/sendMail` (202 = enviado). Refresco: `/oauth2/v2.0/token` con `grant_type=refresh_token`; el refresh_token rota y se guarda el nuevo.
5. `invalid_grant` / `interaction_required` = caducado: `client_panel.gmail.caducado` pasa a true y el panel pide reconectar.
6. `client_panel.gmail.proveedor` (por defecto `google`); los textos del panel se adaptan.

## Esquema
`2026-11-28_05_proveedor_microsoft.sql`: columna `proveedor` con valor por defecto `google` y restricción. Las filas de Gmail no cambian. Vuelta atrás: `..._05_..._99_vuelta_atras.sql`. `client_panel` lee la columna con `to_jsonb(t)`, así funciona antes y después de ejecutar el 05.

## Lo que necesita Guillem (sin pegar secretos en el chat)
- Registrar una app en Microsoft Entra: multi-tenant y cuentas personales; redirect URI = el callback de n8n; permisos delegados Microsoft Graph `Mail.Send`, `User.Read`, `offline_access`.
- Crear el secreto de cliente y guardarlo solo en las credenciales de n8n.
- Verificar el editor (publisher verification). Sin ello, muchas empresas exigen consentimiento del administrador y el alta se bloquea.
- Pendiente fuera del repo: ramas Microsoft de los flujos n8n de alta (`auth/start`, callback), refresco y envío, siguiendo `n8n/microsoft/graph.js`.

## Límites
- Microsoft 365 puede limitar el envío por buzón (≈30 mensajes/minuto, tope diario por inquilino): con 15 al día no afecta.
- Los envíos de Reunvo siguen EN PAUSA.
