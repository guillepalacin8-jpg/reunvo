# SQL pendiente (rama fix/panel-v2). NO EJECUTADO.

Orden, en el proyecto de Reunvo (nunca en otro):

0. `2026-11-28_00_copia_seguridad.sql`: guarda las funciones actuales que se sustituyen.
1. `01_esquema` → `02_catalogos_seed` → `03_funciones` (en una transacción).
2. **Antes de 04:** cargar las zonas restringidas desde el fichero NO versionado `supabase/privado/zonas.sql` (lo aporta Guillem; está en `.gitignore`). Sin datos ni titular, `04` falla a propósito.
3. `04_config`.
4. Vuelta atrás: `2026-11-28_99_vuelta_atras.sql`.

Cambios de comportamiento solo para clientes con `flujo_v2`: plazos, fecha de inicio en día laborable, aprobación automática, bloqueo de Quitar tras aprobar. A los clientes actuales solo les llega la corrección de Quitar.

Las listas (`lotes`) existentes no se modifican. Los envíos siguen en pausa: una lista nunca pasa a «enviando» con el envío del cliente en pausa.
