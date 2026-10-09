# Hoja de ruta

Cada paso termina con código, pruebas automatizadas y documentación de la metodología.

## Paso 0 — Organización ✅
- Estructura del paquete Julia por capas (núcleo → datos → agrupación → medición → reportes).
- Modelo de datos propio, centrado en el **contrato** y en **supuestos legibles** por portafolio/cohorte/producto
  (sin tablas de IDs intermedios).
- El esquema (`src/datos/esquema.jl`) es la fuente única: de él salen la lectura, la validación,
  la plantilla Excel y el diccionario de datos.

## Paso 1 — Núcleo ✅
- Tipos de dominio (`Contrato`, `MovimientoPrima`, `Portafolio`, `SupuestosGrupo`, `GrupoContratos`).
- Calendario mensual y fracción devengada (diaria o mensual).
- Configuración (hoja `configuracion` del Excel): corte, políticas (IACF diferir/gasto, devengo, descuento), umbrales de onerosidad.
- Lectura desde un único Excel de insumos (o CSV) y validación con reporte por hoja y fila.

## Paso 2 — Agrupación y onerosidad inicial ✅
- Fecha de reconocimiento (párr. 25) y cohorte anual (párr. 22).
- Test de onerosidad por conjunto portafolio × cohorte × producto (párr. 16–19, 47, 57).
- Tres clases: ONEROSO / SIN_RIESGO_SIGNIFICATIVO / RESTANTE.
- Grupos fijados en el reconocimiento inicial y persistidos entre cortes (párr. 24).
- Metodología: [`01_agrupacion_y_onerosidad.md`](01_agrupacion_y_onerosidad.md).

## Paso 3 — LRC PAA y onerosidad posterior ⏳
- Devengo de la prima por contrato y movimiento (ingreso por seguro, B126).
- IACF: diferidos y amortizados con el devengo, o a gasto (configurable).
- Roll-forward mensual del LRC por grupo hasta cualquier corte.
- Test de onerosidad en cada corte (párr. 57–58): componente de pérdida, su reconocimiento y reversión.
- Control: `LRC = prima no devengada − IACF por amortizar` en forma cerrada.

## Paso 4 — Descuento
- Curvas: interpolación, factores de descuento, tasas *locked-in* por cohorte.
- Test de onerosidad con flujos descontados usando `patron_pagos`.
- Componente financiero del LRC PAA cuando aplique (párr. 56).

## Paso 5 — Resultados y movimientos
- Ingreso por seguro, gasto del servicio de seguro (siniestros, gastos, amortización IACF, pérdidas en onerosos).
- Tablas de conciliación de saldos (párr. 100–105) y salida en Excel.

## Paso 6 — GMM
- Proyección de flujos futuros (primas, siniestros, gastos, caducidad), BEL, RA, CSM.
- Unidades de cobertura, acreción a tasa *locked-in*, liberación del CSM, componente de pérdida GMM.
- Onerosidad GMM con flujos descontados incluidas las primas futuras (párr. 47).

## Paso 7 — Ampliaciones
- LIC (siniestros incurridos), reaseguro cedido, opción OCI, transición.
- Conciliación contra resultados externos (p. ej. asientos contables de otra herramienta).
