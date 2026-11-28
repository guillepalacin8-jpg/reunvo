-- Vuelta atrás de 06: restaura las 6 funciones desde reunvo_backup_funciones_v2 y quita lo nuevo.
begin;
drop view if exists public.companies_con_cliente;
drop trigger if exists reunvo_cliente_texto_trg on public.companies;
drop trigger if exists reunvo_cliente_renombrado_trg on public.clients;
drop trigger if exists reunvo_campania_guarda_trg on public.campaigns;
drop trigger if exists reunvo_fijar_plazo_trg on public.campaigns;
do $$ declare r record; begin
  if not exists (select 1 from public.reunvo_backup_funciones_v2) then raise exception 'sin copia v2: no se toca nada'; end if;
  for r in select definicion from public.reunvo_backup_funciones_v2 loop execute r.definicion; end loop;
end $$;
drop function if exists public.reunvo_campania_guarda();
drop function if exists public.reunvo_cliente_texto();
drop function if exists public.reunvo_cliente_renombrado();
drop function if exists public.reunvo_fijar_plazo();
drop function if exists public.reunvo_sustituir_en_silencio(uuid, uuid);
drop function if exists public.reunvo_asignar_empresas(uuid, int, uuid, boolean, boolean);
drop function if exists public.reunvo_puede_enviar(uuid, uuid);
drop function if exists public.reunvo_liberar(uuid, uuid);
drop function if exists public.reunvo_reclamar(uuid, uuid);
drop function if exists public.reunvo_libre_para(public.companies, uuid);
drop function if exists public.reunvo_lock_duenio();
drop function if exists public.reunvo_dominio_clave(text);
drop function if exists public.reunvo_vigente(timestamptz, timestamptz);
drop function if exists public.reunvo_dominio(text);
drop table if exists public.dominios_no_agrupables;
drop function if exists public.reunvo_grupo_ya_en_lista(uuid, uuid);
alter table public.companies drop column if exists cliente;
-- las columnas cliente_id_asignado/asignada_* se dejan (vacías tras 07_99); eliminarlas solo si hace falta.
commit;
