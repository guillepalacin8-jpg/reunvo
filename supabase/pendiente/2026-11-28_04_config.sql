-- =====================================================================================
-- App de Reunvo · semana del 30/11 · 4/4: DATOS Y CONFIGURACIÓN
-- PENDIENTE DE APROBACIÓN (Guillem). NO EJECUTADO. Escribe datos: revisar antes.
-- Idempotente: cada UPDATE solo toca lo que aún no está hecho.
-- Los envíos siguen EN PAUSA por decisión de Guillem: nada de esto los reactiva.
-- =====================================================================================
begin;

-- 1) Región y provincia normalizadas a código INE (a partir del CP y del texto actual).
update public.companies
   set provincia_ine = left(postal_code, 2)
 where provincia_ine is null and postal_code ~ '^\d{5}$'
   and exists (select 1 from public.provincias p where p.codigo = left(postal_code, 2));
update public.companies co
   set ccaa_ine = p.ccaa
  from public.provincias p
 where co.ccaa_ine is null and p.codigo = co.provincia_ine;
update public.companies co
   set ccaa_ine = a.codigo
  from public.ccaa a
 where co.ccaa_ine is null and co.region = a.nombre;

-- 2) Titular de las zonas reservadas = la firma. Solo si hoy hay UN cliente real activo
--    (que es la firma); si hay más, no hace nada y hay que fijarlo a mano por id.
update public.zonas_reservadas z
   set titular = (select id from public.clients where status = 'active' and not coalesce(is_test,false))
 where z.titular is null
   and (select count(*) from public.clients where status = 'active' and not coalesce(is_test,false)) = 1;

-- 3) Plazos (14 + 7), aprobación automática marcada, inicio sin solape, bloqueo de Quitar
--    tras aprobar y sustituta desde la lista siguiente: SOLO para clientes con flujo_v2.
--    A los clientes actuales no se les cambia nada de eso. Para el cliente de prueba:
-- update public.clients set flujo_v2 = true, dias_aprobacion = 14, dias_revision = 7,
--        bloquear_quitar_tras_aprobar = true where id = '<id del cliente de prueba>';

commit;

-- 5) Piloto Deale (cliente aún por crear). Al darlo de alta:
--    emails_per_day = 15, cola_objetivo_dias = 21  → objetivo del lote = 315/mes,
--    dias_aprobacion = 14, dias_revision = 7, usa_reserva según su inventario.
