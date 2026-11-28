alter table client_tokens drop constraint if exists client_tokens_proveedor_chk;
alter table client_tokens drop column if exists proveedor;
