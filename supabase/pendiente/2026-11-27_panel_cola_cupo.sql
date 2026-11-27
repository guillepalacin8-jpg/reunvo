-- =====================================================================================
-- Panel de cliente: cola siempre en el cupo del lote, «Quitar» definitivo con sustituta,
-- y cabecera del lote coherente.
-- PENDIENTE DE APROBACIÓN (Guillem). NO EJECUTADO. Proyecto: quywrltqzoyyorbsuiwc.
-- Va con la rama fix/panel-cola-cupo (panel_cliente.html). El panel nuevo funciona también
-- con las funciones actuales (degrada), pero el cupo y la sustitución correctos necesitan esto.
-- =====================================================================================

-- 1) client_panel
--    · Lote que se enseña: primero el que está en manos del cliente ('cliente'); si no hay,
--      el PRÓXIMO lote aún sin empezar ('guille'/'listo' con inicio futuro); solo si no hay
--      ninguno, el que se está enviando. Antes se enseñaba el que se está enviando (lista
--      vieja, «Lista de 2026-11 · ya revisada · envíos desde 26/10»).
--    · 'objetivo' del lote = cupo (sale del plan al crear el lote), y 'en_curso' para el
--      lote que se está enviando.
--    · 'aprobacion' ya no incluye las quitadas ni las ya enviadas.
CREATE OR REPLACE FUNCTION public.client_panel(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare c record; v jsonb; v_lote uuid; v_curso uuid; t record;
begin
  select * into c from clients where panel_token = p_token and status='active';
  if not found then return jsonb_build_object('error','token'); end if;

  select l.id into v_lote from lotes l
   where l.client_id=c.id
     and (l.estado='cliente'
          or (l.estado in ('guille','listo') and l.inicio_envio > current_date))
   order by case l.estado when 'cliente' then 0 else 1 end, l.inicio_envio limit 1;

  select l.id into v_curso from lotes l
   where l.client_id=c.id and l.estado='enviando'
   order by l.inicio_envio limit 1;

  if v_lote is null then v_lote := v_curso; end if;
  if v_curso = v_lote then v_curso := null; end if;

  select * into t from client_tokens where client_id = c.id::text;

  select jsonb_build_object(
    'cliente', jsonb_build_object('name', coalesce(c.name,c.company), 'plan', c.plan,
                                  'epd', coalesce(c.emails_per_day,10)),
    'gmail', jsonb_build_object(
      'conectado', (t.refresh_token is not null and t.refresh_token <> ''),
      'cuenta', t.gmail_email,
      'caducado', (t.token_expiry is not null and t.token_expiry < now())),
    'kpis', jsonb_build_object(
      'contactadas', (select count(distinct cp.company_id) from campaigns cp where cp.client_id=c.id::text),
      'aperturas',   (select count(distinct e.company_id) from email_events e
                       where e.client_id=c.id and e.event_type='open'),
      'en_cola',     (select count(*) from companies co where co.lote_id=v_lote
                       and co.status='pilot_pending' and not coalesce(co.excluded_by_client,false)
                       and not exists (select 1 from campaigns ca where ca.company_id=co.id
                                        and ca.client_id=c.id::text)),
      'cupo_mes',    coalesce((select l.objetivo from lotes l where l.id=v_lote),
                              coalesce(c.emails_per_day,10) * coalesce(c.cola_objetivo_dias,20)),
      'dossiers_cap', 10,
      'dossiers_usados', (select count(*) from dossier_requests d where d.client_id=c.id
                             and d.requested_at >= date_trunc('month', now()))),
    'stats', jsonb_build_object(
      'facturacion_media', (select round(avg(co.revenue_eur)/1000.0,1) from companies co
                             join campaigns cp on cp.company_id=co.id
                            where cp.client_id=c.id::text and co.revenue_eur is not null),
      'sectores', (select coalesce(jsonb_agg(jsonb_build_object('s',s,'n',n) order by n desc),'[]'::jsonb)
                   from (select co.sector_simplified s, count(*) n from companies co
                          join campaigns cp on cp.company_id=co.id
                         where cp.client_id=c.id::text and co.sector_simplified is not null
                         group by 1 order by 2 desc limit 6) x),
      'ciudades', (select coalesce(jsonb_agg(jsonb_build_object('s',s,'n',n) order by n desc),'[]'::jsonb)
                   from (select co.locality s, count(*) n from companies co
                          join campaigns cp on cp.company_id=co.id
                         where cp.client_id=c.id::text and co.locality is not null
                         group by 1 order by 2 desc limit 6) x)),
    'target', jsonb_build_object('region', c.target_region, 'sector', c.target_sector,
      'rev_min', round(c.target_revenue_min/1000.0), 'rev_max', round(c.target_revenue_max/1000.0)),
    'target_pendiente', (select jsonb_build_object('region',t2.region,'sector',t2.sector,
        'rev_min',t2.rev_min,'rev_max',t2.rev_max,'fecha',t2.requested_at)
       from target_requests t2 where t2.client_id=c.id and t2.status='pendiente'
       order by t2.requested_at desc limit 1),
    'aprobacion', (select coalesce(jsonb_agg(jsonb_build_object(
        'company_id', co.id, 'empresa', co.company_name, 'sector', co.sector_simplified,
        'localidad', co.locality, 'excluida', false)
        order by co.company_name),'[]'::jsonb)
      from companies co where co.lote_id = v_lote and co.status='pilot_pending'
        and not coalesce(co.excluded_by_client,false)
        and not exists (select 1 from campaigns ca where ca.company_id=co.id
                         and ca.client_id=c.id::text)),
    'contactadas', (select coalesce(jsonb_agg(jsonb_build_object(
        'company_id', co.id, 'empresa', co.company_name, 'sector', co.sector_simplified,
        'localidad', co.locality,
        'dossier_pedido', exists(select 1 from dossier_requests d
                                  where d.company_id=co.id and d.client_id=c.id))
        order by co.company_name),'[]'::jsonb)
      from companies co join campaigns cp on cp.company_id=co.id where cp.client_id=c.id::text),
    'dossiers', (select coalesce(jsonb_agg(jsonb_build_object(
        'empresa', d.company_name, 'fecha', d.requested_at, 'status', d.status,
        'delivered_at', d.delivered_at) order by d.requested_at desc),'[]'::jsonb)
      from dossier_requests d where d.client_id=c.id),
    'lote', (select to_jsonb(x) from (
       select l.periodo, l.estado, l.inicio_envio, l.limite_cliente, l.objetivo,
              (select count(*) from companies co where co.lote_id=l.id
                 and co.status='pilot_pending' and not coalesce(co.excluded_by_client,false)
                 and not exists (select 1 from campaigns ca where ca.company_id=co.id
                                  and ca.client_id=c.id::text)) as empresas,
              (select jsonb_build_object('periodo', l2.periodo,
                  'por_enviar', (select count(*) from companies co where co.lote_id=l2.id
                     and co.status='pilot_pending' and not coalesce(co.excluded_by_client,false)
                     and not exists (select 1 from campaigns ca where ca.company_id=co.id
                                      and ca.client_id=c.id::text)))
                 from lotes l2 where l2.id = v_curso) as en_curso
         from lotes l where l.id = v_lote) x)
  ) into v;
  return v;
end $function$;


-- 2) client_toggle_company
--    · Quitar es definitivo: p_exclude=false («Reponer») ya no se acepta desde el panel.
--    · No se puede quitar una empresa ya enviada.
--    · Sustituta: primero la reserva/pool (buscar_reemplazo); si está vacía (hoy lo está:
--      0 elegibles), la primera empresa del SIGUIENTE lote del cliente, que pasa a este.
--      Así la lista del mes se mantiene en el cupo y el déficit se traslada al lote
--      siguiente, que se rellena cuando entre inventario.
--    · Si no hay ninguna, queda anotado en reposicion_requests (como hoy).
--    Ojo: una sustituta que viene del pool entra sin envio_aprobado; si el lote ya está
--    'listo'/'enviando', no saldrá hasta que se apruebe en revisión. Las que vienen del
--    lote siguiente ya traen su aprobación.
CREATE OR REPLACE FUNCTION public.client_toggle_company(p_token text, p_company_id uuid, p_exclude boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare c record; v_nueva record; v_lote uuid; v_ini date; v_id uuid; v_quedan int; v_obj int;
begin
  select * into c from clients where panel_token = p_token and status='active';
  if not found then return jsonb_build_object('error','token'); end if;

  if not coalesce(p_exclude, false) then
    return jsonb_build_object('ok',false,'mensaje','Las empresas quitadas no se pueden reponer.');
  end if;

  select co.lote_id into v_lote from companies co
   where co.id = p_company_id and co.assigned_client_id = c.id and co.status='pilot_pending'
     and not coalesce(co.excluded_by_client,false)
     and not exists (select 1 from campaigns ca where ca.company_id=co.id and ca.client_id=c.id::text)
   for update;
  if not found then return jsonb_build_object('error','no_autorizado'); end if;

  select inicio_envio, objetivo into v_ini, v_obj from lotes where id = v_lote;

  update companies set excluded_by_client = true where id = p_company_id;

  v_id := buscar_reemplazo(c.id);

  if v_id is null and v_lote is not null then
    select co.id into v_id
      from companies co join lotes l on l.id = co.lote_id
     where l.client_id = c.id and co.lote_id <> v_lote and l.inicio_envio > v_ini
       and l.estado in ('cliente','guille','listo')
       and co.assigned_client_id = c.id and co.status = 'pilot_pending'
       and not coalesce(co.excluded_by_client,false)
       and not exists (select 1 from campaigns ca where ca.company_id=co.id and ca.client_id=c.id::text)
     order by l.inicio_envio, co.assigned_at nulls last, co.id
     limit 1
     for update of co skip locked;
  end if;

  if v_id is null then
    insert into reposicion_requests (client_id, company_id, lote_id)
    values (c.id, p_company_id, v_lote)
    on conflict do nothing;
    select count(*) into v_quedan from companies co
     where co.lote_id = v_lote and co.status='pilot_pending'
       and not coalesce(co.excluded_by_client,false);
    return jsonb_build_object('ok',true,'excluida',true,'sin_reemplazo',true,
      'en_lista',v_quedan,'cupo',v_obj,
      'mensaje','Quitada. No quedan empresas en reserva: su lista queda en '||v_quedan||
                ' de '||coalesce(v_obj,v_quedan)||'. La completaremos en cuanto haya.');
  end if;

  update companies set assigned_client_id=c.id, status='pilot_pending',
         excluded_by_client=false, replacement_for=p_company_id,
         assigned_at=now(), lote_id=v_lote
   where id = v_id;
  select * into v_nueva from companies where id = v_id;

  select count(*) into v_quedan from companies co
   where co.lote_id = v_lote and co.status='pilot_pending'
     and not coalesce(co.excluded_by_client,false);

  return jsonb_build_object('ok',true,'excluida',true,
    'nueva', jsonb_build_object('company_id',v_nueva.id,'empresa',v_nueva.company_name,
             'sector',v_nueva.sector_simplified,'localidad',v_nueva.locality),
    'en_lista',v_quedan,'cupo',v_obj,
    'mensaje','Quitada. Ha entrado «'||v_nueva.company_name||'» en su lugar.');
end $function$;


-- 3) CONFIGURACIÓN (decisión de Guillem, comentado a propósito)
--    El único cliente activo tiene dias_aprobacion = 0: sus lotes nacen en 'guille' y nunca
--    pasan por el cliente, así que no tiene fecha límite real (limite_cliente = inicio_envio).
--    Si el cliente debe aprobar antes de una fecha, hace falta dias_aprobacion > 0, p. ej.:
-- update clients set dias_aprobacion = 7 where id = '<id del cliente>';
--    El cupo del lote es emails_per_day * cola_objetivo_dias (hoy 35 * 20 = 700). Si el cupo
--    del mes debe ser 315, hay que fijarlo en el plan del cliente (p. ej. cola_objetivo_dias = 9)
--    y en lotes.objetivo de los lotes abiertos; no está fijado en el código.
