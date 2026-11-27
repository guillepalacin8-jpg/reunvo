# Prueba de una semana «como si fuéramos Deale»

Rama `fix/panel-cola-cupo`. Empieza solo cuando Guillem dé el sí al despliegue. Mientras dura la prueba:
- **ningún email a empresas reales**: los envíos de Reunvo siguen EN PAUSA y no se reactivan;
- **todos los avisos van a Guillem**.

## 0. Preparación (día 0, con el sí de Guillem)

1. Ejecutar SQL 01→04 en quywrltqzoyyorbsuiwc y desplegar `panel_cliente.html` + `assets/catalogos.js`.
2. Crear el cliente de prueba «Deale (prueba)» con estos valores:
   - `is_test = true`, `status = 'active'`;
   - `emails_per_day = 15`, `cola_objetivo_dias = 21` (315/mes);
   - `dias_aprobacion = 14`, `dias_revision = 7`, `bloquear_quitar_tras_aprobar = true`;
   - `envio_pausado = true` y `modo_envio = 'borrador'`;
   - `target_region = 'DEMO'`.
   - Email de contacto y del consultor: los de Guillem. Así cualquier aviso «al cliente» le llega a él.
3. Sin Gmail conectado para ese cliente (`client_tokens` vacío). Sin token, el flujo de envío no puede mandar nada aunque se active por error.
4. Inventario de prueba: ~500 empresas ficticias con región DEMO y emails `@example.invalid`, un dominio que no existe y no recibe correo.
   - Repartir por varias CCAA y provincias, sectores CNAE, resultados y edades del DG para probar el target.
   - Incluir ~60 en el perímetro reservado (Cataluña, resultado 0,4–50 M€) para comprobar que no le entran a «Deale».
5. Tres listas para que los plazos caigan dentro de la semana:
   - una «en curso» con 200 pendientes;
   - una pendiente con fecha límite el día 3;
   - otra con fecha límite el día 5, para la aprobación automática.

## 1. Comprobación diaria (Guillem, ~10 min; Claude lo verifica con SELECT)

| # | Qué mirar | Bien si… |
|---|---|---|
| 1 | Envíos reales | `campaigns` sin filas nuevas del cliente de prueba ni de nadie (pausa) |
| 2 | Cola | «En su lista» = 315 de 315 mientras haya reserva; si no, aviso «Faltan N» y fila en `reposicion_requests` |
| 3 | Quitar | 10 quitadas al día (incluye doble clic y dos pestañas): ninguna reaparece, ninguna sustituta repetida, ninguna del perímetro reservado, contactada o de otro cliente |
| 4 | Cabecera | Mes correcto; «Apruebe antes del…» = inicio − 7; «Envíos a partir del…» nunca antes del fin de la lista en curso |
| 5 | Target | Una solicitud nueva al día: facturación o resultado, CNAE, CCAA/provincia y edad. Le llega a Guillem en el panel de administración |
| 6 | Zona no disponible | El mensaje es neutro y no da cifras ni motivo |
| 7 | Textos | Ninguna mención a exclusividad ni a la reserva en el panel |
| 8 | Avisos | Todos los avisos del día llegaron a Guillem y a nadie más |
| 9 | Errores | Ningún error en el navegador (consola) ni en los registros de Supabase para las funciones `client_*` |

## 2. Calendario

| Día | Prueba principal |
|---|---|
| L | Despliegue + preparación. Recorrido completo del panel en escritorio y móvil |
| M | Quitar intensivo: 50 seguidas, doble clic, dos pestañas, y agotar la reserva para ver el aviso |
| X | Aprobar antes de plazo: el inicio es aprobación + 7 o el fin de la lista en curso. Tras aprobar, Quitar bloqueado |
| J | Target: todas las combinaciones, zona no disponible y solicitud aplicada desde administración (la lista siguiente respeta el target) |
| V | Vence el plazo de la tercera lista: aprobación automática con «Lista aprobada automáticamente el…». Repaso de la semana |
| S–D | Sin tocar: el ciclo automático no debe crear listas raras ni enviar nada |

## 3. Criterio «sin errores» para pasar a Deale

Se pasa a Deale solo si se cumplen todas:
- 0 emails enviados a empresas reales;
- 0 empresas quitadas que reaparecen;
- 0 sustitutas repetidas o ajenas;
- la cola nunca baja del cupo mientras haya reserva;
- 0 fechas de inicio que se solapen con la lista en curso;
- 0 menciones a exclusividad o a la reserva;
- 0 errores de consola o de base de datos en los flujos del cliente;
- todos los avisos llegaron solo a Guillem.

Un solo fallo reinicia el contador de días limpios: hacen falta 5 días laborables seguidos sin fallos.

## 4. Pendiente de Guillem antes de Deale

- Filtro de edad del DG: lo fija Guillem con SABI (edad > 60). Si no hay empresas suficientes, se le dice a Deale y Deale decide.
- Reimportar de SABI, cruzando por NIF: resultado, CNAE, código postal y fecha de nacimiento del DG.
