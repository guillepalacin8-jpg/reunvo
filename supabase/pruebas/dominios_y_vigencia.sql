-- Prueba local (réplica, datos ficticios): dominio normalizado, dominios no agrupables y vigencia de reservas sin envío.
truncate companies, campaigns, avisos_guillem, lotes cascade;
select 'norm', reunvo_dominio('https://www.MediaMarkt.es/ruta'), reunvo_dominio('http://mediamarkt.es'), reunvo_dominio('www.x.com'), reunvo_dominio_clave('https://www.gmail.com/'), reunvo_dominio_clave('hotmail.es');
insert into companies(id,company_name,nif,domain,contact_email,region,status,assigned_client_id) values
 ('00000000-0000-0000-0000-0000000000b1','u1','U1','https://www.grupo.es/a','u1@x.test','DEMO','pending',null),
 ('00000000-0000-0000-0000-0000000000b2','u2','U2','http://grupo.es','u2@x.test','DEMO','pending','00000000-0000-0000-0000-00000000000a'),
 ('00000000-0000-0000-0000-0000000000b3','g1','G1','gmail.com','g1@gmail.com','DEMO','pending','00000000-0000-0000-0000-00000000000a'),
 ('00000000-0000-0000-0000-0000000000b4','g2','G2','https://www.gmail.com','g2@gmail.com','DEMO','pending','00000000-0000-0000-0000-00000000000a'),
 ('00000000-0000-0000-0000-0000000000b5','r1','R1','res1.test','r1@x.test','DEMO','pending','00000000-0000-0000-0000-00000000000a'),
 ('00000000-0000-0000-0000-0000000000b6','r2','R2','res2.test','r2@x.test','DEMO','pending','00000000-0000-0000-0000-00000000000a');
select 'B_reclama_u1', reunvo_reclamar('00000000-0000-0000-0000-0000000000b1','00000000-0000-0000-0000-00000000000b');
select 'u2_dueno(grupo por url distinta)', cliente from companies where company_name='u2';
select 'B_reclama_g1', reunvo_reclamar('00000000-0000-0000-0000-0000000000b3','00000000-0000-0000-0000-00000000000b');
select 'g2_dueno(debe ser libre: gmail no agrupa)', coalesce(cliente,'(libre)') from companies where company_name='g2';
insert into campaigns(company_id,client_id,status) values ('00000000-0000-0000-0000-0000000000b4','00000000-0000-0000-0000-00000000000a','draft_created');
select 'g2_A_puede_enviar(debe ser 1)', count(*) from campaigns where company_id='00000000-0000-0000-0000-0000000000b4';
-- reservas sin envío: r1 reciente de B (bloquea), r2 de hace 13 meses (caducada)
update companies set cliente_id_asignado='00000000-0000-0000-0000-00000000000b', asignada_desde=now()-interval '2 months', asignada_hasta=null where company_name='r1';
update companies set cliente_id_asignado='00000000-0000-0000-0000-00000000000b', asignada_desde=now()-interval '13 months', asignada_hasta=null where company_name='r2';
select 'elegibles_A', string_agg(co.company_name, ',' order by co.company_name) from companies co, clients c where c.id='00000000-0000-0000-0000-00000000000a' and reunvo_elegible(co,c);
