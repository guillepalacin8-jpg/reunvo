# SQL pendiente (rama fix/panel-cola-cupo). NO EJECUTADO.

Orden, en el proyecto quywrltqzoyyorbsuiwc (nunca en otro):

1. `2026-11-28_01_esquema.sql`: tablas `cnae2009`, `ccaa`, `provincias` y `zonas_reservadas`, con RLS (los catálogos son de lectura pública y `zonas_reservadas` no tiene políticas). También las columnas nuevas de `companies`, `clients`, `target_requests` y `lotes`.
2. `2026-11-28_02_catalogos_seed.sql`: CNAE 2009 (21 secciones y 88 divisiones), 19 CCAA, 52 provincias y 4 zonas reservadas. Se genera con `supabase/catalogos/generar.py`, que también escribe `assets/catalogos.js`.
3. `2026-11-28_03_funciones.sql`: `reunvo_elegible` (una única elegibilidad), reserva, `client_request_target_v2`, `reunvo_aplicar_target`, cola/Quitar con interruptor, plazos, aprobación automática y `reunvo_fin_envios` (una lista nunca empieza antes de que acabe la anterior). El mensaje de zona no disponible es neutro y nunca menciona la reserva.
4. `2026-11-28_04_config.sql`: escribe datos. Normaliza CCAA y provincia, pone de titular de las zonas a la firma (solo si hay un único cliente activo), fija `dias_aprobacion = 14` y deja el interruptor «bloquear Quitar tras aprobar» activado por defecto.

Validado en un Postgres 16 local con una réplica del esquema y datos ficticios: los cuatro ficheros se pueden ejecutar dos veces seguidas sin errores, y los flujos de quitar, reponer, aprobar, aprobar automáticamente, reserva, target y edad dan el resultado esperado.
Los envíos siguen en pausa: nada de esto los reactiva.
