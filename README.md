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

## Cómo usarlo

👉 **Lea [`GUIA_DE_USO.md`](GUIA_DE_USO.md)**. En resumen: instale Julia, llene el Excel
`plantillas/IFRS17_Insumos_PLANTILLA.xlsx` y arrástrelo sobre `EJECUTAR.bat`. Los resultados quedan en
un Excel en la carpeta `resultados`. Con doble clic en `EJECUTAR.bat` corre el ejemplo
(`datos/ejemplo/IFRS17_Insumos_ejemplo.xlsx`, datos sintéticos).

Para desarrolladores:

```bash
julia --project=. -e 'using Pkg; Pkg.test()'             # pruebas
julia --project=. scripts/generar_plantillas.jl          # regenera plantilla, ejemplo y diccionario
```

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
datos/ejemplo/           Excel de ejemplo con datos sintéticos (y su versión CSV)
plantillas/              Excel de insumos vacío + diccionario de datos (generados desde el esquema)
EJECUTAR.bat             ejecutar en Windows (arrastrar el Excel encima)
GUIA_DE_USO.md           guía paso a paso
docs/                    hoja de ruta, marco normativo y metodología por módulo
```

## Insumos y resultados

- Insumos: un Excel con una hoja por tabla — diccionario completo en
  [`plantillas/DICCIONARIO_DE_DATOS.md`](plantillas/DICCIONARIO_DE_DATOS.md).
- Resultados: `resultados/resultados_<corte>.xlsx` (resumen, onerosidad_inicial, grupos,
  clasificacion_contratos, incidencias).
