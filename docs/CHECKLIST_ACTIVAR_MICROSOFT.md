# Activar el alta con Microsoft: pasos para Guillem

Nada de esto está hecho. El código (rama `feat/alta-microsoft-v2`) está listo pero **no se activa** hasta cumplir la lista, en este orden. Los secretos nunca se pegan en el chat.

1. **Microsoft Entra:** seguir `docs/GUIA_ENTRA.md` (app multiinquilino con cuentas personales; permisos `Mail.Send`, `openid`, `email`, `offline_access`; sin `User.Read`). Anotar el Id. de aplicación.
2. **Secreto:** crearlo en Entra y pegarlo solo en las credenciales de n8n. Recordatorio en el calendario un mes antes de que caduque.
3. **Editor verificado** y marca (nombre, logo, enlace de privacidad `https://reunvo.com/privacidad.html` y términos). Sin esto, muchas empresas exigen consentimiento del administrador.
4. **Gmail primero:** antes de ejecutar el SQL 05, los flujos de Gmail en n8n deben leer `client_tokens` con `proveedor = 'google'`. Si no, intentarían refrescar con Google un token de Microsoft.
5. **Ejecutar el SQL 05** (después de 03). Vuelta atrás: `..._05_..._99_vuelta_atras.sql`. Usa `client_tokens.updated_at`, que existe en producción.
6. **Flujos n8n de Microsoft**, siguiendo `n8n/microsoft/graph.js`:
   - `auth/start`: recibe `s` (nonce) y `p`; valida `p` con lista blanca (`google`, `microsoft`); usa el nonce como `state`; **no lo consume**.
   - **Callback:** aquí se consume el nonce (`reunvo_oauth_consumir`: válido 10 minutos y una sola vez) y se comprueba que el `state` devuelto coincide. Si no es válido, se rechaza el alta.
   - Alta: guardar `proveedor = 'microsoft'`, `refresh_token`, email (del id_token) y `estado = 'ok'`. No guardar `access_token`.
   - Refresco: con la concesión por cliente (`reunvo_token_lease` / `reunvo_token_soltar`), leyendo el último `refresh_token` dentro de la concesión y guardando el rotado antes de usar el access token.
   - `invalid_grant`: `reunvo_token_estado(cliente, 'caducada')`.
   - Envío: `POST /me/sendMail`, con copia en Enviados.
7. **Política de privacidad:** añadir el permiso `Mail.Send` de Microsoft junto a `gmail.send` (hoy `privacidad.html` solo cita Gmail). Lo revisa Compliance.
8. **Prueba extremo a extremo** con una cuenta propia: la pantalla de permisos muestra enviar correo más tres de acceso (nunca leer correo); `client_tokens` queda con `proveedor`, `estado = 'ok'` y `access_token` vacío; al revocar el acceso en Microsoft, el panel muestra «Conexión del correo caducada».
9. Comprobar que el envío real de Reunvo sigue en pausa y que nada de esto lo reactiva.
