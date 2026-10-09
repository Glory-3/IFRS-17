# Motor IFRS 17 en Julia — Análisis y arquitectura

> Documento de trabajo, fase 0. Aquí se define qué hay que calcular, qué datos hacen falta, qué dejamos fuera
> por ahora y cómo se organizaría el código. Se irá actualizando con cada fase.

---

## 1. Objetivo

Construir un motor local en Julia que:

1. Calcule el **saldo de cierre** de las reservas IFRS 17 a **cualquier fecha de corte**:
   - **LRC** (*Liability for Remaining Coverage*, pasivo por cobertura restante).
   - **LIC** (*Liability for Incurred Claims*, pasivo por siniestros incurridos).
2. Soporte dos modelos de medición:
   - **PAA** (*Premium Allocation Approach*, enfoque de asignación de primas), para replicar Addactis.
   - **GMM** (*General Measurement Model*, modelo general / BBA).
3. Genere la **tabla de movimientos** (saldo inicial → saldo final) para poder conciliar contra Addactis
   por cada partida, no solo el saldo final.
4. Sea rápido (miles de grupos × cientos de periodos mensuales en segundos) y reproducible.

Uso principal: **validar de forma independiente los cálculos PAA de Addactis** y, a partir de ahí,
extender a GMM.

---

## 2. Qué hay que calcular (resumen técnico)

### 2.1 Unidad de cálculo: el grupo de contratos

IFRS 17 mide por **grupo**: portafolio (riesgos similares, gestionados juntos) × **cohorte anual** (año de
emisión) × **clase de onerosidad** (oneroso / sin riesgo significativo de ser oneroso / resto).
Todo el motor trabaja a nivel `grupo`; la información de póliza solo se usa para construir los flujos del grupo.

### 2.2 LRC bajo PAA (párr. 55–58, B126)

Roll-forward por periodo:

```
LRC_cierre = LRC_inicial
           + primas recibidas
           − flujos de adquisición (IACF) pagados
           + amortización de IACF                 (si se difieren; si no, se llevan a gasto)
           − ingreso por seguro del periodo        (devengo de la prima esperada)
           + ajuste por componente financiero      (solo si cobertura > 1 año / financiación significativa)
           + componente de pérdida (LC)            (si el grupo es oneroso)
```

- **Ingreso por seguro**: prima esperada asignada por **paso del tiempo** (pro-rata temporis) o por el patrón
  esperado de liberación del riesgo si difiere significativamente.
- **Componente de pérdida (onerosidad)**: si los hechos indican onerosidad,
  `LC = FCF_LRC (PV salidas futuras + RA) − saldo LRC PAA`. Requiere siniestralidad esperada y gastos.
- **Punto a confirmar con Addactis**: si el LRC se construye sobre prima **recaudada** (norma) o sobre prima
  **emitida** con cuentas por cobrar dentro del pasivo (práctica frecuente). Cambia el saldo pero no el ingreso.

### 2.3 LIC (igual en PAA y GMM, párr. 40(b), 59(b))

```
LIC = PV(pagos futuros de siniestros ocurridos: RBNS + IBNR + gastos de liquidación ULAE) + RA_LIC
```

- Proyección de pagos futuros: a partir de **triángulos** (chain ladder / Bornhuetter-Ferguson) o recibiendo
  directamente el BEL nominal y el patrón de pagos desde Addactis.
- **Descuento** con curva vigente al corte; si se aplica la opción OCI, además con la curva *locked-in* a la
  fecha de ocurrencia para separar resultado financiero en PyG vs ORI.
- En PAA se puede **no descontar** si los pagos se esperan dentro de un año.
- Roll-forward: saldo inicial + siniestros incurridos del periodo + ajustes a periodos anteriores
  − pagos + intereses (*unwinding*) + efecto cambio de tasas + liberación/cambio del RA.

### 2.4 LRC bajo GMM (párr. 32–52, B96–B119)

En reconocimiento inicial de cada grupo/cohorte:

```
FCF_0 = PV(salidas: siniestros + gastos atribuibles + IACF) − PV(entradas: primas) + RA
CSM_0 = max(0, −FCF_0)      LC_0 = max(0, FCF_0)
```

Roll-forward del CSM:

```
CSM_cierre = CSM_inicial
           + CSM de nuevos negocios
           + intereses a tasa locked-in (de reconocimiento inicial)
           + cambios en FCF relacionados con servicio futuro (medidos a tasas locked-in)
           − liberación por servicio prestado = CSM_antes_liberación × CU_periodo / (CU_periodo + CU_futuras)
```

`LRC_GMM = BEL_servicio_futuro + RA_LRC + CSM` (o + LC si oneroso).

Ingreso por seguro GMM = siniestros esperados + gastos esperados + liberación RA + liberación CSM
+ asignación de IACF − componentes de inversión.

GMM exige insumos que PAA no: proyección de **primas futuras**, **caducidad/cancelación**, **siniestralidad
esperada**, **unidades de cobertura**, curvas **locked-in por cohorte** y, para grupos existentes a la fecha
de transición, un **método de transición** (retroactivo completo, retroactivo modificado o valor razonable).

### 2.5 Ajuste por riesgo no financiero (RA)

Opciones, de menor a mayor complejidad:

1. **Factor sobre BEL** (% por ramo) — probablemente lo que usa hoy la configuración de Addactis.
2. **Percentil / nivel de confianza** con Mack o bootstrap sobre triángulos.
3. **Costo de capital**.

Propuesta: empezar con (1) para replicar Addactis y dejar la interfaz preparada para (2).

### 2.6 Gastos — clasificación del factor de gastos

El factor de gastos de los contratos hay que **separarlo**, porque cada parte va a un sitio distinto:

| Tipo de gasto                         | Dónde entra                                   |
|---------------------------------------|-----------------------------------------------|
| Adquisición atribuible (IACF)         | LRC (reduce el pasivo, se amortiza / o gasto) |
| Mantenimiento / administración atribuible | FCF de LRC (GMM y test de onerosidad PAA)  |
| Gastos de liquidación (ULAE) atribuibles | LIC                                        |
| No atribuibles                        | Fuera de IFRS 17 (gasto del periodo)          |

### 2.7 Descuento

- Curva libre de riesgo + prima de iliquidez (*bottom-up*) o la curva que use la compañía en Addactis.
- Necesitamos: curva al corte, curvas históricas (para tasas locked-in por cohorte en GMM y para LIC con OCI),
  interpolación/extrapolación y conversión anual → mensual.

---

## 3. Qué necesitamos y qué no (por ahora)

### 3.1 Dentro del alcance

| Bloque | Prioridad | Comentario |
|---|---|---|
| Lectura y validación de insumos (CSV/XLSX) | Alta | Formatos acordes a lo que exporta Addactis |
| Calendario mensual y cortes arbitrarios | Alta | Corte en cualquier fin de mes |
| Curvas de descuento e interpolación | Alta | Base de LIC y GMM |
| LRC PAA + IACF + test de onerosidad | Alta | Validación directa contra Addactis |
| LIC (BEL descontado + RA) | Alta | Desde triángulos o desde BEL/patrón de Addactis |
| Tabla de movimientos LRC/LIC | Alta | Conciliación partida a partida |
| Reporte de conciliación vs Addactis | Alta | Diferencias absolutas/relativas por grupo |
| GMM (BEL, RA, CSM, unidades de cobertura, LC) | Media | Fase posterior, reutiliza todo lo anterior |
| Opción OCI (desagregación financiera) | Media | Depende de la política contable |

### 3.2 Fuera del alcance inicial (se puede añadir después)

- **VFA** (contratos con participación directa): solo aplica si hay productos con participación.
- **Reaseguro cedido** (párr. 60–70): misma mecánica que directo pero con signo y LC recovery; fase posterior.
- **Transición** GMM (MRA / FVA): solo necesaria si se va a medir GMM sobre cartera anterior a la transición.
- **Multimoneda**, contabilización (asientos) y revelaciones completas.
- Reservas de seguros de vida con modelos estocásticos.

---

## 4. Datos de entrada propuestos

Todos los montos en moneda del grupo, una fila por registro. Nombres provisionales, se ajustan a lo que
exporte Addactis.

| Archivo | Columnas mínimas | Uso |
|---|---|---|
| `grupos.csv` | id_grupo, portafolio, ramo, cohorte, clase_onerosidad, modelo (PAA/GMM), moneda, opcion_oci | Definición de grupos |
| `primas.csv` | id_grupo (o póliza), fecha_emision, inicio_vigencia, fin_vigencia, prima_emitida, prima_recaudada, fecha_recaudo, cancelaciones | Devengo LRC |
| `gastos_supuestos.csv` | ramo/grupo, factor_iacf, factor_mantenimiento, factor_ulae, factor_no_atribuible, politica_iacf (diferir/gasto) | Gastos |
| `siniestros_pagos.csv` | id_grupo, fecha_ocurrencia, fecha_aviso, fecha_pago, monto | Triángulos y pagos del periodo |
| `siniestros_reservas.csv` | id_grupo, fecha_corte, fecha_ocurrencia, reserva_avisados | RBNS |
| `patrones_pago.csv` *(opcional)* | ramo, desarrollo (meses), % acumulado | Si se toma el patrón de Addactis |
| `siniestralidad_esperada.csv` | ramo/cohorte, loss_ratio | Onerosidad PAA y GMM |
| `curvas.csv` | fecha_curva, moneda, plazo_meses, tasa | Descuento |
| `ra_supuestos.csv` | ramo, metodo, parametro (factor o percentil) | RA |
| `saldos_iniciales.csv` *(opcional)* | id_grupo, fecha, LRC, LIC, CSM, LC, IACF_activo | Arrancar desde un cierre previo |
| `addactis_resultados.csv` | id_grupo, fecha_corte, partida, valor | Conciliación |
| *GMM:* `caducidad.csv`, `unidades_cobertura.csv`, `primas_futuras.csv` | — | Solo para GMM |

**Dos modos de ejecución** para "saldo de cierre al corte que necesite":

1. **Desde el origen**: se reconstruye todo el histórico de cada grupo hasta el corte (no necesita saldos previos).
2. **Desde un saldo inicial**: se parte del cierre anterior (propio o de Addactis) y se corre solo el periodo.
   Útil para aislar diferencias en un solo trimestre.

---

## 5. Arquitectura propuesta en Julia

### 5.1 Estructura del paquete

```
IFRS17Engine/
├── Project.toml                 # dependencias
├── config/
│   └── ejemplo.toml             # rutas de insumos, fecha de corte, políticas contables
├── src/
│   ├── IFRS17Engine.jl          # módulo principal, exports
│   ├── tipos.jl                 # Grupo, Supuestos, Curva, ResultadoLRC, ResultadoLIC, Movimientos
│   ├── calendario.jl            # rejilla mensual, cortes, fracciones devengadas
│   ├── datos/
│   │   ├── lectura.jl           # CSV/XLSX → DataFrames
│   │   └── validacion.jl        # chequeos de calidad (fechas, signos, nulos, duplicados)
│   ├── supuestos/
│   │   ├── curvas.jl            # interpolación, factores de descuento, forwards, locked-in
│   │   ├── patrones.jl          # chain ladder, patrón de pagos
│   │   ├── gastos.jl            # separación del factor de gastos
│   │   └── ajuste_riesgo.jl     # RA: factor, percentil (Mack), CoC
│   ├── flujos/
│   │   └── proyeccion.jl        # flujos esperados por grupo y mes
│   ├── medicion/
│   │   ├── paa.jl               # LRC PAA, IACF, devengo
│   │   ├── onerosidad.jl        # test y componente de pérdida
│   │   ├── lic.jl               # LIC: BEL descontado + RA
│   │   ├── gmm.jl               # BEL LRC, RA, CSM
│   │   └── csm.jl               # unidades de cobertura, acreción, liberación
│   ├── movimientos.jl           # roll-forward / tablas párr. 100–105
│   └── reportes/
│       ├── salida.jl            # CSV/XLSX de resultados
│       └── conciliacion.jl      # comparación contra Addactis
├── test/
│   ├── runtests.jl
│   └── casos/                   # casos pequeños calculados a mano / en Excel
└── data/ejemplo/                # datos sintéticos para pruebas
```

### 5.2 Decisiones de diseño

- **Despacho múltiple** sobre el modelo: `abstract type Modelo end; struct PAA <: Modelo; struct GMM <: Modelo`,
  y `medir_lrc(::PAA, grupo, supuestos, corte)` / `medir_lrc(::GMM, ...)`. LIC es común a ambos.
- **Rejilla mensual** como base temporal; los flujos de cada grupo son `Vector{Float64}` indexados por mes,
  y los de toda la cartera una matriz `grupos × meses` (memoria contigua, muy rápido).
- **Funciones puras**: insumos → resultados, sin estado global. El estado entre cierres (CSM, LC, tasas locked-in,
  IACF por amortizar) se guarda explícitamente en un `struct EstadoGrupo`, que es lo que se persiste.
- **Tipos concretos y estables** (sin `Any`), para que el compilador genere código nativo eficiente.
- **Paralelismo por grupo** con `Threads.@threads` (los grupos son independientes).
- **Trazabilidad**: cada resultado guarda sus componentes (prima, IACF, LC, BEL, RA, CSM, intereses…)
  para conciliar partida a partida, no solo totales.
- **Configuración en TOML**: fecha de corte, políticas (IACF diferido o gasto, opción OCI, descontar LIC
  en PAA sí/no, base prima emitida/recaudada), rutas de archivos.

### 5.3 Dependencias previstas

`DataFrames`, `CSV`, `XLSX`, `Dates` (estándar), `TOML` (estándar), `Test` (estándar),
`BenchmarkTools` (rendimiento) y, solo para RA por percentil, `Distributions`.
Se evita depender de paquetes grandes para mantener el motor auditable.

---

## 6. Hoja de ruta por fases

| Fase | Entregable | Validación |
|---|---|---|
| **0** | Este documento + definición de formatos con datos reales de Addactis | Acordar insumos |
| **1** | Esqueleto del paquete, tipos, calendario, curvas y descuento, lectura/validación de datos | Tests unitarios (factores de descuento, fracciones devengadas) |
| **2** | **LRC PAA**: devengo, IACF, test de onerosidad y LC, movimientos | Conciliación vs Addactis por grupo y partida |
| **3** | **LIC**: patrones/chain ladder (o BEL Addactis), descuento, RA, unwinding, movimientos | Conciliación vs Addactis |
| **4** | Estado de resultados IFRS 17 (ingreso, gasto de servicio, resultado financiero) y reportes | Conciliación vs Addactis |
| **5** | **GMM**: proyección de primas futuras, BEL LRC, RA, CSM, unidades de cobertura, LC | Casos de prueba manuales + análisis de sensibilidad |
| **6** | Opcionales: opción OCI, reaseguro cedido, transición, multimoneda | — |

Cada fase termina con tests automatizados y un reporte de diferencias contra Addactis.

---

## 7. Preguntas abiertas (para avanzar a la fase 1)

1. **Exportes de Addactis**: ¿qué tablas de insumos y resultados puedes exportar (y a qué nivel: póliza,
   grupo, ramo)? Ideal: insumos + tabla de movimientos de un corte cerrado para usarlo como caso de prueba.
2. **Granularidad de primas**: ¿por póliza con vigencias, o ya agregadas por grupo/mes?
3. **Base del LRC**: ¿prima emitida o recaudada? ¿cómo trata Addactis las cuentas por cobrar?
4. **IACF**: ¿se difieren y amortizan, o se llevan a gasto (opción PAA para cobertura ≤ 1 año)?
5. **Factor de gastos**: ¿viene separado en adquisición / administración / liquidación / no atribuible?
6. **LIC**: ¿calculamos el BEL desde triángulos o tomamos el BEL nominal / patrón de pagos de Addactis?
   ¿Se descuenta el LIC en PAA?
7. **Curva de descuento**: fuente y metodología (¿bottom-up con prima de iliquidez?), periodicidad.
8. **RA**: método y parámetros actuales (factor por ramo, percentil, CoC).
9. **Opción OCI**: ¿se usa para separar el efecto de tasas?
10. **Onerosidad**: ¿cómo se identifica hoy y qué siniestralidad esperada se usa?
11. **GMM**: ¿para qué productos? ¿se necesitaría transición sobre cartera existente?
12. **Reaseguro**: ¿entra en esta primera versión?
13. **Frecuencia de cierre** (mensual / trimestral) y moneda(s).
