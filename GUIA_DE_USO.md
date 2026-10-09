# Guía de uso — Motor IFRS 17

Esta guía explica, sin necesidad de programar, cómo poner a correr el motor con sus datos.

## Idea general

```
 Excel de insumos  ──►  EJECUTAR.bat  ──►  Excel de resultados
 (usted lo llena)       (doble clic)       (carpeta "resultados")
```

Todo lo que el motor necesita va en **un solo archivo Excel**. El motor lo lee, valida los datos,
calcula y deja otro Excel con los resultados.

---

## 1. Instalar (una sola vez)

1. **Instalar Julia** (el lenguaje en el que está hecho el motor).
   - Windows: abra *PowerShell* y escriba `winget install julia -s msstore`
     (o descargue el instalador desde <https://julialang.org/downloads/>).
   - Mac / Linux: en una terminal, `curl -fsSL https://install.julialang.org | sh`.
2. **Descargar el motor**: en GitHub, botón verde **Code → Download ZIP** y descomprímalo en una
   carpeta, por ejemplo `C:\IFRS17`. (Si usa git: `git clone` del repositorio.)
3. **Probar con el ejemplo**: haga **doble clic en `EJECUTAR.bat`**.
   La primera vez descarga librerías y tarda unos minutos; después es rápido.
   Debe ver un resumen en pantalla y el mensaje *"Resultados completos en: ...\resultados\resultados_2024-12-31.xlsx"*.

> Si su empresa usa proxy y falla la descarga de librerías, pida a TI permitir el acceso a
> `pkg.julialang.org` o ejecute el paso con la red de la casa la primera vez.

## 2. Preparar sus datos

1. Copie `plantillas/IFRS17_Insumos_PLANTILLA.xlsx` a una carpeta de trabajo, por ejemplo
   `C:\IFRS17\datos\privados\Insumos_2024-12.xlsx` (la carpeta `datos/privados` nunca se sube a GitHub).
2. Abra `datos/ejemplo/IFRS17_Insumos_ejemplo.xlsx` para ver **cómo** debe quedar cada hoja.
3. Llene las hojas (la hoja **INSTRUCCIONES** describe cada columna):

| Hoja | Qué poner | Ejemplo |
|---|---|---|
| `configuracion` | Fecha de corte y políticas | `fecha_corte = 2024-12-31`, `politica_iacf = DIFERIR` |
| `contratos` | Una fila por póliza | `POL001, AUTOS, AUTOS_LIVIANOS, 2024-03-01, 2024-03-01, 2025-02-28` |
| `primas` | Una fila por emisión, endoso o cancelación | `POL001, 2024-03-01, EMISION, 2400000` |
| `portafolios` | Sus portafolios y si van por PAA o GMM | `AUTOS, Automóviles, PAA` |
| `supuestos_siniestralidad` | Siniestralidad esperada y RA | `AUTOS, 0, , 0.60, 0.05` |
| `supuestos_gastos` | Cada gasto como % de la prima y su tipo | `AUTOS, 0, , Comisiones, ADQUISICION, 0.15` |
| `patron_pagos`, `curvas` | Opcionales (para descuento, pasos futuros) | |
| `clasificacion_previa` | Opcional: la clasificación del corte anterior | ver punto 4 |

Reglas: no cambie nombres de hojas ni encabezados; porcentajes como fracción (0.15) o con formato %;
cancelaciones en negativo; `cohorte = 0` significa "aplica a todas las cohortes".

**Tipos de gasto** (columna `clasificacion` en `supuestos_gastos`):
- `ADQUISICION`: comisiones y demás costos de vender el contrato.
- `MANTENIMIENTO`: administración, asistencias, contribuciones… atribuibles al contrato.
- `NO_ATRIBUIBLE`: gastos generales que no van en IFRS 17.

## 3. Correr

- **Windows**: arrastre su Excel y suéltelo **encima de `EJECUTAR.bat`**.
- **Mac / Linux**: `./ejecutar.sh ruta/al/archivo.xlsx`.

Si hay errores en los datos, el motor **no calcula** y le dice la hoja, la fila y el problema, por ejemplo:

```
[contratos] 1 errores, 0 advertencias
  ERROR fila 15: portafolio 'AUTO' no existe en portafolios
```

Corrija el Excel y vuelva a soltarlo sobre `EJECUTAR.bat`.

## 4. Leer los resultados

Se crea `resultados/resultados_<fecha de corte>.xlsx` junto a su Excel de insumos, con estas hojas:

| Hoja | Contenido |
|---|---|
| `resumen` | Cifras principales: contratos, grupos, grupos onerosos, pérdida inicial |
| `onerosidad_inicial` | Test por portafolio × cohorte × producto: prima, siniestros, RA, gastos, ratio, clase y pérdida |
| `grupos` | Grupos de contratos formados (portafolio × cohorte × clase) |
| `clasificacion_contratos` | Clase de cada póliza |
| `incidencias` | Advertencias encontradas en los datos |

**Para el siguiente cierre**: copie la hoja `clasificacion_contratos` dentro de la hoja
`clasificacion_previa` del nuevo Excel de insumos. Así cada póliza conserva el grupo que se le
asignó al inicio, como exige la norma (párr. 24).

## 5. ¿Qué calcula hoy y qué viene?

Hoy: validación de datos, fecha de reconocimiento, cohortes, **test de onerosidad inicial** y grupos.
Siguiente: **saldo del LRC (PAA) a cualquier corte** con su tabla de movimientos y el componente de
pérdida en cada cierre. Ver [`docs/00_hoja_de_ruta.md`](docs/00_hoja_de_ruta.md).

## ¿No quiere instalar nada todavía?

Puede enviar su Excel de insumos en la conversación con Claude y él ejecuta el motor y le devuelve
el Excel de resultados.
