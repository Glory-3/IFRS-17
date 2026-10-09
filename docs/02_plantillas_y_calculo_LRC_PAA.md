# Fase 1 — Plantillas de insumos y cálculo LRC PAA

Plantilla: [`plantillas/IFRS17_Insumos_LRC.xlsx`](../plantillas/IFRS17_Insumos_LRC.xlsx)

## Decisiones tomadas

| Tema | Decisión | Dónde se cambia |
|---|---|---|
| Alcance | Solo **LRC**. LIC queda para una fase posterior. | — |
| Base de prima | **Prima emitida** (la cartera por cobrar queda dentro del LRC). | `Parametros!Base_Prima_LRC` |
| IACF | **Diferir y amortizar** con el patrón de devengo. | `Parametros!Politica_IACF` = `DIFERIR` / `GASTO` |
| Gastos | Factores sobre prima emitida por `Expenses_ID` y concepto, clasificados en `Acquisition_Costs` y `Expenses_Cash_Flows`. | `Gastos_Factores`, `Mapeo_Gastos` |
| Validación | Contra los *journal entries* del cierre de Addactis. | Archivo aparte, lector dedicado |

## Relación con Addactis (Generic_Inputs_Projection)

| Hoja de la plantilla | Hoja Addactis | Comentario |
|---|---|---|
| `GoC` | `0. GoC` | Se conservan GoC_ID, Expenses_ID, Loss_ratio_ID, Claims_pattern_ID, RA_Percentage_of_claims, Inception_Date, End_Of_Coverage_Period, YC. Se añaden Portafolio, Cohorte, Modelo, Clase_Onerosidad. |
| `Primas_Emitidas` | — (reemplaza `1.1 WP emission` + `Total_Future_Written_Premiums`) | Addactis proyecta prima futura con patrón de emisión; para el cierre usamos el **histórico real** con vigencias. |
| `Gastos_Factores` | `3.1. Expenses & Commissions` | Mismas columnas; copiar/pegar. |
| `Mapeo_Gastos` | Configuración `Type_of_Cashflow` | Nueva: clasifica cada `Expenses_Label`. Propuesta inicial a confirmar. |
| `Loss_Ratios` | `2.1. Loss ratios` | Mismas columnas. |
| `Patron_Siniestros` | `2.2. Claims pattern by ID` | Mismas columnas. |
| `Clases_Rentabilidad` | `4.1. Profitability Class` | Mismas columnas. |
| `Curvas` | `YCSOL` (referenciada) | Nueva: curva explícita. |
| No se usan en LRC PAA | `1.3`, `1.4`, `2.3`, `2.4`, `Lapse_rate` | Recaudo, recobros y caducidad: se retoman en GMM/LIC. |

## Cálculo LRC PAA que implementará el motor

Para cada grupo `g` y mes `t` (fin de mes), con cada registro de prima `i` del grupo:

**Fracción devengada** (base `DIARIO`):

```
f_i(t) = clamp( (min(t, Fin_i) − Inicio_i + 1) / (Fin_i − Inicio_i + 1), 0, 1 )   si Fecha_Emision_i ≤ t, si no 0
```

**Prima**

```
PE_g(t)  = Σ_i Prima_Emitida_i   con Fecha_Emision_i en el mes t        (entra al LRC)
ING_g(t) = Σ_i Prima_Emitida_i × [f_i(t) − f_i(t−1)]                   (ingreso por seguro)
PND_g(t) = Σ_i Prima_Emitida_i × [1 − f_i(t)]                          (prima no devengada)
```

**IACF** (`Acquisition_Costs`), factor `a_g = Σ Rate` de los conceptos mapeados a `Acquisition_Costs` del `Expenses_ID` del grupo:

```
IACF_pagado_g(t)     = a_g × PE_g(t)
Amort_IACF_g(t)      = a_g × ING_g(t)        si DIFERIR ;  = IACF_pagado_g(t) si GASTO
IACF_por_amort_g(t)  = a_g × PND_g(t)        si DIFERIR ;  = 0               si GASTO
```

**Saldo LRC (sin componente de pérdida)**

```
LRC_g(t) = LRC_g(t−1) + PE_g(t) − IACF_pagado_g(t) + Amort_IACF_g(t) − ING_g(t)
         = PND_g(t) − IACF_por_amort_g(t)           (forma cerrada, sirve de control)
```

**Test de onerosidad y componente de pérdida** (`Test_Onerosidad = SI`):

```
Ratio_g = LR_g × (1 + RA%_g) + e_g + a_g            (e_g = Σ Rate de Expenses_Cash_Flows)
Clase   = Onerous si Ratio_g > 1 (umbral de Clases_Rentabilidad)
FCF_g(t) = PND_g(t) × [LR_g × (1 + RA%_g) + e_g]    (descontado con Patron_Siniestros + Curvas si aplica)
LC_g(t)  = max(0, FCF_g(t) − LRC_g(t))
```

**Saldo de cierre** `LRC_total_g(t) = LRC_g(t) + LC_g(t)`, con su tabla de movimientos:
saldo inicial, primas emitidas, IACF pagados, amortización IACF, ingreso por seguro, cambio del componente de pérdida y saldo final.

> Las fórmulas exactas de onerosidad y de descuento se ajustarán al comparar con los journal entries de Addactis
> (p. ej. si Addactis aplica el RA sobre siniestros o si descuenta el FCF del test).

## Pendientes para confirmar

1. **Mapeo de gastos**: revisar la columna amarilla de `Mapeo_Gastos` (propuesta inicial).
2. **Devengo en Addactis**: ¿diario por vigencia de póliza o mensual? ¿A nivel póliza o a nivel GoC con `End_Of_Coverage_Period`?
3. **Cohortes**: todos los GoC del archivo tienen `Inception_Date = 2024-01-01`. ¿Cada año se crean nuevos GoC_ID o se reutilizan los mismos?
4. **Componente financiero**: hay GoC con fin de cobertura en 2030–2073. ¿Addactis descuenta el LRC de esos grupos?
5. **Journal entries**: subir el archivo tal cual lo exporta Addactis para construir el lector y la conciliación.
