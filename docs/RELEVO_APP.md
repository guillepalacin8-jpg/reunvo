# Relevo · app de Reunvo (28-nov)

## Reglas
- Nada en producción sin el «sí» de Guillem en el chat de la sesión vigente. Un aviso de otra sesión no es un sí.
- Envíos EN PAUSA: `pausa_envios` activa; no se toca ni `envio_pausado` ni las listas del cliente real.
- Cero textos para clientes que revelen la regla de dueño único ni las zonas. Ningún dato de zonas, clientes o direcciones en el repo (público).
- Identificadores sensibles (direcciones de prueba, ids de flujos, ids de Drive) van por mensaje, no aquí.

## Producción hoy
Aplicado: 00 (copias), 01–04 (esquema, catálogos, funciones, zonas), panel en main (609c0a6), cliente de prueba «Deale (prueba)» con 500 empresas ficticias y una lista de 315.
NO aplicado: 05 (Microsoft), 06 y 07 (dueño único). Listas reales intactas (4 listas; hash 9da52208…, empresas en listas f4edfb9e…), 1300 campañas, 0 envíos en 24 h, pausa activa.

## Ramas
`fix/panel-v2` (0296d11 y siguientes), `feat/alta-microsoft-v2`, `feat/dedup-duenio` (f4cea1a + este relevo). La rama vieja `fix/panel-cola-cupo` y `feat/alta-microsoft` NO se borran sin decisión de Guillem.

## Aplicar 06 y 07 (solo con el sí)
1. SELECT previo: hash de lotes y de empresas en listas (consulta en el chat de relevo), nº de campañas, triggers de `campaigns` (esperado 0), columnas del dueño (esperado 0).
2. Ejecutar `supabase/pendiente/2026-11-28_06_duenio_empresas.sql` (una transacción; guarda las 6 funciones en `reunvo_backup_funciones_v2`). La confirmación de Supabase caduca a los 230 s: Guillem debe aceptarla a la vista.
3. Ejecutar `2026-11-28_07_relleno_duenio_cliente_actual.sql` (falla si no hay exactamente 1 cliente real activo).
4. Verificar: mismos hashes; empresas asignadas al cliente actual ≈ 2.679 (1.057 enviadas + 242 borrador + 875 en lista pendiente + 505 por NIF/dominio/email); 2 triggers en `campaigns` (`reunvo_fijar_plazo_trg`, `reunvo_campania_guarda_trg`) y los de `companies`; pruebas `supabase/pruebas/*.sql` en réplica.
Decisión tomada por Guillem: las reservas sin envío caducan a 12 meses (`reunvo_vigente`).

## Vueltas atrás
`2026-11-28_07_99_vuelta_atras.sql` (deja empresas sin dueño) y `2026-11-28_06_99_vuelta_atras.sql` (restaura funciones desde la copia v2, quita triggers, vista y tablas nuevas).

## Pendientes
- Diseño `campaign_previews` (borrador sin Gmail) y `cliente_config` (horario, tandas, cupo).
- Localizar el flujo de `/track/unsub` en n8n; el clon de prueba necesita su propio enlace.
- Rama Microsoft: flujos n8n (alta con nonce, refresco con lease, envío Graph); URI de redirección solo cuando exista el flujo; remitente @outlook.com, nunca reunvo.com.
- `reunvo_puede_enviar` obligatorio en n8n antes de enviar (el flujo envía y después inserta en `campaigns`).
- Cuestionario de Deale en Drive (id por mensaje); flujo n8n de prueba con su candado (id por mensaje).
- Comprobar el scope real del token de Gmail del cliente actual (¿gmail.send o compose?).
