-- =====================================================================================
-- App de Reunvo · VUELTA ATRÁS EN UN PASO.
-- Restaura las funciones guardadas por 00_copia_seguridad.sql y quita las nuevas.
-- No borra tablas ni columnas nuevas (no afectan a nada si las funciones son las de antes)
-- ni toca datos. El panel antiguo (main) y el nuevo funcionan los dos con la base restaurada.
-- =====================================================================================
begin;
do $$
declare r record; n int := 0;
begin
  if not exists (select 1 from public.reunvo_backup_funciones) then
    raise exception 'No hay copia de seguridad: no se toca nada.';
  end if;
  -- 1) Primero las funciones antiguas (no dependen de las nuevas)
  for r in select signatura, definicion from public.reunvo_backup_funciones loop
    execute r.definicion; n := n + 1;
  end loop;
  -- 2) Después se quitan las nuevas
  drop function if exists public.client_request_target_v2(text, jsonb);
  drop function if exists public.reunvo_fin_envios(uuid);
  drop function if exists public.reunvo_dia_envio(date, int[]);
  drop function if exists public.reunvo_target_tope(uuid);
  drop function if exists public.reunvo_pausa_global();
  drop function if exists public.reunvo_elegible(public.companies, public.clients);
  drop function if exists public.reunvo_empresa_restringida(public.companies, uuid);
  drop function if exists public.reunvo_choca_zona(uuid, text, text, numeric, numeric);
  raise notice 'Restauradas % funciones; nuevas eliminadas.', n;
end $$;
commit;
-- Panel: volver a publicar panel_cliente.html de main (assets/catalogos.js puede quedarse).
