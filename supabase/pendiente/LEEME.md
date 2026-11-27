# SQL pendiente (rama fix/panel-cola-cupo). NO EJECUTADO.

Orden, en el proyecto quywrltqzoyyorbsuiwc (nunca en otro):

0. `2026-11-28_00_copia_seguridad.sql`: guarda la definición actual de las 10 funciones que se van a sustituir.

1. `2026-11-28_01_esquema.sql`: tablas `cnae2009`, `ccaa`, `provincias` y `zonas_reservadas`, con RLS (los catálogos son de lectura pública y `zonas_reservadas` no tiene políticas). También las columnas nuevas de `companies`, `clients`, `target_requests` y `lotes`.
2. `2026-11-28_02_catalogos_seed.sql`: CNAE 2009 (21 secciones y 88 divisiones), 19 CCAA, 52 provincias y 4 zonas reservadas. Se genera con `supabase/catalogos/generar.py`, que también escribe `assets/catalogos.js`.
3. `2026-11-28_03_funciones.sql`: `reunvo_elegible` (una única elegibilidad), reserva, `client_request_target_v2`, `reunvo_aplicar_target`, cola/Quitar con interruptor, plazos, aprobación automática y `reunvo_fin_envios` (una lista nunca empieza antes de que acabe la anterior). El mensaje de zona no disponible es neutro y nunca menciona la reserva.
4. `2026-11-28_04_config.sql`: escribe datos. Normaliza CCAA y provincia, pone de titular de las zonas a la firma (solo si hay un único cliente activo), fija `dias_aprobacion = 14` y deja el interruptor «bloquear Quitar tras aprobar» activado por defecto.

Validado en un Postgres 16 local con una réplica del esquema y datos ficticios: los cuatro ficheros se pueden ejecutar dos veces seguidas sin errores, y los flujos de quitar, reponer, aprobar, aprobar automáticamente, reserva, target y edad dan el resultado esperado.
**Clientes actuales:** sin la bandera `clients.flujo_v2` (por defecto `false`) solo les llega la corrección de Quitar: la quitada desaparece, ya no hay «Reponer», la sustituta sale de la reserva y, si no hay, queda el aviso. Para ellos no cambian ni los plazos, ni la aprobación automática, ni la fecha de inicio, ni el bloqueo tras aprobar, ni se toma la sustituta de la lista siguiente.

**Listas ya creadas:** ningún fichero modifica filas de `lotes`. 01 añade columnas con valor por defecto. 04 solo escribe columnas nuevas de `companies` (código de CCAA y de provincia) y la tabla nueva `zonas_reservadas`.

**Vuelta atrás en un paso:** `2026-11-28_99_vuelta_atras.sql` restaura las funciones guardadas por 00 y elimina las nuevas. Para el panel, se vuelve a publicar `panel_cliente.html` de main.

Los envíos siguen en pausa: nada de esto los reactiva.
