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

-- 3) Plazos: 14 días para aprobar; fecha límite = inicio − 7 (dias_revision, por defecto 7).
--    Con esto los lotes nuevos pasan por el cliente y reunvo_ciclo_lotes() crea en su
--    siguiente pasada un lote 'cliente' para quien no lo tenga.
update public.clients set dias_aprobacion = 14
 where status = 'active' and coalesce(dias_aprobacion, -1) <> 14;

-- 4) Interruptor «aprobar bloquea Quitar». Recomendado: true (valor por defecto de la columna).
--    Para permitir quitar tras aprobar en un cliente concreto:
-- update public.clients set bloquear_quitar_tras_aprobar = false where id = '<id>';

commit;

-- 5) Piloto Deale (cliente aún por crear). Al darlo de alta:
--    emails_per_day = 15, cola_objetivo_dias = 21  → objetivo del lote = 315/mes,
--    dias_aprobacion = 14, dias_revision = 7, usa_reserva según su inventario.
