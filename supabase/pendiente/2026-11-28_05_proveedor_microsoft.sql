-- Alta con Microsoft 365 / Outlook. NO EJECUTADO. Idempotente. Rama feat/alta-microsoft.
-- Solo añade una columna con valor por defecto: las filas de Gmail no cambian.
alter table client_tokens add column if not exists proveedor text not null default 'google';
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'client_tokens_proveedor_chk') then
    alter table client_tokens add constraint client_tokens_proveedor_chk check (proveedor in ('google','microsoft'));
  end if;
end $$;
