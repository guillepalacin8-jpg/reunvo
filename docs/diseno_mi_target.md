# «Mi target» y cola del panel de cliente: diseño y plan de entrega

Estado: especificación. No se implementa ni se ejecuta SQL hasta que lo apruebe Guillem.
Proyecto Supabase: quywrltqzoyyorbsuiwc. Datos consultados el 27/11/2026, solo lectura.

## 0. Lo que hay hoy en la base (y condiciona el diseño)

| Dato | Situación |
|---|---|
| Facturación | `companies.revenue_eur` (bigint). Solo 5.703 de 19.773 empresas la tienen. **Unidades mezcladas**: mínimo 10.000 y máximo ≈ 5·10¹⁰. El panel lo trata como miles de €; hay que normalizarlo antes de filtrar por tramos. |
| Resultado del ejercicio | **No existe la columna.** Sí existe `criterio_sabi` = «resultado 400k-50M» en 14.735 empresas: se importaron de SABI con ese filtro, pero el valor no se guardó. |
| Sector | `sector_simplified`: 16 categorías propias + ~100 variantes sueltas mal normalizadas (p. ej. «Automotriz.», «Alimentación ») + 8.977 nulos. **No hay CNAE.** |
| Región | `region`: solo Cataluña (19.055), Aragón (718) y DEMO (23). |
| Provincia | No hay columna. `postal_code` solo en 718 empresas; la provincia sale de sus 2 primeros dígitos. `locality` es texto libre. |
| Solicitudes | `target_requests(region, sector, rev_min, rev_max, meta jsonb)`: 1 fila. `client_request_target` guarda texto libre sin validar. |

**Contexto del punto 4:** 14.735 de las ~19.800 empresas de la base (Cataluña + Aragón, «resultado 400k-50M») son el universo de la firma M&A, que hoy es el único cliente, así que es lo esperado. La reserva sirve para que OTROS clientes no pisen a la firma: el titular (`zonas_reservadas.titular`) queda exento y el resto no puede pedir ni recibir esas empresas. Para clientes nuevos (p. ej. el piloto Deale, aún por crear) el inventario disponible fuera del perímetro reservado es hoy de unas 5.000 empresas.

## 1. Criterio económico (facturación O resultado, con mínimo y máximo)

- UI: selector «Criterio» (Facturación / Resultado del ejercicio) y dos campos numéricos en M€ con validación (mín ≤ máx, ≥ 0).
- Datos:
  - `companies.result_eur bigint` (resultado del ejercicio en €) y `companies.fin_year int`.
  - Normalizar `revenue_eur` a € con una migración que detecte la escala por fila (o reimportar desde SABI).
  - `clients.target_metric text check (in ('revenue','result'))` + `target_min`, `target_max` (€). Se mantienen `target_revenue_*` por compatibilidad hasta migrar.
  - `target_requests.metric`.
- Funciones: `en_tramo()` pasa a recibir el valor según la métrica (`case c.target_metric when 'result' then co.result_eur else co.revenue_eur end`). Hay que tocar `reunvo_crear_lote`, `buscar_reemplazo`, `reunvo_mantener_colas`, `reunvo_reponer_cola`, `reunvo_ciclo_lotes` y `revision_cola`. Recomendación: una vista o función `reunvo_elegible(co, c)` única que usen todas, para que no vuelvan a divergir (hoy `mantener_colas` y `crear_lote` ya filtran distinto).
- Requiere reimportar de SABI la columna de resultado (el export existe: es el que generó `criterio_sabi`).
- Estimación: 1 día (½ SQL y migración, ½ UI) + reimportación.

## 2. Sector: desplegable con los sectores de SABI

- Fuente de la lista: **catálogo CNAE 2009 del INE** (21 secciones, 88 divisiones, 4 dígitos). Es lo que SABI exporta como «Código primario CNAE 2009». No hay que inventar la lista: tabla `cnae2009(codigo, nivel, titulo, padre)` cargada del fichero del INE (≈ 1.000 filas).
- Mapeo de empresas: reimportar del export de SABI la columna CNAE → `companies.cnae text` (4 dígitos). Para las que no lo traigan, como recurso: clasificar `activity_description` a división CNAE (lote con IA y revisión) y marcarlas `cnae_inferido = true`.
- Desplegable: dos niveles (sección → división), con recuento de empresas disponibles en cada opción para no ofrecer sectores vacíos. `sector_simplified` se mantiene como etiqueta legible derivada de `cnae2009` vía una tabla `sector_map(cnae_division → sector_simplified)`, y se limpian las ~100 variantes sueltas.
- Target: `clients.target_cnae text[]` (divisiones). Filtro `co.cnae like any(prefijos)`.
- Estimación: 1,5 días (carga del catálogo y mapeo ½, reimportación y relleno de nulos ½, UI ½). El relleno con IA de los 8.977 sin sector va aparte, aprox. ½ día más.

## 3. Región y zona: desplegables

- Tablas de referencia: `ccaa(codigo, nombre)` (19) y `provincias(codigo_ine, nombre, ccaa)` (52). El código de provincia coincide con los 2 primeros dígitos del código postal.
- `companies.provincia_ine char(2)` = `left(postal_code,2)`; reimportar CP/provincia de SABI para las 19.000 sin CP.
- UI: «Comunidad» (obligatorio) → «Provincia» (opcional, multiselección, solo las de esa comunidad). Mismo criterio para cualquier campo libre que quede: ningún `<input>` de texto en «Mi target».
- `client_request_target` valida contra las tablas y devuelve error legible si no cuadra.
- Estimación: 1 día.

## 4. Prioridad de la firma (zonas reservadas)

Regla de Guillem: un cliente no puede pedir Cataluña, Aragón, Madrid ni Comunidad Valenciana con resultado entre 400 k€ y 50 M€.

- Tabla `zonas_reservadas(ccaa, metric, min_eur, max_eur, titular, activa)` con esas 4 filas (resultado 400.000–50.000.000). Así cambiar la regla es un dato y no hay que redesplegar.
- Validación en el servidor (`client_request_target`) y, como segunda barrera, en `reunvo_elegible`: una empresa de una CCAA reservada con resultado dentro del rango nunca entra en la cola de un cliente que no sea el titular (`clients.id <> zonas_reservadas.titular`).
- Solape: se rechaza si el tramo pedido **se solapa** con el reservado, no solo si está contenido. Ejemplo: Cataluña, resultado 30–80 M€ → se rechaza, o se ofrece «solo > 50 M€».
- Con facturación como métrica no se puede comprobar el resultado en la solicitud. La exclusión se aplica igual por empresa en `reunvo_elegible` usando `result_eur`; si una empresa no tiene resultado, se excluye por precaución (a decidir).
- UI: en el desplegable de comunidad, las reservadas aparecen con nota «solo resultado < 400 k€ o > 50 M€», y el mensaje de error explica qué ajustar.
- Estimación: ½ día.

## 5. Cola, «Quitar» y plazos (rama fix/panel-cola-cupo)

Hecho en la rama y sin desplegar: panel + `supabase/pendiente/2026-11-27_panel_cola_cupo.sql`.
- client_panel muestra el próximo lote con su objetivo; Quitar es definitivo y la sustituta sale del pool o del lote siguiente.
- Plazos (decisión 27-nov): `dias_aprobacion = 14`; fecha límite = inicio − 7 (`clients.dias_revision`, semana de revisión de correos). Si el cliente aprueba antes, `client_lote_verificado` adelanta el inicio a aprobación + 7 (`lotes.adelantado`). `reunvo_crear_lote` garantiza inicio ≥ hoy + 14 + 7.
- Aprobación automática (opción A): si el cliente no aprueba como tarde en la fecha límite, `reunvo_ciclo_lotes` la da por aprobada ese día tal como esté (lo quitado, quitado queda), marca `lotes.aprobado_auto` y los envíos salen en la fecha fijada (tras la revisión de correos de esa semana).
- Cabecera: «Apruebe antes del DD/MM · Envíos a partir del DD/MM»; tras aprobar: «Envíos a partir del DD/MM (7 días tras su aprobación)»; tras la fecha límite: «Lista aprobada automáticamente el DD/MM».
- Pendiente de decidir: hoy el cliente puede seguir quitando empresas de una lista ya aprobada (hasta que se envían). Si la aprobación debe cerrarla, basta con limitar `client_toggle_company` a lotes en estado 'cliente' y ocultar «Quitar».
- Cupo por cliente: la firma va a 35/día × 20; el piloto Deale serían 15/día con cola_objetivo_dias = 21 → 315/mes.

## 6. Plan de entrega, semana del 30/11 al 4/12

| Día | Trabajo | SQL | Decide Guillem antes |
|---|---|---|---|
| L 30/11 | Desplegar cola/Quitar (c602f4b) + SQL pendiente. (Los envíos siguen en pausa por decisión de Guillem; esto no los reactiva.) | `2026-11-27_panel_cola_cupo.sql`; `dias_aprobacion` y objetivo del cliente | Cupo y días de aprobación por cliente (Deale, piloto por crear: 15/día → 315/mes) |
| M 1/12 | Tablas de referencia (ccaa, provincias, cnae2009, sector_map, zonas_reservadas) + columnas nuevas | migración de esquema, sin tocar datos | Lista de zonas reservadas (¿alguna más?) |
| X 2/12 | Reimportar de SABI: resultado, CNAE, CP/provincia; normalizar `revenue_eur` | carga de datos (staging → merge) | Export SABI con esas columnas |
| J 3/12 | `reunvo_elegible` único + `client_request_target` con validación y regla de la firma; adaptar las 6 funciones | funciones | Qué hacer con empresas sin resultado en CCAA reservada |
| V 4/12 | UI «Mi target» con desplegables y criterio económico; pruebas Playwright con mocks; despliegue | — | Visto bueno final |

Total estimado: unos 4,5 días de trabajo, más la reimportación de SABI. Lo que más riesgo tiene para el calendario es esa reimportación.
