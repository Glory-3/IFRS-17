# Motor IFRS 17 en Julia

Motor propio de medición de contratos de seguro bajo IFRS 17, construido desde la norma
(no como réplica de ninguna herramienta comercial). Objetivo: calcular el saldo de cierre del
**LRC** (y más adelante del **LIC**) a cualquier fecha de corte, bajo **PAA** y **GMM**, con la
tabla de movimientos completa.

## Estado

| Paso | Contenido | Estado |
|---|---|---|
| 0 | Organización del proyecto, modelo de datos propio, plantillas | ✅ |
| 1 | Núcleo: tipos, calendario, configuración, lectura y validación de insumos | ✅ |
| 2 | Reconocimiento, cohortes, **test de onerosidad inicial** y formación de grupos | ✅ |
| 3 | LRC PAA: devengo, IACF, roll-forward y **onerosidad posterior** (componente de pérdida) | ⏳ siguiente |
| 4 | Descuento: curvas, componente financiero, test de onerosidad descontado | |
| 5 | Estado de resultados IFRS 17 y tabla de movimientos (párr. 100–105) | |
| 6 | GMM: BEL, RA, CSM, unidades de cobertura | |
| 7 | LIC, reaseguro cedido, conciliación contra sistemas externos | |

Detalle en [`docs/00_hoja_de_ruta.md`](docs/00_hoja_de_ruta.md).

## Uso rápido

```bash
julia --project=. -e 'using Pkg; Pkg.instantiate()'     # una vez
julia --project=. scripts/ejecutar.jl                    # corre el ejemplo
julia --project=. scripts/ejecutar.jl ruta/configuracion.toml
julia --project=. -e 'using Pkg; Pkg.test()'             # pruebas
```

Los datos de `datos/ejemplo/` son **sintéticos** (`scripts/generar_datos_ejemplo.jl`).
Los datos reales van en `datos/privados/` (excluido de git).

## Estructura

```
src/
  IFRS17.jl              módulo principal
  nucleo/                tipos de dominio, calendario, configuración (TOML)
  datos/                 esquema de insumos (fuente única), lectura CSV, validación
  agrupacion/            reconocimiento, cohortes, test de onerosidad, grupos
  reportes/              tablas de salida y corrida completa (`ejecutar`)
test/                    pruebas automatizadas (casos calculados a mano)
scripts/                 ejecución y generación de datos de ejemplo
datos/ejemplo/           insumos sintéticos + configuracion.toml
plantillas/              CSV vacíos + diccionario de datos (generados desde el esquema)
docs/                    hoja de ruta, marco normativo y metodología por módulo
```

## Insumos

Un CSV por tabla (diccionario completo en [`plantillas/LEEME.md`](plantillas/LEEME.md)):

| Tabla | Contenido |
|---|---|
| `contratos` | Una fila por póliza: portafolio, producto, emisión, vigencia |
| `primas` | Movimientos de prima emitida (emisión, endoso, cancelación) |
| `portafolios` | Portafolios y su modelo de medición (PAA / GMM) |
| `supuestos_siniestralidad` | Siniestralidad esperada y RA por portafolio / cohorte / producto |
| `supuestos_gastos` | Factores de gasto por concepto, clasificados ADQUISICION / MANTENIMIENTO / NO_ATRIBUIBLE |
| `patron_pagos`, `curvas` | (opcionales) para descuento |
| `clasificacion_previa` | (opcional) clase de onerosidad ya asignada en cortes anteriores |

## Salidas (paso 2)

`incidencias.csv`, `onerosidad_inicial.csv`, `grupos.csv`, `clasificacion_contratos.csv`
(esta última se usa como `clasificacion_previa` en el siguiente corte).
