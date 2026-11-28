-- Alta con Microsoft 365 / Outlook. NO EJECUTADO. Idempotente. Va DESPUÉS de 03.
-- client_tokens ya tiene una fila por cliente (clave primaria client_id): un cliente tiene UNA
-- conexión; cambiar de proveedor sustituye la fila. Por eso client_panel es determinista.
-- IMPORTANTE antes de activar Microsoft: los flujos n8n de Gmail deben leer client_tokens con
-- proveedor = 'google'; si no, intentarían refrescar con Google un token de Microsoft.
begin;

alter table client_tokens add column if not exists proveedor text not null default 'google';
alter table client_tokens add column if not exists estado    text not null default 'ok';
alter table client_tokens add column if not exists refresh_lease_until timestamptz;
alter table client_tokens drop constraint if exists client_tokens_proveedor_chk;
alter table client_tokens add constraint client_tokens_proveedor_chk check (proveedor in ('google','microsoft'));
alter table client_tokens drop constraint if exists client_tokens_estado_chk;
alter table client_tokens add constraint client_tokens_estado_chk check (estado in ('ok','caducada'));

-- state de OAuth: nonce de un solo uso ligado al cliente y al proveedor. El panel_token
-- nunca viaja como state ni en la URL de Microsoft.
create table if not exists oauth_estados (
  nonce      uuid primary key default gen_random_uuid(),
  client_id  text not null,
  proveedor  text not null check (proveedor in ('google','microsoft')),
  creado_at  timestamptz not null default now(),
  usado_at   timestamptz
);
alter table oauth_estados enable row level security;   -- sin políticas: solo funciones definer y service role

-- Panel -> nonce. Lista blanca de proveedores y tope de nonces vivos por cliente.
create or replace function public.client_oauth_iniciar(p_token text, p_proveedor text)
 returns jsonb language plpgsql security definer set search_path to 'public' as $f$
declare v uuid; n uuid;
begin
  if p_proveedor is null or p_proveedor not in ('google','microsoft') then
    return jsonb_build_object('ok',false,'mensaje','Proveedor no válido.'); end if;
  select id into v from clients where panel_token = p_token and status = 'active';
  if v is null then return jsonb_build_object('error','token'); end if;
  delete from oauth_estados where creado_at < now() - interval '1 hour';
  if (select count(*) from oauth_estados where client_id = v::text and usado_at is null
         and creado_at > now() - interval '10 minutes') >= 10 then
    return jsonb_build_object('ok',false,'mensaje','Demasiados intentos. Espere unos minutos.'); end if;
  insert into oauth_estados (client_id, proveedor) values (v::text, p_proveedor) returning nonce into n;
  return jsonb_build_object('ok',true,'nonce',n);
end $f$;

-- n8n (service role) -> consume el nonce: válido 10 minutos y una sola vez.
create or replace function public.reunvo_oauth_consumir(p_nonce uuid)
 returns jsonb language sql security definer set search_path to 'public' as $f$
  with u as (
    update oauth_estados set usado_at = now()
     where nonce = p_nonce and usado_at is null and creado_at > now() - interval '10 minutes'
    returning client_id, proveedor)
  select coalesce((select jsonb_build_object('ok',true,'client_id',client_id,'proveedor',proveedor) from u),
                  jsonb_build_object('ok',false));
$f$;

-- Concesión (lease) para serializar el refresco por cliente: una sola llamada a la vez.
create or replace function public.reunvo_token_lease(p_client text, p_segundos int default 30)
 returns boolean language sql security definer set search_path to 'public' as $f$
  with u as (
    update client_tokens set refresh_lease_until = now() + make_interval(secs => least(greatest(p_segundos,1),120))
     where client_id = p_client and (refresh_lease_until is null or refresh_lease_until < now())
    returning 1)
  select exists (select 1 from u);
$f$;
create or replace function public.reunvo_token_soltar(p_client text)
 returns void language sql security definer set search_path to 'public' as $f$
  update client_tokens set refresh_lease_until = null where client_id = p_client;
$f$;
-- Estado de la conexión: n8n escribe 'caducada' al recibir invalid_grant y 'ok' al reconectar.
create or replace function public.reunvo_token_estado(p_client text, p_estado text)
 returns void language sql security definer set search_path to 'public' as $f$
  update client_tokens set estado = p_estado, updated_at = now() where client_id = p_client and p_estado in ('ok','caducada');
$f$;

revoke execute on function public.reunvo_oauth_consumir(uuid)       from public, anon, authenticated;
revoke execute on function public.reunvo_token_lease(text, int)     from public, anon, authenticated;
revoke execute on function public.reunvo_token_soltar(text)         from public, anon, authenticated;
revoke execute on function public.reunvo_token_estado(text, text)   from public, anon, authenticated;
revoke execute on function public.client_oauth_iniciar(text, text)  from public;
grant  execute on function public.client_oauth_iniciar(text, text)  to anon, authenticated;

commit;
