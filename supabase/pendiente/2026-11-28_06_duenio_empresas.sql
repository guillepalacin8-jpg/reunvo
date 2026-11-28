
-- =====================================================================================
-- 06 · DUEÑO ÚNICO POR EMPRESA (deduplicación entre clientes). NO EJECUTADO.
-- Regla interna: una empresa solo la contacta un cliente durante 12 meses desde el primer envío.
-- Nada de esto aparece en textos para clientes. Requiere 01-03. Va en una transacción.
-- =====================================================================================
begin;

-- Copia de las funciones que se sustituyen (estado actual de producción)
create table if not exists public.reunvo_backup_funciones_v2 (
  signatura text primary key, definicion text not null, guardada_at timestamptz not null default now());
alter table public.reunvo_backup_funciones_v2 enable row level security;
insert into public.reunvo_backup_funciones_v2 (signatura, definicion)
select f.s, pg_get_functiondef(to_regprocedure(f.s))
  from (values ('public.reunvo_elegible(public.companies,public.clients)'),('public.buscar_reemplazo(uuid)'),
               ('public.reunvo_crear_lote(uuid,date)'),('public.reunvo_reponer_cola(text,uuid,integer)'),
               ('public.reunvo_mantener_colas()'),('public.client_toggle_company(text,uuid,boolean)')) f(s)
 where to_regprocedure(f.s) is not null
on conflict (signatura) do nothing;

-- Columnas e índices
alter table public.companies add column if not exists cliente_id_asignado uuid references public.clients(id);
alter table public.companies add column if not exists asignada_desde      timestamptz;
alter table public.companies add column if not exists asignada_hasta      timestamptz;  -- null = reservada, aún sin envío
-- Texto legible del dueño para el editor de tablas. Lo mantiene SOLO el trigger a partir de cliente_id_asignado.
alter table public.companies add column if not exists cliente              text;
create index if not exists companies_duenio_idx   on public.companies (cliente_id_asignado) where cliente_id_asignado is not null;
create index if not exists companies_nif_idx      on public.companies (nif) where nif is not null;
create index if not exists companies_domain_l_idx on public.companies (lower(domain)) where domain is not null;
create index if not exists companies_email_l_idx  on public.companies (lower(contact_email)) where contact_email is not null;
create index if not exists campaigns_company_idx  on public.campaigns (company_id, status);

CREATE OR REPLACE FUNCTION public.reunvo_cliente_texto()
 RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
begin
  new.cliente := (select coalesce(c.name, c.company) from clients c where c.id = new.cliente_id_asignado);  -- null si libre
  return new;
end $function$;
drop trigger if exists reunvo_cliente_texto_trg on public.companies;
create trigger reunvo_cliente_texto_trg before insert or update of cliente_id_asignado, cliente on public.companies
  for each row execute function public.reunvo_cliente_texto();

-- Si el cliente cambia de nombre, se actualiza el texto de sus empresas
CREATE OR REPLACE FUNCTION public.reunvo_cliente_renombrado()
 RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
begin
  update companies set cliente_id_asignado = cliente_id_asignado where cliente_id_asignado = new.id;
  return new;
end $function$;
drop trigger if exists reunvo_cliente_renombrado_trg on public.clients;
create trigger reunvo_cliente_renombrado_trg after update of name, company on public.clients
  for each row when (old.name is distinct from new.name or old.company is distinct from new.company)
  execute function public.reunvo_cliente_renombrado();

-- Vista para el editor de tablas: «cliente» justo al lado del nombre (Postgres no permite reordenar
-- columnas de la tabla sin reconstruirla; la vista es de solo lectura y respeta los permisos de quien la abre).
create or replace view public.companies_con_cliente with (security_invoker = true) as
  select id, company_name, cliente, status, nif, domain, contact_email, region,
         cliente_id_asignado, asignada_desde, asignada_hasta, assigned_client_id, lote_id
    from public.companies;
revoke all on public.companies_con_cliente from anon, authenticated;

-- ¿Está libre para este cliente? (sin dueño, dueño caducado, o de este cliente; vale para todo el grupo)
CREATE OR REPLACE FUNCTION public.reunvo_libre_para(co public.companies, p_client uuid)
 RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
  select not (
    exists (select 1 from companies o where o.id = co.id
             and o.cliente_id_asignado is not null and o.cliente_id_asignado <> p_client
             and (o.asignada_hasta is null or o.asignada_hasta > now()))
    or (co.nif is not null and exists (select 1 from companies o where o.nif = co.nif
             and o.cliente_id_asignado is not null and o.cliente_id_asignado <> p_client
             and (o.asignada_hasta is null or o.asignada_hasta > now())))
    or (co.domain is not null and exists (select 1 from companies o where lower(o.domain) = lower(co.domain)
             and o.cliente_id_asignado is not null and o.cliente_id_asignado <> p_client
             and (o.asignada_hasta is null or o.asignada_hasta > now())))
    or (co.contact_email is not null and exists (select 1 from companies o where lower(o.contact_email) = lower(co.contact_email)
             and o.cliente_id_asignado is not null and o.cliente_id_asignado <> p_client
             and (o.asignada_hasta is null or o.asignada_hasta > now())))
  );
$function$;

-- Todos los cambios de dueño se serializan con un bloqueo global (pocos al día): sin interbloqueos.
-- Se toma SIEMPRE antes de bloquear filas de companies.
CREATE OR REPLACE FUNCTION public.reunvo_lock_duenio()
 RETURNS void LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path TO 'public'
AS $function$ select pg_advisory_xact_lock(hashtextextended('reunvo_duenio', 0)); $function$;

-- ¿Ya hay en la lista de este cliente otra fila con el mismo NIF, dominio o email? (un contacto por empresa)
CREATE OR REPLACE FUNCTION public.reunvo_grupo_ya_en_lista(p_company uuid, p_client uuid)
 RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
  select exists (
    select 1 from companies co join companies o on o.id <> co.id
     where co.id = p_company
       and o.assigned_client_id = p_client and o.status = 'pilot_pending' and not coalesce(o.excluded_by_client,false)
       and ((co.nif is not null and o.nif = co.nif)
            or (co.domain is not null and lower(o.domain) = lower(co.domain))
            or (co.contact_email is not null and lower(o.contact_email) = lower(co.contact_email))));
$function$;

-- Reclamo atómico: bloquea por NIF/dominio/email (en orden fijo, sin interbloqueos), comprueba y asigna
-- el dueño a todo el grupo. Devuelve falso si otro cliente es dueño vigente.
CREATE OR REPLACE FUNCTION public.reunvo_reclamar(p_company uuid, p_client uuid)
 RETURNS boolean LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare co public.companies%rowtype;
begin
  perform reunvo_lock_duenio();
  select * into co from companies where id = p_company;
  if not found then return false; end if;
  if not reunvo_libre_para(co, p_client) then return false; end if;
  update companies o set cliente_id_asignado = p_client,
         asignada_desde = case when o.cliente_id_asignado = p_client then coalesce(o.asignada_desde, now()) else now() end,
         asignada_hasta = case when o.cliente_id_asignado = p_client then o.asignada_hasta else null end
   where (o.id = co.id
          or (co.nif is not null and o.nif = co.nif)
          or (co.domain is not null and lower(o.domain) = lower(co.domain))
          or (co.contact_email is not null and lower(o.contact_email) = lower(co.contact_email)))
     and (o.cliente_id_asignado is null or o.cliente_id_asignado = p_client or o.asignada_hasta <= now());
  return true;
end $function$;

-- Quitar antes del envío: se libera el dueño de las filas del grupo que el cliente tiene sin enviar
CREATE OR REPLACE FUNCTION public.reunvo_liberar(p_company uuid, p_client uuid)
 RETURNS void LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path TO 'public'
AS $function$
  update companies o set cliente_id_asignado = null, asignada_desde = null, asignada_hasta = null
   from companies co
  where co.id = p_company
    and o.cliente_id_asignado = p_client and o.asignada_hasta is null
    and (o.id = co.id
         or (co.nif is not null and o.nif = co.nif)
         or (co.domain is not null and lower(o.domain) = lower(co.domain))
         or (co.contact_email is not null and lower(o.contact_email) = lower(co.contact_email)))
    and not exists (select 1 from campaigns ca where ca.company_id = o.id and ca.client_id = p_client::text and ca.status = 'sent');
$function$;

-- Con el primer envío se fija el plazo: 12 meses
CREATE OR REPLACE FUNCTION public.reunvo_fijar_plazo()
 RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
begin
  if new.status = 'sent' and new.client_id ~ '^[0-9a-f-]{36}$' then
    update companies o set asignada_hasta = coalesce(new.sent_at, now()) + interval '12 months'
      from companies co
     where co.id = new.company_id and o.cliente_id_asignado = new.client_id::uuid and o.asignada_hasta is null
       and (o.id = co.id
            or (co.nif is not null and o.nif = co.nif)
            or (co.domain is not null and lower(o.domain) = lower(co.domain))
            or (co.contact_email is not null and lower(o.contact_email) = lower(co.contact_email)));
  end if;
  return new;
end $function$;
drop trigger if exists reunvo_fijar_plazo_trg on public.campaigns;
create trigger reunvo_fijar_plazo_trg after insert or update of status on public.campaigns
  for each row execute function public.reunvo_fijar_plazo();

-- Red de seguridad antes de cada envío: la empresa tiene que ser de ese cliente
CREATE OR REPLACE FUNCTION public.reunvo_puede_enviar(p_client uuid, p_company uuid)
 RETURNS boolean LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare co public.companies%rowtype;
begin
  select * into co from companies where id = p_company;
  if not found then return false; end if;
  if co.cliente_id_asignado is null or co.asignada_hasta <= now() then
    -- sin dueño vigente: solo se reclama si la empresa está en la lista de ESTE cliente
    return coalesce(co.assigned_client_id = p_client, false) and reunvo_reclamar(p_company, p_client);
  end if;
  return coalesce(co.cliente_id_asignado = p_client, false) and reunvo_libre_para(co, p_client);
end $function$;

-- GARANTÍA EN LA BASE: una campaña solo se registra si companies.cliente_id_asignado = client_id de la campaña
-- (y ninguna fila con el mismo NIF/dominio/email es de otro dueño vigente). Si no, no se inserta y avisa solo a Guillem.
CREATE OR REPLACE FUNCTION public.reunvo_campania_guarda()
 RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare ok boolean := false;
begin
  if new.company_id is not null and new.client_id ~ '^[0-9a-f-]{36}$' then
    ok := coalesce(reunvo_puede_enviar(new.client_id::uuid, new.company_id), false);
  end if;
  if not coalesce(ok, false) then
    if new.client_id ~ '^[0-9a-f-]{36}$' then
      insert into avisos_guillem(tipo, client_id, company_id, texto)
      values ('dedup_bloqueado', new.client_id::uuid, new.company_id, 'Envío bloqueado: la empresa pertenece a otro cliente.');
    end if;
    return null;
  end if;
  return new;
end $function$;
drop trigger if exists reunvo_campania_guarda_trg on public.campaigns;
create trigger reunvo_campania_guarda_trg before insert or update of client_id, company_id on public.campaigns
  for each row execute function public.reunvo_campania_guarda();

-- Sustitución silenciosa en un envío bloqueado (para el flujo): quita y reemplaza sin avisar al cliente
CREATE OR REPLACE FUNCTION public.reunvo_sustituir_en_silencio(p_client uuid, p_company uuid)
 RETURNS uuid LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare v_lote uuid; v_id uuid;
begin
  perform reunvo_lock_duenio();
  select lote_id into v_lote from companies where id = p_company and assigned_client_id = p_client for update;
  update companies set excluded_by_client = true where id = p_company and assigned_client_id = p_client;
  v_id := buscar_reemplazo(p_client);
  if v_id is not null then
    update companies set assigned_client_id = p_client, status = 'pilot_pending', excluded_by_client = false,
           replacement_for = p_company, assigned_at = now(), lote_id = v_lote where id = v_id;
  end if;
  insert into avisos_guillem(tipo, client_id, company_id, texto)
  values ('dedup_sustituida', p_client, p_company, 'Empresa sustituida antes del envío por tener ya otro dueño.');
  return v_id;
end $function$;

-- Asignación en bloque con reclamo atómico (la usan crear_lote, reponer_cola y mantener_colas)
CREATE OR REPLACE FUNCTION public.reunvo_asignar_empresas(p_client uuid, p_n int, p_lote uuid, p_dato_primero boolean, p_exigir_dato boolean)
 RETURNS int LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare c public.clients%rowtype; r record; n int := 0;
begin
  perform reunvo_lock_duenio();
  select * into c from clients where id = p_client;
  if not found or p_n <= 0 then return 0; end if;
  for r in
    select co.id, (co.revenue_eur is null) as sin_dato from companies co
     where reunvo_elegible(co, c)
       and (not p_exigir_dato or co.revenue_eur is not null)
     order by case when p_dato_primero then (co.revenue_eur is null) else false end asc,
              es_probable_filial(co.company_name) asc,
              (co.domain is not null) desc,
              coalesce(length(co.activity_description),0) desc, co.id
     limit p_n * 4
  loop
    exit when n >= p_n;
    continue when reunvo_grupo_ya_en_lista(r.id, p_client);
    if reunvo_reclamar(r.id, p_client) then
      update companies set status = 'pilot_pending', assigned_client_id = p_client, assigned_at = now(),
             lote_id = coalesce(p_lote, lote_id),
             sin_tramo_confirmado = case when p_dato_primero then r.sin_dato else sin_tramo_confirmado end
       where id = r.id;
      n := n + 1;
    end if;
  end loop;
  return n;
end $function$;


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
    -- Nunca a quien ya se escribió en nombre de este cliente (aunque vuelva al pool)
    and not exists (select 1 from campaigns ca where ca.company_id = co.id and ca.client_id = c.id::text)
    -- Dueño único: solo empresas sin dueño, con dueño caducado o de este mismo cliente
    -- (el dueño vale para todas las filas con el mismo NIF, dominio o email)
    and reunvo_libre_para(co, c.id)
    -- Perímetro restringido a otro cliente
    and not reunvo_empresa_restringida(co, c.id);
$function$;

CREATE OR REPLACE FUNCTION public.buscar_reemplazo(p_client_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 VOLATILE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r record; c public.clients%rowtype;
begin
  select * into c from clients where id = p_client_id;
  if not found then return null; end if;
  for r in
    select co.id from companies co
     where reunvo_elegible(co, c)
       and coalesce(co.activity_description,'') <> ''
     order by (co.revenue_eur is null) asc,
              es_probable_filial(co.company_name) asc,
              (co.domain is not null) desc,
              coalesce(length(co.activity_description),0) desc, co.id
     limit 25
  loop
    continue when reunvo_grupo_ya_en_lista(r.id, p_client_id);
    if reunvo_reclamar(r.id, p_client_id) then return r.id; end if;
  end loop;
  return null;
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
  -- Sin flujo_v2: límite = inicio − dias_aprobacion, como siempre.
  v_rev := case when coalesce(c.flujo_v2,false) then coalesce(c.dias_revision,7) else v_apr end;

  v_ini := coalesce(p_inicio,
    (select max(inicio_envio) + coalesce(c.cola_objetivo_dias,20) from lotes where client_id = p_client_id),
    (current_date + 1));
  -- El cliente tiene que tener sus días de aprobación completos + la semana de revisión.
  v_min := current_date + (case when v_apr > 0 and coalesce(c.flujo_v2,false) then v_apr + v_rev else 1 end);
  if v_ini < v_min then v_ini := v_min; end if;
  -- Una sola pasada: el inicio de un cliente con flujo_v2 nunca cae en fin de semana; el
  -- periodo (mes) se calcula ya con la fecha ajustada.
  loop
    if coalesce(c.flujo_v2,false) then v_ini := reunvo_dia_envio(v_ini, c.dias_envio); end if;
    v_per := to_char(v_ini,'YYYY-MM');
    exit when not exists (select 1 from lotes where client_id=p_client_id and periodo=v_per);
    v_ini := v_ini + 30;
  end loop;

  v_obj := coalesce(c.emails_per_day,10) * coalesce(c.cola_objetivo_dias,20);
  v_estado := case when v_apr = 0 then 'guille' else 'cliente' end;

  insert into lotes(client_id, periodo, estado, objetivo, inicio_envio, limite_cliente, cerrado_cliente_at)
  values (p_client_id, v_per, v_estado, v_obj, v_ini,
          case when v_apr > 0 then v_ini - v_rev else v_ini end,
          case when v_estado='guille' then now() end)
  returning id into v_id;

  v_n := reunvo_asignar_empresas(p_client_id, v_obj, v_id, true, false);

  return jsonb_build_object('ok',true,'lote',v_id,'periodo',v_per,'estado',v_estado,
    'objetivo',v_obj,'asignadas',v_n,'inicio_envio',v_ini,
    'sin_tramo_confirmado',(select count(*) from companies where lote_id=v_id and sin_tramo_confirmado),
    'limite_cliente', case when v_apr > 0 then v_ini - v_rev else v_ini end,
    'sin_inventario', v_n < v_obj);
end $function$;

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
  if reunvo_pausa_global() then
    return jsonb_build_object('ok',false,'mensaje','Envíos en pausa: no se repone la cola.'); end if;

  n := reunvo_asignar_empresas(p_client_id, p_n, null, true, false);
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
  if reunvo_pausa_global() then
    return jsonb_build_object('ts', now(), 'clientes', v_out, 'pausa', true); end if;
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
      -- Clientes actuales (sin flujo_v2): como en producción, con tramo configurado la empresa de
      -- facturación desconocida no entra aquí.
      v_asig := reunvo_asignar_empresas(c.id, v_falta, null, false,
                  (not coalesce(c.flujo_v2,false)) and not (c.target_revenue_min is null and c.target_revenue_max is null));
    end if;

    v_out := v_out || jsonb_build_object(
      'cliente', coalesce(c.name, c.company),
      'objetivo', v_obj, 'tenia', v_hay, 'asignadas', v_asig,
      'cola_final', v_hay + v_asig,
      'sin_inventario', (v_hay + v_asig) < v_obj);
  end loop;
  return jsonb_build_object('ts', now(), 'clientes', v_out);
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

  -- Una sola operación de quitar a la vez por cliente (doble clic, dos pestañas): sin esto,
  -- dos llamadas simultáneas podían elegir la misma sustituta y la lista bajaba de su cupo.
  perform pg_advisory_xact_lock(hashtext('reunvo_quitar:' || c.id::text));
  perform reunvo_lock_duenio();   -- antes de bloquear filas (orden fijo: sin interbloqueos)

  -- Ya quitada (otra pestaña o doble clic): no es un error ni se busca otra sustituta.
  if exists (select 1 from companies where id = p_company_id and assigned_client_id = c.id
               and coalesce(excluded_by_client,false)) then
    return jsonb_build_object('ok',true,'excluida',true,'ya_quitada',true,
      'mensaje','Esa empresa ya estaba quitada.');
  end if;

  select co.lote_id into v_lote from companies co
   where co.id = p_company_id and co.assigned_client_id = c.id and co.status='pilot_pending'
     and not coalesce(co.excluded_by_client,false)
     and not exists (select 1 from campaigns ca where ca.company_id=co.id and ca.client_id=c.id::text)
   for update;
  if not found then return jsonb_build_object('error','no_autorizado'); end if;

  select inicio_envio, objetivo into v_ini, v_obj from lotes where id = v_lote;

  -- Interruptor (recomendado: activado). Aprobada la lista, ya no se quita nada.
  if coalesce(c.flujo_v2,false) and coalesce(c.bloquear_quitar_tras_aprobar,true)
     and exists (select 1 from lotes where id = v_lote and estado <> 'cliente') then
    return jsonb_build_object('ok',false,
      'mensaje','Esta lista ya está aprobada y no admite cambios.');
  end if;

  -- Lista ya en envío o agotada: no se quita nada, para cualquier cliente.
  if exists (select 1 from lotes where id = v_lote and estado in ('enviando','agotado')) then
    return jsonb_build_object('ok',false,
      'mensaje','Esta lista ya está en envío y no admite cambios.');
  end if;

  update companies set excluded_by_client = true where id = p_company_id;
  -- Quitada antes del envío: se libera el dueño (de ella y de las filas con el mismo NIF/dominio/email)
  perform reunvo_liberar(p_company_id, c.id);

  v_id := buscar_reemplazo(c.id);

  -- Tomar de la lista siguiente mueve una empresa entre listas ya creadas: solo con flujo_v2.
  if v_id is null and v_lote is not null and coalesce(c.flujo_v2,false) then
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
      'mensaje','Quitada. No quedan empresas en la lista de reemplazo: su lista queda en '||v_quedan||
                ' de '||coalesce(v_obj,v_quedan)||'. La completaremos en cuanto haya.');
  end if;

  -- v_id viene bloqueado (FOR UPDATE SKIP LOCKED). Guarda extra: si alguien se la llevó,
  -- no se pisa; se aborta y el cliente puede reintentar.
  update companies set assigned_client_id=c.id, status='pilot_pending',
         excluded_by_client=false, replacement_for=p_company_id,
         assigned_at=now(), lote_id=v_lote
   where id = v_id
     and (assigned_client_id is null or assigned_client_id = c.id)
     and not exists (select 1 from campaigns ca where ca.company_id = v_id and ca.client_id = c.id::text);
  get diagnostics v_quedan = row_count;
  if v_quedan <> 1 then raise exception 'sustituta_no_disponible'; end if;
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

revoke execute on function public.reunvo_cliente_texto()                            from public, anon, authenticated;
revoke execute on function public.reunvo_cliente_renombrado()                      from public, anon, authenticated;
revoke execute on function public.reunvo_lock_duenio()                              from public, anon, authenticated;
revoke execute on function public.reunvo_libre_para(public.companies, uuid)        from public, anon, authenticated;
revoke execute on function public.reunvo_grupo_ya_en_lista(uuid, uuid)             from public, anon, authenticated;
revoke execute on function public.reunvo_reclamar(uuid, uuid)                      from public, anon, authenticated;
revoke execute on function public.reunvo_liberar(uuid, uuid)                       from public, anon, authenticated;
revoke execute on function public.reunvo_puede_enviar(uuid, uuid)                  from public, anon, authenticated;
revoke execute on function public.reunvo_sustituir_en_silencio(uuid, uuid)         from public, anon, authenticated;
revoke execute on function public.reunvo_asignar_empresas(uuid, int, uuid, boolean, boolean) from public, anon, authenticated;
revoke execute on function public.reunvo_elegible(public.companies, public.clients) from public, anon, authenticated;
revoke execute on function public.buscar_reemplazo(uuid)                           from public, anon, authenticated;
revoke execute on function public.reunvo_crear_lote(uuid, date)                    from public, anon, authenticated;
revoke execute on function public.reunvo_mantener_colas()                          from public, anon, authenticated;

commit;
