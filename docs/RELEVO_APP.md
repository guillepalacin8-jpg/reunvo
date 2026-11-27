# Relevo · app de Reunvo (panel de cliente)

Rama `fix/panel-cola-cupo`, a partir del commit 1333d35. **Nada desplegado ni ejecutado en producción.** Se despliega solo con el sí de Guillem, dado en el chat de la sesión.

## Estado
- Auditoría 66/66 OK: base réplica en Postgres 16 local más Playwright con las RPC simuladas. 170 quitadas con la cola siempre en 315.
- Auditoría, causa del bug de Quitar y plan: https://claude.ai/artifact/HC5iFyquj3fj9LDNrSouod
- Capturas antes/después: https://claude.ai/artifact/MyRmAeVgkhXT93SDERdjUz
- Detalle del SQL: `supabase/pendiente/LEEME.md`. Diseño: `docs/diseno_mi_target.md`.

## Despliegue (proyecto quywrltqzoyyorbsuiwc; nunca Supabase_Tennium)
1. `supabase/pendiente/2026-11-28_00_copia_seguridad.sql`: guarda las 10 funciones actuales.
2. `01_esquema` → `02_catalogos_seed` → `03_funciones` → `04_config`. Son idempotentes.
3. Publicar `panel_cliente.html` y `assets/catalogos.js`.
4. Crear «Deale (prueba)» con estos valores:
   - `is_test = true`, `status = 'active'`;
   - `flujo_v2 = true`, `emails_per_day = 15`, `cola_objetivo_dias = 21` (315/mes);
   - `dias_aprobacion = 14`, `dias_revision = 7`;
   - `envio_pausado = true`, `modo_envio = 'borrador'`, sin Gmail;
   - avisos al email de Guillem;
   - empresas ficticias `@example.invalid`.

**Vuelta atrás en un paso:** ejecutar `2026-11-28_99_vuelta_atras.sql`. Si hace falta, volver a publicar el `panel_cliente.html` de main.

Sin `flujo_v2`, los clientes actuales solo reciben la corrección de Quitar: la quitada desaparece, no hay «Reponer», la sustituta sale de la reserva y, si no hay, queda un aviso.

## Plan de la semana
Está en `docs/plan_prueba_semana.md`: checklist diaria de 9 puntos. Se pasa a Deale con 5 días laborables seguidos sin fallos.

## Reglas
- Las listas (`lotes`) ya creadas no se tocan.
- Los envíos de Reunvo están EN PAUSA: no se reactivan ni se propone reactivarlos. Ningún email a empresas reales.
- Todos los avisos y alertas van a Guillem.
- Nunca mencionar exclusividad. Nunca revelar la reserva de la firma: el mensaje es neutro, «Este tramo no está disponible en esta zona…».
- Nada de datos de clientes o empresas reales en commits ni capturas.

## Pendiente de Guillem
- El sí al despliegue, en el chat de la sesión.
- Filtro de edad del DG con SABI (> 60). Si no hay empresas suficientes, se le dice a Deale y Deale decide.
- Reimportar de SABI, por NIF: resultado, CNAE, código postal y fecha de nacimiento del DG. Sin eso, esos filtros no descartan.
- Ya decidido: aprobar bloquea Quitar (sí); aprobación automática al vencer el plazo (opción A).
