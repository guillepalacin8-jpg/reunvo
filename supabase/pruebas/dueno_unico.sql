-- Prueba local (réplica, datos ficticios) del dueño único: ningún envío de un segundo cliente a la misma empresa, dominio, email o NIF. Debe dar PROHIBIDOS=0 y permitidos=3.
truncate companies, campaigns, avisos_guillem, lotes, clients cascade;
insert into clients(id,name,company,status,panel_token,target_region,usa_reserva,is_test) values
 ('00000000-0000-0000-0000-00000000000a','Deale','Deale','active','0123456789abcdef0123','DEMO',false,true),
 ('00000000-0000-0000-0000-00000000000b','Cliente Actual SL','Cliente Actual SL','active','abcdef0123456789abcd','DEMO',false,false);
insert into companies(id,company_name,nif,domain,contact_email,region,status,assigned_client_id) values
 ('00000000-0000-0000-0000-0000000000a1','x1','N1','d1.test','e1@x.test','DEMO','pending',null),
 ('00000000-0000-0000-0000-0000000000a2','x2','N2','d1.test','e2@x.test','DEMO','pending','00000000-0000-0000-0000-00000000000a'),
 ('00000000-0000-0000-0000-0000000000a3','x3','N3','d3.test','E1@x.test','DEMO','pending','00000000-0000-0000-0000-00000000000a'),
 ('00000000-0000-0000-0000-0000000000a4','x4','N1','d4.test','e4@x.test','DEMO','pending','00000000-0000-0000-0000-00000000000a'),
 ('00000000-0000-0000-0000-0000000000a5','x5','N5','d5.test','e5@x.test','DEMO','pending','00000000-0000-0000-0000-00000000000a'),
 ('00000000-0000-0000-0000-0000000000a7','x7','N7','d7.test','e7@x.test','DEMO','pending','00000000-0000-0000-0000-00000000000a'),
 ('00000000-0000-0000-0000-0000000000a8','x8','N8','d8.test','e8@x.test','DEMO','pending',null);
select 'B_reclama_x1', reunvo_reclamar('00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000000b');
select 'cliente_texto_x1_x2_x3_x4', string_agg(company_name||'='||coalesce(cliente,'(libre)'), ' | ' order by company_name) from companies where company_name in ('x1','x2','x3','x4','x5');
update companies set cliente='MANUAL' where company_name='x1';
select 'manual_ignorado', cliente from companies where company_name='x1';
-- x6: importada DESPUÉS, mismo dominio que x1, en la lista de Deale, sin dueño propio
insert into companies(id,company_name,nif,domain,contact_email,region,status,assigned_client_id) values ('00000000-0000-0000-0000-0000000000a6','x6','N6','D1.test','e6@x.test','DEMO','pending','00000000-0000-0000-0000-00000000000a');
-- x7: dueño B caducado
update companies set cliente_id_asignado='00000000-0000-0000-0000-00000000000b', asignada_desde=now()-interval '13 months', asignada_hasta=now()-interval '1 month' where company_name='x7';
-- intentos de envío de Deale (A)
insert into campaigns(company_id,client_id,status) values ('00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000000a','sent');
insert into campaigns(company_id,client_id,status) values ('00000000-0000-0000-0000-0000000000a2','00000000-0000-0000-0000-00000000000a','sent');
insert into campaigns(company_id,client_id,status) values ('00000000-0000-0000-0000-0000000000a3','00000000-0000-0000-0000-00000000000a','sent');
insert into campaigns(company_id,client_id,status) values ('00000000-0000-0000-0000-0000000000a4','00000000-0000-0000-0000-00000000000a','sent');
insert into campaigns(company_id,client_id,status) values ('00000000-0000-0000-0000-0000000000a6','00000000-0000-0000-0000-00000000000a','sent');
insert into campaigns(company_id,client_id,status) values ('00000000-0000-0000-0000-0000000000a8','00000000-0000-0000-0000-00000000000a','sent');
insert into campaigns(company_id,client_id,status) values ('00000000-0000-0000-0000-0000000000a1','no-es-uuid','sent');
select 'PROHIBIDOS_insertados(debe ser 0)', count(*) from campaigns where client_id='00000000-0000-0000-0000-00000000000a';
-- permitidos
insert into campaigns(company_id,client_id,status,sent_at) values ('00000000-0000-0000-0000-0000000000a5','00000000-0000-0000-0000-00000000000a','sent',now());
insert into campaigns(company_id,client_id,status,sent_at) values ('00000000-0000-0000-0000-0000000000a7','00000000-0000-0000-0000-00000000000a','sent',now());
insert into campaigns(company_id,client_id,status,sent_at) values ('00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000000b','sent',now());
select 'permitidos(debe ser 3)', count(*) from campaigns;
select 'x5_x7_dueno_y_plazo', string_agg(company_name||'→'||cliente||' '||round(extract(epoch from (asignada_hasta-now()))/2592000)||'m', ' | ' order by company_name) from companies where company_name in ('x5','x7');
-- UPDATE para cambiar de cliente una campaña existente
update campaigns set client_id='00000000-0000-0000-0000-00000000000a' where company_id='00000000-0000-0000-0000-0000000000a1';
select 'update_bloqueado(x1 sigue de B)', (select name from clients where id::text=c.client_id) from campaigns c where company_id='00000000-0000-0000-0000-0000000000a1';
select 'avisos_dedup', count(*) from avisos_guillem where tipo='dedup_bloqueado';
-- liberar y renombrar
select reunvo_liberar('00000000-0000-0000-0000-0000000000a8','00000000-0000-0000-0000-00000000000a');
update clients set name='Deale (prueba)' where id='00000000-0000-0000-0000-00000000000a';
select 'renombrado', cliente from companies where company_name='x5';
select 'vista', company_name, cliente from companies_con_cliente where company_name='x1';
