-- 07 · RELLENO DEL DUEÑO CON EL HISTORIAL DEL CLIENTE ACTUAL. NO EJECUTADO. Escribe datos: necesita el sí de Guillem.
-- Requiere 06. Idempotente (solo filas sin dueño). Falla si no hay exactamente UN cliente real activo.
-- Antes: SELECT de comprobación (más abajo) y copia de las columnas nuevas no hace falta (están vacías); la vuelta
-- atrás es 2026-11-28_07_99_vuelta_atras.sql.
begin;
do $$
declare v_cli uuid; v_n int;
begin
  select count(*) into v_n from public.clients where status='active' and not coalesce(is_test,false);
  if v_n <> 1 then raise exception 'se esperaba exactamente 1 cliente real activo, hay %', v_n; end if;
  select id into v_cli from public.clients where status='active' and not coalesce(is_test,false);

  -- 1) Empresas con envío: dueño = cliente actual, 12 meses desde su primer envío
  update public.companies co set cliente_id_asignado = v_cli, asignada_desde = e.primer,
         asignada_hasta = e.primer + interval '12 months'
    from (select company_id, min(coalesce(sent_at, created_at)) primer from public.campaigns
           where client_id = v_cli::text and status = 'sent' group by 1) e
   where co.id = e.company_id and co.cliente_id_asignado is null;

  -- 2) Con borrador sin envío, o ya en su lista pendiente: reservadas (sin plazo hasta el primer envío)
  update public.companies co set cliente_id_asignado = v_cli, asignada_desde = now(), asignada_hasta = null
   where co.cliente_id_asignado is null
     and (co.id in (select company_id from public.campaigns where client_id = v_cli::text and status = 'draft_created')
          or (co.assigned_client_id = v_cli and co.status = 'pilot_pending' and not coalesce(co.excluded_by_client,false)));

  -- 3) Mismo dueño para las filas con el mismo NIF, dominio o email
  update public.companies o set cliente_id_asignado = v_cli, asignada_desde = s.desde, asignada_hasta = s.hasta
    from (select distinct on (o2.id) o2.id, d.asignada_desde desde, d.asignada_hasta hasta
            from public.companies o2 join public.companies d on d.cliente_id_asignado = v_cli and d.id <> o2.id
             and ((o2.nif is not null and o2.nif = d.nif)
                  or (o2.domain is not null and lower(o2.domain) = lower(d.domain))
                  or (o2.contact_email is not null and lower(o2.contact_email) = lower(d.contact_email)))
           where o2.cliente_id_asignado is null
           order by o2.id, d.asignada_hasta desc nulls first) s
   where o.id = s.id and o.cliente_id_asignado is null;
end $$;
commit;
select cliente_id_asignado, count(*) filter (where asignada_hasta is null) reservadas,
       count(*) filter (where asignada_hasta is not null) con_plazo, min(asignada_hasta) primer_vencimiento
  from public.companies where cliente_id_asignado is not null group by 1;
