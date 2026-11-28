-- Vuelta atrás del relleno (06 sigue en pie): deja a todas las empresas sin dueño.
update public.companies set cliente_id_asignado = null, asignada_desde = null, asignada_hasta = null where cliente_id_asignado is not null;
