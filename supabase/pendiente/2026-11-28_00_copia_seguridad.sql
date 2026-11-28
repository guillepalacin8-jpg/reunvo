-- =====================================================================================
-- App de Reunvo · 0/4: COPIA DE SEGURIDAD de las funciones que se van a sustituir.
-- Ejecutar ANTES de 01. Guarda la definición actual de producción para poder volver
-- atrás en un paso con 99_vuelta_atras.sql. Idempotente: no pisa una copia ya guardada.
-- =====================================================================================
begin;
create table if not exists public.reunvo_backup_funciones (
  signatura        text primary key,      -- p. ej. public.client_panel(text)
  definicion   text not null,
  guardada_at  timestamptz not null default now()
);
alter table public.reunvo_backup_funciones enable row level security;   -- sin políticas: nadie desde fuera

insert into public.reunvo_backup_funciones (signatura, definicion)
select f.signatura, pg_get_functiondef(to_regprocedure(f.signatura))
  from (values
    ('public.client_panel(text)'),
    ('public.client_toggle_company(text,uuid,boolean)'),
    ('public.client_lote_verificado(text)'),
    ('public.client_request_target(text,text,text,numeric,numeric)'),
    ('public.reunvo_crear_lote(uuid,date)'),
    ('public.reunvo_ciclo_lotes()'),
    ('public.buscar_reemplazo(uuid)'),
    ('public.reunvo_reponer_cola(text,uuid,integer)'),
    ('public.reunvo_mantener_colas()'),
    ('public.reunvo_aplicar_target(text,uuid)')
  ) f(signatura)
 where to_regprocedure(f.signatura) is not null
on conflict (signatura) do nothing;

select signatura, guardada_at from public.reunvo_backup_funciones order by signatura;
commit;
