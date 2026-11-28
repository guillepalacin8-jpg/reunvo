# Registro de Reunvo en Microsoft Entra (paso a paso, para Guillem)

Objetivo: que los clientes conecten Microsoft 365 / Outlook con un único permiso de envío. **Ningún secreto se pega en el chat**: el secreto va directo a las credenciales de n8n.

Necesita una cuenta de Microsoft con acceso a https://entra.microsoft.com (puede ser una cuenta gratuita de Azure; el registro de aplicaciones no tiene coste).

## 1. Crear el registro
1. entra.microsoft.com → **Identidad** → **Aplicaciones** → **Registros de aplicaciones** → **Nuevo registro**.
2. **Nombre:** `Reunvo` (es lo que verá el cliente en la pantalla de permisos).
3. **Tipos de cuenta compatibles:** «Cuentas en cualquier directorio de la organización (multiinquilino) y cuentas personales de Microsoft». Es la tercera opción; sin ella solo entrarían clientes de su propio inquilino.
4. **URI de redirección:** plataforma **Web** y la URL de callback de n8n. Cópiela exacta del nodo Webhook del flujo de alta en n8n (pestaña **Production URL**, no la de test). El inicio ya existe en `https://guillepalacin1.app.n8n.cloud/webhook/auth/start`; el callback tendrá el mismo dominio y empezará por `https://guillepalacin1.app.n8n.cloud/webhook/`. Debe coincidir carácter a carácter con lo que usa n8n.
5. **Registrar.** Anote (no es secreto) el **Id. de aplicación (cliente)**.

## 2. Permisos
1. **Permisos de API** → **Agregar un permiso** → **Microsoft Graph** → **Permisos delegados**.
2. Marque solo: `Mail.Send` (Microsoft Graph) y, en «Permisos de OpenID», `openid`, `email` y `offline_access`. **No** añada `User.Read`: el email de la cuenta se lee del id_token.
3. **No** añada `Mail.Read`, `Mail.ReadWrite` ni permisos de aplicación. No pulse «Conceder consentimiento de administrador» para su organización: cada cliente consiente el suyo.

## 3. Secreto (va a n8n, no al chat)
1. **Certificados y secretos** → **Nuevo secreto de cliente** → descripción `n8n`, caducidad 24 meses.
2. Copie el **Valor** en el momento (solo se ve una vez) y péguelo **directamente** en n8n: Credentials → nueva credencial → campo de secreto. No lo escriba en el chat, en un email ni en el repositorio.
3. Ponga un recordatorio en el calendario 1 mes antes de la caducidad: al caducar, todas las altas y los refrescos de Microsoft fallan.

## 4. Verificar el editor
1. Cuenta de Microsoft AI Cloud Partner Program (MCP ID) → **Marca** → **Editor verificado**. Sin esto, los clientes con Microsoft 365 empresarial suelen ver «necesita aprobación del administrador» y no pueden dar de alta.
2. Complete también **Marca**: nombre, logo, enlace a `https://reunvo.com/privacidad` y a los términos.

## 5. Prueba
1. Con una cuenta propia (no de cliente) abra `conectar.html` con su enlace de prueba y pulse «Continuar con Microsoft 365 / Outlook».
2. Debe ver: enviar correo en su nombre, más los permisos estándar de acceso (iniciar sesión y mantener la conexión). Si pide leer el correo o el perfil, algo está mal: pare y avise.
3. Tras aceptar, `client_tokens` debe tener `proveedor = 'microsoft'`, `estado = 'ok'`, el email de la cuenta y `access_token` vacío.

## Datos para pasar a quien configure n8n
Id. de aplicación (cliente), y que el inquilino es `common`. El secreto no se pasa: se carga en n8n.
