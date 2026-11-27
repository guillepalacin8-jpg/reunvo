"""Fuente única de los catálogos del panel (CNAE 2009 por división, CCAA y provincias INE).
Genera assets/catalogos.js (panel) y supabase/pendiente/2026-11-28_02_catalogos_seed.sql (tablas).
Uso: python3 supabase/catalogos/generar.py  (desde la raíz del repo)."""
import json, os

# CNAE 2009 (INE): sección, título, [(división, título, etiqueta sector_simplified)]
CNAE = [
 ("A","Agricultura, ganadería, silvicultura y pesca",[("01","Agricultura, ganadería, caza y servicios relacionados","Agroalimentario"),("02","Silvicultura y explotación forestal","Agroalimentario"),("03","Pesca y acuicultura","Agroalimentario")]),
 ("B","Industrias extractivas",[("05","Extracción de antracita, hulla y lignito","Industrial"),("06","Extracción de crudo de petróleo y gas natural","Industrial"),("07","Extracción de minerales metálicos","Industrial"),("08","Otras industrias extractivas","Industrial"),("09","Actividades de apoyo a las industrias extractivas","Industrial")]),
 ("C","Industria manufacturera",[("10","Industria de la alimentación","Alimentación y bebidas"),("11","Fabricación de bebidas","Alimentación y bebidas"),("12","Industria del tabaco","Alimentación y bebidas"),("13","Industria textil","Industrial"),("14","Confección de prendas de vestir","Industrial"),("15","Industria del cuero y del calzado","Industrial"),("16","Industria de la madera y del corcho, excepto muebles; cestería y espartería","Industrial"),("17","Industria del papel","Industrial"),("18","Artes gráficas y reproducción de soportes grabados","Industrial"),("19","Coquerías y refino de petróleo","Industrial"),("20","Industria química","Industrial"),("21","Fabricación de productos farmacéuticos","Salud y bienestar"),("22","Fabricación de productos de caucho y plásticos","Industrial"),("23","Fabricación de otros productos minerales no metálicos","Industrial"),("24","Metalurgia; fabricación de productos de hierro, acero y ferroaleaciones","Industrial"),("25","Fabricación de productos metálicos, excepto maquinaria y equipo","Industrial"),("26","Fabricación de productos informáticos, electrónicos y ópticos","Tecnología"),("27","Fabricación de material y equipo eléctrico","Industrial"),("28","Fabricación de maquinaria y equipo n.c.o.p.","Industrial"),("29","Fabricación de vehículos de motor, remolques y semirremolques","Industrial"),("30","Fabricación de otro material de transporte","Industrial"),("31","Fabricación de muebles","Industrial"),("32","Otras industrias manufactureras","Industrial"),("33","Reparación e instalación de maquinaria y equipo","Industrial")]),
 ("D","Suministro de energía eléctrica, gas, vapor y aire acondicionado",[("35","Suministro de energía eléctrica, gas, vapor y aire acondicionado","Medioambiente")]),
 ("E","Suministro de agua, saneamiento, gestión de residuos y descontaminación",[("36","Captación, depuración y distribución de agua","Medioambiente"),("37","Recogida y tratamiento de aguas residuales","Medioambiente"),("38","Recogida, tratamiento y eliminación de residuos; valorización","Medioambiente"),("39","Actividades de descontaminación y otros servicios de gestión de residuos","Medioambiente")]),
 ("F","Construcción",[("41","Construcción de edificios","Construcción e ingeniería"),("42","Ingeniería civil","Construcción e ingeniería"),("43","Actividades de construcción especializada","Construcción e ingeniería")]),
 ("G","Comercio al por mayor y al por menor; reparación de vehículos de motor y motocicletas",[("45","Venta y reparación de vehículos de motor y motocicletas","Retail y consumo"),("46","Comercio al por mayor e intermediarios del comercio","Distribución y logística"),("47","Comercio al por menor","Retail y consumo")]),
 ("H","Transporte y almacenamiento",[("49","Transporte terrestre y por tubería","Distribución y logística"),("50","Transporte marítimo y por vías navegables interiores","Distribución y logística"),("51","Transporte aéreo","Distribución y logística"),("52","Almacenamiento y actividades anexas al transporte","Distribución y logística"),("53","Actividades postales y de correos","Distribución y logística")]),
 ("I","Hostelería",[("55","Servicios de alojamiento","Hostelería y turismo"),("56","Servicios de comidas y bebidas","Hostelería y turismo")]),
 ("J","Información y comunicaciones",[("58","Edición","Comunicación y medios"),("59","Actividades cinematográficas, de vídeo y de televisión, grabación de sonido y edición musical","Comunicación y medios"),("60","Actividades de programación y emisión de radio y televisión","Comunicación y medios"),("61","Telecomunicaciones","Tecnología"),("62","Programación, consultoría y otras actividades relacionadas con la informática","Tecnología"),("63","Servicios de información","Tecnología")]),
 ("K","Actividades financieras y de seguros",[("64","Servicios financieros, excepto seguros y fondos de pensiones","Financiero y legal"),("65","Seguros, reaseguros y fondos de pensiones","Financiero y legal"),("66","Actividades auxiliares a los servicios financieros y a los seguros","Financiero y legal")]),
 ("L","Actividades inmobiliarias",[("68","Actividades inmobiliarias","Servicios")]),
 ("M","Actividades profesionales, científicas y técnicas",[("69","Actividades jurídicas y de contabilidad","Financiero y legal"),("70","Actividades de las sedes centrales; consultoría de gestión empresarial","Servicios"),("71","Servicios técnicos de arquitectura e ingeniería; ensayos y análisis técnicos","Construcción e ingeniería"),("72","Investigación y desarrollo","Tecnología"),("73","Publicidad y estudios de mercado","Comunicación y medios"),("74","Otras actividades profesionales, científicas y técnicas","Servicios"),("75","Actividades veterinarias","Salud y bienestar")]),
 ("N","Actividades administrativas y servicios auxiliares",[("77","Actividades de alquiler","Servicios"),("78","Actividades relacionadas con el empleo","Servicios"),("79","Agencias de viajes, operadores turísticos y servicios de reservas","Hostelería y turismo"),("80","Actividades de seguridad e investigación","Servicios"),("81","Servicios a edificios y actividades de jardinería","Servicios"),("82","Actividades administrativas de oficina y otras auxiliares a las empresas","Servicios")]),
 ("O","Administración Pública y defensa; Seguridad Social obligatoria",[("84","Administración Pública y defensa; Seguridad Social obligatoria","Servicios")]),
 ("P","Educación",[("85","Educación","Educación y formación")]),
 ("Q","Actividades sanitarias y de servicios sociales",[("86","Actividades sanitarias","Salud y bienestar"),("87","Asistencia en establecimientos residenciales","Salud y bienestar"),("88","Actividades de servicios sociales sin alojamiento","Salud y bienestar")]),
 ("R","Actividades artísticas, recreativas y de entretenimiento",[("90","Actividades de creación, artísticas y espectáculos","Comunicación y medios"),("91","Bibliotecas, archivos, museos y otras actividades culturales","Comunicación y medios"),("92","Actividades de juegos de azar y apuestas","Hostelería y turismo"),("93","Actividades deportivas, recreativas y de entretenimiento","Hostelería y turismo")]),
 ("S","Otros servicios",[("94","Actividades asociativas","Servicios"),("95","Reparación de ordenadores, efectos personales y artículos de uso doméstico","Servicios"),("96","Otros servicios personales","Servicios")]),
 ("T","Actividades de los hogares como empleadores o productores para uso propio",[("97","Actividades de los hogares como empleadores de personal doméstico","Servicios"),("98","Actividades de los hogares como productores de bienes y servicios para uso propio","Servicios")]),
 ("U","Actividades de organizaciones y organismos extraterritoriales",[("99","Actividades de organizaciones y organismos extraterritoriales","Servicios")]),
]
# CCAA (código INE, nombre) y provincias (código INE = 2 primeros dígitos del CP)
CCAA = [
 ("01","Andalucía",[("04","Almería"),("11","Cádiz"),("14","Córdoba"),("18","Granada"),("21","Huelva"),("23","Jaén"),("29","Málaga"),("41","Sevilla")]),
 ("02","Aragón",[("22","Huesca"),("44","Teruel"),("50","Zaragoza")]),
 ("03","Principado de Asturias",[("33","Asturias")]),
 ("04","Illes Balears",[("07","Illes Balears")]),
 ("05","Canarias",[("35","Las Palmas"),("38","Santa Cruz de Tenerife")]),
 ("06","Cantabria",[("39","Cantabria")]),
 ("07","Castilla y León",[("05","Ávila"),("09","Burgos"),("24","León"),("34","Palencia"),("37","Salamanca"),("40","Segovia"),("42","Soria"),("47","Valladolid"),("49","Zamora")]),
 ("08","Castilla-La Mancha",[("02","Albacete"),("13","Ciudad Real"),("16","Cuenca"),("19","Guadalajara"),("45","Toledo")]),
 ("09","Cataluña",[("08","Barcelona"),("17","Girona"),("25","Lleida"),("43","Tarragona")]),
 ("10","Comunitat Valenciana",[("03","Alicante"),("12","Castellón"),("46","Valencia")]),
 ("11","Extremadura",[("06","Badajoz"),("10","Cáceres")]),
 ("12","Galicia",[("15","A Coruña"),("27","Lugo"),("32","Ourense"),("36","Pontevedra")]),
 ("13","Comunidad de Madrid",[("28","Madrid")]),
 ("14","Región de Murcia",[("30","Murcia")]),
 ("15","Comunidad Foral de Navarra",[("31","Navarra")]),
 ("16","País Vasco",[("01","Araba/Álava"),("48","Bizkaia"),("20","Gipuzkoa")]),
 ("17","La Rioja",[("26","La Rioja")]),
 ("18","Ceuta",[("51","Ceuta")]),
 ("19","Melilla",[("52","Melilla")]),
]
# Zonas reservadas a la firma (dato inicial; en la base vive en zonas_reservadas).
RESERVADAS = {"ccaa":["09","02","13","10"],"metric":"result","min_eur":400000,"max_eur":50000000}

assert sum(len(d) for _,_,d in CNAE)==88 and sum(len(p) for _,_,p in CCAA)==52
root=os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
js={"cnae":[{"s":s,"t":t,"d":[{"c":c,"t":tt,"sec":sec} for c,tt,sec in d]} for s,t,d in CNAE],
    "ccaa":[{"c":c,"t":t,"p":[{"c":pc,"t":pt} for pc,pt in p]} for c,t,p in CCAA],
    "reservadas":RESERVADAS}
with open(os.path.join(root,"assets","catalogos.js"),"w") as f:
    f.write("/* Generado por supabase/catalogos/generar.py: no editar a mano. CNAE 2009 (INE) por división, CCAA y provincias INE. */\n")
    f.write("window.REUNVO_CATALOGOS="+json.dumps(js,ensure_ascii=False,separators=(",",":"))+";\n")
q=lambda s:"'"+s.replace("'","''")+"'"
L=["-- Generado por supabase/catalogos/generar.py: no editar a mano. Idempotente (upsert).","begin;"]
L.append("insert into public.cnae2009 (codigo, nivel, titulo, padre, sector_simplified) values")
rows=[]
for s,t,d in CNAE:
    rows.append(f"({q(s)},'seccion',{q(t)},null,null)")
    for c,tt,sec in d: rows.append(f"({q(c)},'division',{q(tt)},{q(s)},{q(sec)})")
L.append(",\n".join(rows)+"\non conflict (codigo) do update set nivel=excluded.nivel, titulo=excluded.titulo, padre=excluded.padre, sector_simplified=excluded.sector_simplified;")
L.append("insert into public.ccaa (codigo, nombre) values\n"+",\n".join(f"({q(c)},{q(t)})" for c,t,_ in CCAA)+"\non conflict (codigo) do update set nombre=excluded.nombre;")
L.append("insert into public.provincias (codigo, nombre, ccaa) values\n"+",\n".join(f"({q(pc)},{q(pt)},{q(c)})" for c,_,p in CCAA for pc,pt in p)+"\non conflict (codigo) do update set nombre=excluded.nombre, ccaa=excluded.ccaa;")
L.append("insert into public.zonas_reservadas (ccaa, metric, min_eur, max_eur, titular, activa) values\n"+",\n".join(f"({q(c)},'result',{RESERVADAS['min_eur']},{RESERVADAS['max_eur']},null,true)" for c in RESERVADAS['ccaa'])+"\non conflict (ccaa, metric) do nothing;  -- titular: id del cliente de la firma, se rellena a mano (ver 2026-11-28_04_config.sql)")
L.append("commit;")
with open(os.path.join(root,"supabase","pendiente","2026-11-28_02_catalogos_seed.sql"),"w") as f: f.write("\n".join(L)+"\n")
print("ok")
