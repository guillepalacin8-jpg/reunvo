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
              (l.cerrado_cliente_at at time zone 'Europe/Madrid')::date as aprobada_el,
              coalesce(l.adelantado,false) as adelantado,
              (select count(*) from companies co where co.lote_id=l.id
                 and co.status='pilot_pending' and not coalesce(co.excluded_by_client,false)
                 and not exists (select 1 from campaigns ca where ca.company_id=co.id
                                  and ca.client_id=c.id::text)) as empresas,
              (select jsonb_build_object('periodo', l2.periodo,
                  'por_enviar', (select count(*) from companies co where co.lote_id=l2.id
                     and co.status='pilot_pending' and not coalesce(co.excluded_by_client,false)
                     and not exists (select 1 from campaigns ca where ca.company_id=co.id
                                      and ca.client_id=c.id::text)))
                 from lotes l2 where l2.id = v_curso) as en_curso,
              -- Lista ya aprobada que aún no ha empezado (tras aprobar se crea la siguiente y
              -- pasa a ser la principal; ésta se resume en una línea).
              (select jsonb_build_object('periodo', l3.periodo, 'inicio_envio', l3.inicio_envio,
                      'adelantado', coalesce(l3.adelantado,false))
                 from lotes l3 where l3.client_id=c.id and l3.id <> l.id
                  and l3.estado in ('guille','listo') and l3.inicio_envio > current_date
                order by l3.inicio_envio limit 1) as aprobada
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


-- 3) PLAZOS (decisión de Guillem, 27-nov)
--    · dias_aprobacion = 14: el cliente tiene 2 semanas para revisar y aprobar.
--    · Cada lote tiene un inicio de envíos fijado; fecha límite = inicio − 7
--      (esa semana es para revisar los correos). Los 7 días son un dato: clients.dias_revision.
--    · Si el cliente aprueba antes, los envíos empiezan 7 días después de su aprobación
--      (nunca más tarde de lo previsto): lotes.adelantado = true.
alter table public.clients add column if not exists dias_revision integer not null default 7;
alter table public.lotes   add column if not exists adelantado boolean not null default false;

CREATE OR REPLACE FUNCTION public.reunvo_crear_lote(p_client_id uuid, p_inicio date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare c record; v_ini date; v_per text; v_obj int; v_id uuid; v_n int; v_estado text;
        v_apr int; v_rev int; v_min date;
begin
  select * into c from clients where id = p_client_id;
  if not found then return jsonb_build_object('ok',false,'mensaje','cliente no existe'); end if;

  v_apr := coalesce(c.dias_aprobacion,7);
  v_rev := coalesce(c.dias_revision,7);

  v_ini := coalesce(p_inicio,
    (select max(inicio_envio) + coalesce(c.cola_objetivo_dias,20) from lotes where client_id = p_client_id),
    (current_date + 1));
  -- El cliente tiene que tener sus días de aprobación completos + la semana de revisión.
  v_min := current_date + (case when v_apr > 0 then v_apr + v_rev else 1 end);
  if v_ini < v_min then v_ini := v_min; end if;

  v_per := to_char(v_ini,'YYYY-MM');
  while exists (select 1 from lotes where client_id=p_client_id and periodo=v_per) loop
    v_ini := v_ini + 30; v_per := to_char(v_ini,'YYYY-MM');
  end loop;

  v_obj := coalesce(c.emails_per_day,10) * coalesce(c.cola_objetivo_dias,20);
  v_estado := case when v_apr = 0 then 'guille' else 'cliente' end;

  insert into lotes(client_id, periodo, estado, objetivo, inicio_envio, limite_cliente, cerrado_cliente_at)
  values (p_client_id, v_per, v_estado, v_obj, v_ini,
          case when v_apr > 0 then v_ini - v_rev else v_ini end,
          case when v_estado='guille' then now() end)
  returning id into v_id;

  with elegibles as (
    select co.id, (co.revenue_eur is null) as sin_dato from companies co
    where reunvo_disponible(co.status, co.assigned_client_id, p_client_id, c.usa_reserva) and co.email_verified
      and co.contact_email is not null and co.shareholder_first is not null
      and co.sector_simplified is not null
      and (case when coalesce(c.target_region,'') = 'DEMO'
                then coalesce(co.region,'') = 'DEMO'
                else coalesce(co.region,'') <> 'DEMO' end)
      and (c.target_region is null or co.region = c.target_region)
      and (c.target_sector is null or co.sector_simplified = c.target_sector)
      and en_tramo(co.revenue_eur, c.target_revenue_min, c.target_revenue_max)
    order by (co.revenue_eur is null) asc,
             es_probable_filial(co.company_name) asc,
             (co.domain is not null) desc,
             coalesce(length(co.activity_description),0) desc, co.id
    limit v_obj
  )
  update companies co set status='pilot_pending', assigned_client_id=p_client_id,
         assigned_at=now(), lote_id=v_id, sin_tramo_confirmado = e.sin_dato
    from elegibles e where co.id = e.id;
  get diagnostics v_n = row_count;

  return jsonb_build_object('ok',true,'lote',v_id,'periodo',v_per,'estado',v_estado,
    'objetivo',v_obj,'asignadas',v_n,'inicio_envio',v_ini,
    'sin_tramo_confirmado',(select count(*) from companies where lote_id=v_id and sin_tramo_confirmado),
    'limite_cliente', case when v_apr > 0 then v_ini - v_rev else v_ini end,
    'sin_inventario', v_n < v_obj);
end $function$;

-- Aprobación del cliente: adelanta el inicio a aprobación + dias_revision si cae antes.
CREATE OR REPLACE FUNCTION public.client_lote_verificado(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_cli uuid; v_rev int; v_lote record; v_n int; v_ini date; v_hoy date;
begin
  select id, coalesce(dias_revision,7) into v_cli, v_rev
    from clients where panel_token = p_token and status='active';
  if v_cli is null then return jsonb_build_object('ok',false,'mensaje','token'); end if;

  select * into v_lote from lotes
   where client_id=v_cli and estado='cliente' order by inicio_envio limit 1 for update;
  if not found then
    return jsonb_build_object('ok',false,
      'mensaje','Ahora mismo no tiene ninguna lista pendiente de aprobar.'); end if;

  v_hoy := (now() at time zone 'Europe/Madrid')::date;
  v_ini := least(v_lote.inicio_envio, v_hoy + v_rev);

  update lotes set estado='guille', cerrado_cliente_at=now(),
         inicio_envio = v_ini, adelantado = (v_ini < v_lote.inicio_envio)
   where id=v_lote.id;
  select count(*) into v_n from companies where lote_id=v_lote.id
    and status='pilot_pending' and not coalesce(excluded_by_client,false);

  perform reunvo_ciclo_lotes();   -- encadena el siguiente lote de inmediato

  return jsonb_build_object('ok',true,'inicio_envio',v_ini,
    'adelantado', v_ini < v_lote.inicio_envio,
    'mensaje','Lista de '||v_lote.periodo||' aprobada ('||v_n||' empresas). Envíos a partir del '||
              to_char(v_ini,'DD/MM')||
              case when v_ini < v_lote.inicio_envio then ' (7 días tras su aprobación).' else '.' end);
end $function$;

-- Ojo, encadenado: el siguiente lote se calcula con max(inicio_envio) + cola_objetivo_dias.
-- Si un lote se adelanta, el siguiente también se adelanta, pero reunvo_crear_lote lo empuja
-- como mínimo a hoy + 14 + 7, así que el cliente siempre tiene sus 2 semanas.

-- 4) CONFIGURACIÓN
--    Aplicar el plazo de 14 días. Con esto los lotes nuevos pasan por el cliente y
--    reunvo_ciclo_lotes() crea en su siguiente pasada un lote en estado 'cliente' para quien
--    no lo tenga. Los envíos siguen en pausa: esto no los reactiva.
update public.clients set dias_aprobacion = 14 where status = 'active';
--    El cupo del lote es emails_per_day * cola_objetivo_dias. Para el piloto Deale (por crear):
--    emails_per_day = 15; para 315/mes, cola_objetivo_dias = 21.
