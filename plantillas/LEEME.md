# Diccionario de datos de insumos

Generado automáticamente desde `src/datos/esquema.jl`. Un archivo CSV por tabla, codificación UTF-8, fechas `aaaa-mm-dd`, tasas y factores como fracción.

## `contratos.csv`

Un registro por contrato (póliza). Atributos que no cambian en el tiempo.

| Columna | Tipo | Obligatoria | Descripción | Valores |
|---|---|---|---|---|
| `contrato_id` | texto | sí | Identificador único del contrato. |  |
| `portafolio_id` | texto | sí | Portafolio al que pertenece (debe existir en portafolios). |  |
| `producto` | texto | no | Producto o ramo comercial (informativo). |  |
| `fecha_emision` | fecha | sí | Fecha de emisión del contrato. |  |
| `inicio_cobertura` | fecha | sí | Inicio del periodo de cobertura. |  |
| `fin_cobertura` | fecha | sí | Fin del periodo de cobertura (incluido). |  |
| `fecha_primer_pago` | fecha | no | Vencimiento del primer pago del tomador (párr. 25(b)). Vacío = fecha_emision. |  |

## `primas.csv`

Movimientos de prima emitida. Cancelaciones y devoluciones con monto negativo.

| Columna | Tipo | Obligatoria | Descripción | Valores |
|---|---|---|---|---|
| `contrato_id` | texto | sí | Contrato al que corresponde el movimiento. |  |
| `fecha_contable` | fecha | sí | Fecha en que se registra la prima emitida. |  |
| `tipo_movimiento` | texto | sí | Tipo de movimiento. | EMISION, ENDOSO, CANCELACION, RENOVACION |
| `monto` | número | sí | Prima emitida del movimiento (negativa si es devolución). |  |
| `inicio_cobertura` | fecha | no | Inicio de la cobertura de este movimiento. Vacío = la del contrato. |  |
| `fin_cobertura` | fecha | no | Fin de la cobertura de este movimiento. Vacío = la del contrato. |  |

## `portafolios.csv`

Un registro por portafolio (párr. 14).

| Columna | Tipo | Obligatoria | Descripción | Valores |
|---|---|---|---|---|
| `portafolio_id` | texto | sí | Identificador del portafolio. |  |
| `descripcion` | texto | no | Descripción. |  |
| `modelo_medicion` | texto | sí | Modelo de medición. | PAA, GMM |
| `curva_id` | texto | no | Curva de descuento (tabla curvas). |  |

## `supuestos_siniestralidad.csv`

Siniestralidad esperada y RA. Se busca primero (portafolio, cohorte, producto), luego sin producto, luego cohorte 0 con producto y por último cohorte 0 sin producto.

| Columna | Tipo | Obligatoria | Descripción | Valores |
|---|---|---|---|---|
| `portafolio_id` | texto | sí | Portafolio. |  |
| `cohorte` | entero | sí | Año de la cohorte, o 0 para todas. |  |
| `producto` | texto | no | Producto al que aplica. Vacío = todos los productos del portafolio. |  |
| `siniestralidad_esperada` | número | sí | Siniestros esperados / prima (0.65 = 65%). |  |
| `ajuste_riesgo_pct` | número | sí | RA como fracción de los siniestros esperados (0.05 = 5%). |  |

## `supuestos_gastos.csv`

Factores de gasto sobre prima emitida, por concepto. Se usa el conjunto de filas de la clave más específica que exista, con la misma prioridad que supuestos_siniestralidad.

| Columna | Tipo | Obligatoria | Descripción | Valores |
|---|---|---|---|---|
| `portafolio_id` | texto | sí | Portafolio. |  |
| `cohorte` | entero | sí | Año de la cohorte, o 0 para todas. |  |
| `producto` | texto | no | Producto al que aplica. Vacío = todos los productos del portafolio. |  |
| `concepto` | texto | sí | Nombre del gasto (comisión, administración, ...). |  |
| `clasificacion` | texto | sí | Tratamiento IFRS 17. | ADQUISICION, MANTENIMIENTO, NO_ATRIBUIBLE |
| `factor` | número | sí | Fracción de la prima emitida (0.12 = 12%). |  |

## `patron_pagos.csv` *(opcional)*

Patrón de pago de siniestros por portafolio (para descontar flujos). Debe sumar 1.

| Columna | Tipo | Obligatoria | Descripción | Valores |
|---|---|---|---|---|
| `portafolio_id` | texto | sí | Portafolio. |  |
| `mes_desarrollo` | entero | sí | Meses desde la ocurrencia (0 = mismo mes). |  |
| `proporcion` | número | sí | Proporción del siniestro pagada en ese mes. |  |

## `curvas.csv` *(opcional)*

Curvas de descuento. Tasa efectiva anual por plazo.

| Columna | Tipo | Obligatoria | Descripción | Valores |
|---|---|---|---|---|
| `curva_id` | texto | sí | Identificador de la curva. |  |
| `fecha_curva` | fecha | sí | Fecha a la que corresponde la curva. |  |
| `plazo_meses` | entero | sí | Plazo en meses. |  |
| `tasa_ea` | número | sí | Tasa efectiva anual (0.095 = 9.5%). |  |

## `clasificacion_previa.csv` *(opcional)*

Clase de onerosidad asignada en corridas anteriores (salida clasificacion_contratos.csv). Los contratos aquí listados conservan su grupo (párr. 24); solo se evalúan los nuevos.

| Columna | Tipo | Obligatoria | Descripción | Valores |
|---|---|---|---|---|
| `contrato_id` | texto | sí | Contrato. |  |
| `clase_onerosidad` | texto | sí | Clase asignada en el reconocimiento inicial. | ONEROSO, SIN_RIESGO_SIGNIFICATIVO, RESTANTE |
| `fecha_clasificacion` | fecha | no | Fecha de corte en que se clasificó. |  |

