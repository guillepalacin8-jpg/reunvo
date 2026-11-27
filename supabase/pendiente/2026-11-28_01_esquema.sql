-- =====================================================================================
-- App de Reunvo · semana del 30/11 · 1/4: ESQUEMA (tablas, columnas, RLS)
-- PENDIENTE DE APROBACIÓN (Guillem). NO EJECUTADO. Proyecto: quywrltqzoyyorbsuiwc.
-- Orden: 01_esquema → 02_catalogos_seed → 03_funciones → 04_config. Todo idempotente:
-- se puede ejecutar dos veces sin romper nada.
-- =====================================================================================
begin;

-- ---- Catálogos (datos públicos: CNAE 2009 del INE, CCAA y provincias INE) -------------
create table if not exists public.cnae2009 (
  codigo            text primary key,          -- 'C' (sección) o '25' (división)
  nivel             text not null check (nivel in ('seccion','division','grupo','clase')),
  titulo            text not null,
  padre             text references public.cnae2009(codigo),
  sector_simplified text                        -- etiqueta legible que ya usa la app
);
create table if not exists public.ccaa (
  codigo text primary key,                      -- código INE de comunidad, '01'..'19'
  nombre text not null
);
create table if not exists public.provincias (
  codigo text primary key,                      -- código INE = 2 primeros dígitos del CP
  nombre text not null,
  ccaa   text not null references public.ccaa(codigo)
);
-- Zonas reservadas a la firma: otros clientes no pueden pedirlas ni recibir esas empresas.
create table if not exists public.zonas_reservadas (
  id       uuid primary key default gen_random_uuid(),
  ccaa     text not null references public.ccaa(codigo),
  metric   text not null check (metric in ('revenue','result')),
  min_eur  numeric not null,
  max_eur  numeric not null,
  titular  uuid references public.clients(id),   -- el cliente al que se reserva (exento)
  activa   boolean not null default true,
  unique (ccaa, metric)
);

-- RLS en todas las tablas nuevas. Catálogos: lectura pública (son datos del INE).
-- zonas_reservadas: sin políticas, solo se lee desde funciones SECURITY DEFINER.
alter table public.cnae2009         enable row level security;
alter table public.ccaa             enable row level security;
alter table public.provincias       enable row level security;
alter table public.zonas_reservadas enable row level security;
drop policy if exists cnae2009_lectura   on public.cnae2009;
drop policy if exists ccaa_lectura       on public.ccaa;
drop policy if exists provincias_lectura on public.provincias;
create policy cnae2009_lectura   on public.cnae2009   for select to anon, authenticated using (true);
create policy ccaa_lectura       on public.ccaa       for select to anon, authenticated using (true);
create policy provincias_lectura on public.provincias for select to anon, authenticated using (true);

-- ---- Empresas: datos que hacen falta para el target nuevo ---------------------------
-- Se rellenan con la reimportación de SABI (cruce por nif). Mientras estén vacías, los
-- filtros correspondientes no descartan (dato desconocido = no es motivo de descarte).
alter table public.companies add column if not exists result_eur          bigint;  -- resultado del ejercicio, €
alter table public.companies add column if not exists fin_year            integer; -- ejercicio del dato
alter table public.companies add column if not exists cnae                text;    -- código primario CNAE 2009 (4 dígitos)
alter table public.companies add column if not exists provincia_ine       text;
alter table public.companies add column if not exists ccaa_ine            text;
alter table public.companies add column if not exists dg_fecha_nacimiento date;    -- DG o administrador
create index if not exists companies_ccaa_ine_idx on public.companies (ccaa_ine);
create index if not exists companies_cnae_idx     on public.companies (cnae);

-- ---- Clientes: target nuevo, plazos e interruptor -----------------------------------
alter table public.clients add column if not exists target_metric     text not null default 'revenue';
alter table public.clients add column if not exists target_min_eur    numeric;
alter table public.clients add column if not exists target_max_eur    numeric;
alter table public.clients add column if not exists target_cnae       text[];   -- secciones ('C') o divisiones ('25')
alter table public.clients add column if not exists target_ccaa       text;     -- código INE
alter table public.clients add column if not exists target_provincias text[];   -- códigos INE; vacío = toda la CCAA
alter table public.clients add column if not exists target_edad_min   integer;  -- edad mínima del DG, años
alter table public.clients add column if not exists dias_revision     integer not null default 7;
alter table public.clients add column if not exists bloquear_quitar_tras_aprobar boolean not null default true;
alter table public.clients drop constraint if exists clients_target_metric_chk;
alter table public.clients add constraint clients_target_metric_chk check (target_metric in ('revenue','result'));

alter table public.target_requests add column if not exists metric     text;
alter table public.target_requests add column if not exists min_eur    numeric;
alter table public.target_requests add column if not exists max_eur    numeric;
alter table public.target_requests add column if not exists cnae       text[];
alter table public.target_requests add column if not exists ccaa       text;
alter table public.target_requests add column if not exists provincias text[];
alter table public.target_requests add column if not exists edad_min   integer;

-- ---- Lotes: plazos ------------------------------------------------------------------
alter table public.lotes add column if not exists adelantado    boolean not null default false;
alter table public.lotes add column if not exists aprobado_auto boolean not null default false;
-- Por qué empieza ese día: 'fecha_fijada' | 'aprobacion' (aprobación + 7) | 'fin_en_curso' (al acabar la lista anterior)
alter table public.lotes add column if not exists inicio_motivo text;

commit;
