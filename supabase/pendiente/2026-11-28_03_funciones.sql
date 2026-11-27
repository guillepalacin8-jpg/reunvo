-- =====================================================================================
-- App de Reunvo · semana del 30/11 · 3/4: FUNCIONES
-- PENDIENTE DE APROBACIÓN (Guillem). NO EJECUTADO. Requiere 01_esquema y 02_catalogos_seed.
-- Idempotente (create or replace). No cambia firmas existentes: el panel desplegado hoy
-- sigue funcionando con estas funciones.
-- =====================================================================================

-- ---- Zonas reservadas a la firma ------------------------------------------------------
-- ¿Choca un target pedido con una zona reservada? Devuelve el motivo o null.
-- Choca si la CCAA está reservada a otro cliente y el tramo pedido se SOLAPA con el
-- reservado (no hace falta que esté dentro). Pedir por facturación en una CCAA reservada
-- se permite: las empresas del tramo reservado se excluyen igualmente en reunvo_elegible.
CREATE OR REPLACE FUNCTION public.reunvo_choca_reserva(p_client uuid, p_ccaa text, p_metric text,
                                                       p_min_eur numeric, p_max_eur numeric)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- Mensaje neutro a propósito: el cliente no debe saber que hay una reserva ni de quién.
  select 'Este tramo no está disponible en esta zona; elija otro tramo u otra comunidad.'::text
    from zonas_reservadas z
   where z.activa and z.ccaa = p_ccaa and z.metric = p_metric
     and z.titular is distinct from p_client
     and coalesce(p_min_eur, 0) <= z.max_eur
     and coalesce(p_max_eur, 'Infinity'::numeric) >= z.min_eur
   limit 1;
$function$;

-- ¿Está esta empresa en el perímetro reservado a otro cliente?
-- Sin resultado conocido, cuenta como reservada si vino de SABI con el criterio de la
-- firma ('resultado 400k-50M'). Una zona sin titular no excluye a nadie (hay que fijarlo
-- en 04_config): así la firma nunca se queda sin su propio universo por un olvido.
CREATE OR REPLACE FUNCTION public.reunvo_empresa_reservada(co public.companies, p_client uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1 from zonas_reservadas z
     where z.activa and z.titular is not null and z.titular <> p_client
       and z.ccaa = co.ccaa_ine
       and case z.metric
             when 'result'  then coalesce(co.result_eur between z.min_eur and z.max_eur,
                                          co.criterio_sabi = 'resultado 400k-50M')
             else coalesce(co.revenue_eur * 1000 between z.min_eur and z.max_eur, false)
           end);
$function$;

-- ---- Elegibilidad única ----------------------------------------------------------------
-- Una sola definición de «esta empresa vale para este cliente». La usan crear_lote,
-- buscar_reemplazo, reponer_cola y mantener_colas (antes cada una filtraba a su manera).
-- Unidades: revenue_eur está en miles de € (así lo trata la app); result_eur y los
-- target_*_eur, en €. Dato desconocido = no descarta (como en_tramo).
CREATE OR REPLACE FUNCTION public.reunvo_elegible(co public.companies, c public.clients)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select
    reunvo_disponible(co.status, co.assigned_client_id, c.id, c.usa_reserva)
    and co.email_verified and co.contact_email is not null
    and co.shareholder_first is not null and co.sector_simplified is not null
    -- DEMO solo para el cliente DEMO
    and (case when coalesce(c.target_region,'') = 'DEMO'
              then coalesce(co.region,'') = 'DEMO' else coalesce(co.region,'') <> 'DEMO' end)
    -- Región: CCAA y provincias (nuevo) o el texto antiguo target_region
    and (case
           when c.target_ccaa is not null then
             coalesce(co.ccaa_ine = c.target_ccaa,
                      co.region = (select nombre from ccaa where codigo = c.target_ccaa))
             and (coalesce(cardinality(c.target_provincias),0) = 0
                  or co.provincia_ine is null or co.provincia_ine = any(c.target_provincias))
           else c.target_region is null or c.target_region = 'DEMO' or co.region = c.target_region
         end)
    -- Sector: CNAE (secciones o divisiones); sin CNAE en la empresa, por su etiqueta
    and (case
           when coalesce(cardinality(c.target_cnae),0) > 0 then
             case when co.cnae is not null then
               exists (select 1 from unnest(c.target_cnae) x
                        where left(co.cnae,2) = x
                           or exists (select 1 from cnae2009 d
                                       where d.padre = x and d.codigo = left(co.cnae,2)))
             else
               co.sector_simplified in (select d.sector_simplified from cnae2009 d
                                         where d.codigo = any(c.target_cnae)
                                            or d.padre  = any(c.target_cnae))
             end
           else c.target_sector is null or co.sector_simplified = c.target_sector
         end)
    -- Criterio económico: facturación O resultado, con mínimo y máximo
    and (case coalesce(c.target_metric,'revenue')
           when 'result' then
             co.result_eur is null
             or ((c.target_min_eur is null or co.result_eur >= c.target_min_eur)
                 and (c.target_max_eur is null or co.result_eur <= c.target_max_eur))
           else
             en_tramo(co.revenue_eur,
                      coalesce(c.target_min_eur/1000, c.target_revenue_min),
                      coalesce(c.target_max_eur/1000, c.target_revenue_max))
         end)
    -- Edad mínima del DG o administrador
    and (c.target_edad_min is null or co.dg_fecha_nacimiento is null
         or co.dg_fecha_nacimiento <= current_date - make_interval(years => c.target_edad_min))
    -- Perímetro reservado a otro cliente
    and not reunvo_empresa_reservada(co, c.id);
$function$;

CREATE OR REPLACE FUNCTION public.buscar_reemplazo(p_client_id uuid)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select co.id from companies co, clients c
   where c.id = p_client_id
     and reunvo_elegible(co, c)
     and coalesce(co.activity_description,'') <> ''
   order by (co.revenue_eur is null) asc,
            es_probable_filial(co.company_name) asc,
            (co.domain is not null) desc,
            coalesce(length(co.activity_description),0) desc, co.id
   limit 1;
$function$;

CREATE OR REPLACE FUNCTION public.reunvo_reponer_cola(p_token text, p_client_id uuid, p_n integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare c public.clients%rowtype; n int;
begin
  if not public.reunvo_es_admin(p_token) then
    return jsonb_build_object('ok',false,'mensaje','unauthorized'); end if;
  select * into c from clients where id = p_client_id;
  if not found then return jsonb_build_object('ok',false,'mensaje','cliente no existe'); end if;
  if p_n is null or p_n <= 0 or p_n > 500 then
    return jsonb_build_object('ok',false,'mensaje','p_n debe estar entre 1 y 500'); end if;

  with elegibles as (
    select co.id, (co.revenue_eur is null) as sin_dato from companies co
    where reunvo_elegible(co, c)
    order by (co.revenue_eur is null) asc,
             es_probable_filial(co.company_name) asc,
             (co.domain is not null) desc,
             coalesce(length(co.activity_description),0) desc, co.id
    limit p_n
  )
  update companies co set status='pilot_pending', assigned_client_id=p_client_id,
         assigned_at=now(), sin_tramo_confirmado = e.sin_dato
    from elegibles e where co.id = e.id;
  get diagnostics n = row_count;
  return jsonb_build_object('ok',true,'asignadas',n,
    'cola_total',(select count(*) from companies where assigned_client_id=p_client_id
                    and status='pilot_pending' and not coalesce(excluded_by_client,false)));
end $function$;

CREATE OR REPLACE FUNCTION public.reunvo_mantener_colas()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare c public.clients%rowtype; v_obj int; v_hay int; v_falta int; v_asig int; v_out jsonb := '[]'::jsonb;
begin
  for c in
    select * from clients
     where status='active' and not coalesce(is_test,false)
       and not coalesce(envio_pausado,false) and html_template is not null
  loop
    v_obj := coalesce(c.emails_per_day,10) * coalesce(c.cola_objetivo_dias,20);

    select count(*) into v_hay
      from companies co
     where co.assigned_client_id = c.id and co.status='pilot_pending'
       and not coalesce(co.excluded_by_client,false)
       and co.contact_email is not null and co.email_verified
       and co.shareholder_first is not null and co.sector_simplified is not null
       and not exists (select 1 from campaigns ca
                        where ca.company_id=co.id and ca.client_id=c.id::text);

    v_falta := greatest(v_obj - v_hay, 0);
    v_asig := 0;

    if v_falta > 0 then
      with elegibles as (
        select co.id from companies co
        where reunvo_elegible(co, c)
        order by es_probable_filial(co.company_name) asc,
                 (co.domain is not null) desc,
                 coalesce(length(co.activity_description),0) desc,
                 co.id
        limit v_falta
      )
      update companies set status='pilot_pending', assigned_client_id=c.id, assigned_at=now()
       where id in (select id from elegibles);
      get diagnostics v_asig = row_count;
    end if;

    v_out := v_out || jsonb_build_object(
      'cliente', coalesce(c.name, c.company),
      'objetivo', v_obj, 'tenia', v_hay, 'asignadas', v_asig,
      'cola_final', v_hay + v_asig,
      'sin_inventario', (v_hay + v_asig) < v_obj);
  end loop;
  return jsonb_build_object('ts', now(), 'clientes', v_out);
end $function$;

-- ---- Target: solicitud del cliente (nuevo) y aplicación por Reunvo ---------------------
-- La función antigua se mantiene (el panel la usa si falta la nueva) pero sin mencionar
-- el texto antiguo del mensaje, que no se dice al cliente.
CREATE OR REPLACE FUNCTION public.client_request_target(p_token text, p_region text, p_sector text, p_rev_min numeric, p_rev_max numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v uuid;
begin
  select id into v from clients where panel_token=p_token;
  if v is null then return jsonb_build_object('error','token'); end if;
  insert into target_requests(client_id,region,sector,rev_min,rev_max,requested_at,status)
    values(v,nullif(trim(p_region),''),nullif(trim(p_sector),''),p_rev_min,p_rev_max,now(),'pendiente');
  return jsonb_build_object('ok',true,'mensaje','Solicitud enviada. La revisaremos y se la confirmaremos.');
end;$function$;

-- p_target: {"metric":"revenue|result","min_meur":n,"max_meur":n,"ccaa":"09",
--            "provincias":["08"],"cnae":["C","46"],"edad_min":55}
CREATE OR REPLACE FUNCTION public.client_request_target_v2(p_token text, p_target jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v uuid; v_metric text; v_min numeric; v_max numeric; v_ccaa text; v_prov text[];
        v_cnae text[]; v_edad int; v_choca text; v_mal text;
begin
  select id into v from clients where panel_token = p_token and status = 'active';
  if v is null then return jsonb_build_object('error','token'); end if;

  v_metric := coalesce(nullif(p_target->>'metric',''),'revenue');
  if v_metric not in ('revenue','result') then
    return jsonb_build_object('ok',false,'mensaje','Elija facturación o resultado.'); end if;
  begin
    v_min  := nullif(p_target->>'min_meur','')::numeric * 1e6;
    v_max  := nullif(p_target->>'max_meur','')::numeric * 1e6;
    v_edad := nullif(p_target->>'edad_min','')::int;
  exception when others then
    return jsonb_build_object('ok',false,'mensaje','Revise las cifras: solo números.');
  end;
  if v_metric = 'revenue' and (coalesce(v_min,0) < 0 or coalesce(v_max,0) < 0) then
    return jsonb_build_object('ok',false,'mensaje','La facturación no puede ser negativa.'); end if;
  if v_min is not null and v_max is not null and v_min > v_max then
    return jsonb_build_object('ok',false,'mensaje','El mínimo es mayor que el máximo.'); end if;
  if v_edad is not null and (v_edad < 18 or v_edad > 100) then
    return jsonb_build_object('ok',false,'mensaje','La edad mínima debe estar entre 18 y 100 años.'); end if;

  v_ccaa := nullif(p_target->>'ccaa','');
  if v_ccaa is not null and not exists (select 1 from ccaa where codigo = v_ccaa) then
    return jsonb_build_object('ok',false,'mensaje','Comunidad no válida.'); end if;
  select coalesce(array_agg(x),'{}') into v_prov from jsonb_array_elements_text(coalesce(p_target->'provincias','[]')) x;
  select string_agg(x, ', ') into v_mal from unnest(v_prov) x
   where not exists (select 1 from provincias p where p.codigo = x and p.ccaa = v_ccaa);
  if v_mal is not null then
    return jsonb_build_object('ok',false,'mensaje','Provincia fuera de la comunidad elegida.'); end if;
  select coalesce(array_agg(x),'{}') into v_cnae from jsonb_array_elements_text(coalesce(p_target->'cnae','[]')) x;
  select string_agg(x, ', ') into v_mal from unnest(v_cnae) x
   where not exists (select 1 from cnae2009 d where d.codigo = x);
  if v_mal is not null then
    return jsonb_build_object('ok',false,'mensaje','Sector no válido: '||v_mal); end if;

  v_choca := reunvo_choca_reserva(v, v_ccaa, v_metric, v_min, v_max);
  if v_choca is not null then
    return jsonb_build_object('ok',false,'reservada',true,'mensaje',v_choca); end if;

  -- Una sola solicitud pendiente por cliente: la nueva sustituye a la anterior.
  update target_requests set status='sustituida' where client_id = v and status = 'pendiente';

  insert into target_requests (client_id, region, sector, rev_min, rev_max, requested_at, status,
                               metric, min_eur, max_eur, cnae, ccaa, provincias, edad_min, meta)
  values (v,
          (select nombre from ccaa where codigo = v_ccaa),
          (select string_agg(titulo, ' / ') from cnae2009 where codigo = any(v_cnae)),
          case when v_metric='revenue' then v_min/1e6 end,
          case when v_metric='revenue' then v_max/1e6 end,
          now(), 'pendiente',
          v_metric, v_min, v_max, nullif(v_cnae,'{}'), v_ccaa, nullif(v_prov,'{}'), v_edad,
          jsonb_build_object('origen','panel_v2'));

  return jsonb_build_object('ok',true,
    'mensaje','Solicitud enviada. La revisaremos y se la confirmaremos.');
end $function$;

CREATE OR REPLACE FUNCTION public.reunvo_aplicar_target(p_token text, p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare t record; v_min numeric; v_max numeric; v_aviso text := null; v_choca text;
begin
  if not public.reunvo_es_admin(p_token) then
    return jsonb_build_object('ok',false,'mensaje','unauthorized'); end if;
  select * into t from target_requests where id = p_request_id;
  if not found then return jsonb_build_object('ok',false,'mensaje','no existe'); end if;
  if t.status <> 'pendiente' then
    return jsonb_build_object('ok',false,'mensaje','ya estaba '||t.status); end if;

  if t.metric is not null then
    -- Solicitud del panel nuevo: se vuelve a comprobar la reserva (puede haber cambiado).
    v_choca := reunvo_choca_reserva(t.client_id, t.ccaa, t.metric, t.min_eur, t.max_eur);
    if v_choca is not null then
      return jsonb_build_object('ok',false,'mensaje',v_choca); end if;
    update clients
       set target_metric = t.metric, target_min_eur = t.min_eur, target_max_eur = t.max_eur,
           target_cnae = t.cnae, target_ccaa = t.ccaa, target_provincias = t.provincias,
           target_edad_min = t.edad_min,
           -- compatibilidad con lo que aún lee los campos antiguos (revision_cola, admin)
           target_region = coalesce(t.region, target_region),
           target_sector = case when t.cnae is null then null else target_sector end,
           target_revenue_min = case when t.metric='revenue' then t.min_eur/1000 end,
           target_revenue_max = case when t.metric='revenue' then t.max_eur/1000 end
     where id = t.client_id;
    update target_requests set status='aplicada' where id = p_request_id;
    return jsonb_build_object('ok',true,'mensaje','Target aplicado.');
  end if;

  -- Solicitud antigua (texto libre): comportamiento de siempre.
  v_min := case when t.rev_min is null then null else t.rev_min * 1000 end;
  v_max := case when t.rev_max is null then null else t.rev_max * 1000 end;
  if coalesce(t.rev_min,0) > 1000 or coalesce(t.rev_max,0) > 1000 then
    v_aviso := 'Las cifras parecen estar ya en miles, no en M€. Comprueba antes de crear el lote.';
  end if;
  update clients
     set target_region = coalesce(nullif(trim(t.region),''), target_region),
         target_sector = nullif(trim(t.sector),''),
         target_revenue_min = v_min,
         target_revenue_max = v_max
   where id = t.client_id;
  update target_requests set status='aplicada' where id = p_request_id;
  return jsonb_build_object('ok',true,
    'aplicado', jsonb_build_object('region',t.region,'sector',t.sector,
        'rev_min_miles',v_min,'rev_max_miles',v_max),
    'aviso', v_aviso,
    'mensaje','Target aplicado: '||coalesce(t.region,'cualquier región')
      ||coalesce(' · '||nullif(trim(t.sector),''),'')
      ||coalesce(' · '||t.rev_min||'-'||t.rev_max||' M€',''));
end $function$;

-- ---- Cola, Quitar, plazos y aprobación (antes en 2026-11-27_panel_cola_cupo.sql) -------

-- Primer día de envío libre para el lote p_lote: el día de envío siguiente a aquel en que,
-- al ritmo del plan (emails_per_day en sus dias_envio), se acaba lo pendiente de las listas
-- ANTERIORES del mismo cliente que ya se envían o están aprobadas. Sin pendiente: null.
-- Es una estimación (supone que se envía todos los días de envío); dos listas nunca se solapan.
CREATE OR REPLACE FUNCTION public.reunvo_fin_envios(p_lote uuid)
 RETURNS date
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare l record; c record; v_pend int; v_n int; v_ult date; v_dias int[];
begin
  select * into l from lotes where id = p_lote;
  if not found then return null; end if;
  select * into c from clients where id = l.client_id;
  v_dias := coalesce(c.dias_envio, '{1,2,3,4,5}');

  select count(*) into v_pend
    from companies co join lotes lo on lo.id = co.lote_id
   where lo.client_id = l.client_id and lo.id <> l.id and lo.periodo < l.periodo
     and lo.estado in ('enviando','listo','guille')
     and co.status = 'pilot_pending' and not coalesce(co.excluded_by_client,false)
     and not exists (select 1 from campaigns ca where ca.company_id = co.id
                      and ca.client_id = l.client_id::text);
  if v_pend = 0 then return null; end if;

  v_n := ceil(v_pend::numeric / greatest(coalesce(c.emails_per_day,10),1))::int;
  -- último día de envío necesario, contando desde mañana (lo de hoy puede haber salido ya)
  select d::date into v_ult
    from generate_series(current_date + 1, current_date + 730, interval '1 day') d
   where extract(isodow from d)::int = any(v_dias)
   order by d offset v_n - 1 limit 1;
  -- y el siguiente día de envío es el primero libre
  return (select d::date from generate_series(v_ult + 1, v_ult + 14, interval '1 day') d
           where extract(isodow from d)::int = any(v_dias) order by d limit 1);
end $function$;

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
      'rev_min', round(c.target_revenue_min/1000.0), 'rev_max', round(c.target_revenue_max/1000.0),
      'metric', coalesce(c.target_metric,'revenue'),
      'min_meur', round(coalesce(c.target_min_eur, c.target_revenue_min*1000)/1e6, 2),
      'max_meur', round(coalesce(c.target_max_eur, c.target_revenue_max*1000)/1e6, 2),
      'cnae', to_jsonb(c.target_cnae), 'ccaa', c.target_ccaa,
      'provincias', to_jsonb(c.target_provincias), 'edad_min', c.target_edad_min),
    'target_pendiente', (select jsonb_build_object('region',t2.region,'sector',t2.sector,
        'rev_min',t2.rev_min,'rev_max',t2.rev_max,'fecha',t2.requested_at,
        'metric',t2.metric,'min_meur',round(t2.min_eur/1e6,2),'max_meur',round(t2.max_eur/1e6,2),
        'cnae',to_jsonb(t2.cnae),'ccaa',t2.ccaa,'provincias',to_jsonb(t2.provincias),'edad_min',t2.edad_min)
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
       select l.periodo, l.estado, l.limite_cliente, l.objetivo,
              -- Pendiente de aprobar: se enseña el inicio real previsto (nunca antes de que
              -- acabe la lista en curso). Ya aprobada: el que quedó fijado.
              case when l.estado = 'cliente'
                   then greatest(l.inicio_envio, coalesce(reunvo_fin_envios(l.id), l.inicio_envio))
                   else l.inicio_envio end as inicio_envio,
              case when l.estado = 'cliente'
                   then case when reunvo_fin_envios(l.id) > l.inicio_envio then 'fin_en_curso' else 'fecha_fijada' end
                   else l.inicio_motivo end as inicio_motivo,
              (l.cerrado_cliente_at at time zone 'Europe/Madrid')::date as aprobada_el,
              coalesce(l.adelantado,false) as adelantado,
              coalesce(l.aprobado_auto,false) as aprobado_auto,
              -- Interruptor: tras aprobar (cliente o automática) ¿se puede seguir quitando?
              (l.estado = 'cliente' or not coalesce(c.bloquear_quitar_tras_aprobar,true)) as puede_quitar,
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
                      'adelantado', coalesce(l3.adelantado,false), 'inicio_motivo', l3.inicio_motivo,
                      'aprobado_auto', coalesce(l3.aprobado_auto,false),
                      'aprobada_el', (l3.cerrado_cliente_at at time zone 'Europe/Madrid')::date)
                 from lotes l3 where l3.client_id=c.id and l3.id <> l.id
                  and l3.estado in ('guille','listo') and l3.inicio_envio > current_date
                order by l3.inicio_envio limit 1) as aprobada
         from lotes l where l.id = v_lote) x)
  ) into v;
  return v;
end $function$;

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

  -- Interruptor (recomendado: activado). Aprobada la lista, ya no se quita nada.
  if coalesce(c.bloquear_quitar_tras_aprobar,true)
     and exists (select 1 from lotes where id = v_lote and estado <> 'cliente') then
    return jsonb_build_object('ok',false,
      'mensaje','Esta lista ya está aprobada y no admite cambios.');
  end if;

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

CREATE OR REPLACE FUNCTION public.reunvo_crear_lote(p_client_id uuid, p_inicio date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare c public.clients%rowtype; v_ini date; v_per text; v_obj int; v_id uuid; v_n int; v_estado text;
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
    where reunvo_elegible(co, c)
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

CREATE OR REPLACE FUNCTION public.client_lote_verificado(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_cli uuid; v_rev int; v_lote record; v_n int; v_ini date; v_hoy date; v_fin date; v_mot text;
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
  -- Inicio = la fecha más tardía entre «aprobación + 7» (sin pasar de la fecha fijada) y el
  -- final de la lista que se está enviando. Nunca se solapan dos listas.
  v_fin := reunvo_fin_envios(v_lote.id);
  v_ini := least(v_lote.inicio_envio, v_hoy + v_rev);
  v_mot := case when v_ini < v_lote.inicio_envio then 'aprobacion' else 'fecha_fijada' end;
  if v_fin is not null and v_fin > v_ini then v_ini := v_fin; v_mot := 'fin_en_curso'; end if;

  update lotes set estado='guille', cerrado_cliente_at=now(),
         inicio_envio = v_ini, adelantado = (v_ini < v_lote.inicio_envio), inicio_motivo = v_mot
   where id=v_lote.id;
  select count(*) into v_n from companies where lote_id=v_lote.id
    and status='pilot_pending' and not coalesce(excluded_by_client,false);

  perform reunvo_ciclo_lotes();   -- encadena el siguiente lote de inmediato

  return jsonb_build_object('ok',true,'inicio_envio',v_ini,'inicio_motivo',v_mot,
    'adelantado', v_ini < v_lote.inicio_envio,
    'mensaje','Lista aprobada ('||v_n||' empresas). Envíos a partir del '||to_char(v_ini,'DD/MM')||
              case v_mot when 'aprobacion' then ' (7 días tras su aprobación).'
                         when 'fin_en_curso' then ' (cuando termine la lista en curso).' else '.' end);
end $function$;

CREATE OR REPLACE FUNCTION public.reunvo_ciclo_lotes()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare l record; v_log jsonb := '[]'::jsonb; v_pend int; v_nuevo jsonb;
begin
  for l in select * from lotes where estado='cliente' and limite_cliente <= current_date loop
    update lotes set estado='guille', aprobado_auto=true,
           cerrado_cliente_at=coalesce(cerrado_cliente_at, now()),
           inicio_envio = greatest(l.inicio_envio, coalesce(reunvo_fin_envios(l.id), l.inicio_envio)),
           inicio_motivo = case when reunvo_fin_envios(l.id) > l.inicio_envio then 'fin_en_curso' else 'fecha_fijada' end
     where id=l.id;
    v_log := v_log || jsonb_build_object('lote',l.periodo,'de','cliente','a','guille','motivo','aprobada automáticamente en la fecha límite');
  end loop;

  for l in select * from lotes where estado='guille' loop
    select count(*) into v_pend from companies co
      join clients cl on cl.id = l.client_id
     where co.lote_id=l.id and co.assigned_client_id=l.client_id
       and co.status='pilot_pending'
       and co.contact_email is not null and co.email_verified
       and en_tramo(co.revenue_eur, cl.target_revenue_min, cl.target_revenue_max)
       and not co.envio_aprobado and not coalesce(co.excluded_by_client,false);
    if v_pend = 0 then
      update lotes set estado='listo', aprobado_at=now() where id=l.id;
      v_log := v_log || jsonb_build_object('lote',l.periodo,'de','guille','a','listo');
    end if;
  end loop;

  for l in select * from lotes where estado='listo' and inicio_envio <= current_date loop
    update lotes set estado='enviando' where id=l.id;
    v_log := v_log || jsonb_build_object('lote',l.periodo,'de','listo','a','enviando');
  end loop;

  for l in select * from lotes where estado='enviando' loop
    select count(*) into v_pend from companies co
     where co.lote_id=l.id and co.status='pilot_pending'
       and not coalesce(co.excluded_by_client,false) and co.envio_aprobado
       and not exists (select 1 from campaigns ca where ca.company_id=co.id and ca.client_id=l.client_id::text);
    if v_pend = 0 then
      update lotes set estado='agotado' where id=l.id;
      v_log := v_log || jsonb_build_object('lote',l.periodo,'de','enviando','a','agotado');
    end if;
  end loop;

  for l in
    select c.* from clients c
     where c.status='active' and not coalesce(c.envio_pausado,false) and c.html_template is not null
       and coalesce(c.dias_aprobacion,7) > 0
       and not exists (select 1 from lotes lo where lo.client_id=c.id and lo.estado='cliente')
  loop
    v_nuevo := reunvo_crear_lote(l.id);
    v_log := v_log || jsonb_build_object('lote_nuevo', v_nuevo);
  end loop;

  for l in
    select c.* from clients c
     where c.status='active' and not coalesce(c.is_test,false)
       and not coalesce(c.envio_pausado,false) and c.html_template is not null
       and coalesce(c.dias_aprobacion,7) = 0
       and not exists (select 1 from lotes lo where lo.client_id=c.id
                        and lo.estado in ('guille','listo'))
  loop
    v_nuevo := reunvo_crear_lote(l.id);
    v_log := v_log || jsonb_build_object('lote_nuevo', v_nuevo);
  end loop;

  return jsonb_build_object('ts', now(), 'cambios', v_log);
end $function$;
