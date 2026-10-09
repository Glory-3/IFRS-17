# Paso 2 — Reconocimiento, agrupación y test de onerosidad inicial

Código: `src/agrupacion/agrupacion.jl`, `src/agrupacion/onerosidad.jl`.

## 1. Fecha de reconocimiento (párr. 25)

Un contrato se reconoce en la fecha más temprana entre:

- (a) el inicio de su periodo de cobertura (`inicio_cobertura`);
- (b) la fecha en que vence el primer pago del tomador (`fecha_primer_pago`; si no se informa se usa
  `fecha_emision`, coherente con una base de prima emitida);
- (c) la fecha en que un grupo oneroso se vuelve oneroso, que para contratos ya emitidos no es posterior a (a) ni a (b).

Consecuencia práctica: una póliza emitida el 20-dic-2023 con vigencia desde el 1-ene-2024 pertenece a la
**cohorte 2023**. Si la compañía prefiere informar vencimientos de pago reales, basta con llenar `fecha_primer_pago`.

## 2. Cohorte (párr. 22)

Cohorte = año calendario de la fecha de reconocimiento. Un grupo no puede mezclar contratos emitidos con
más de un año de diferencia.

## 3. Test de onerosidad inicial

### Nivel de evaluación
Se evalúan **conjuntos** portafolio × cohorte × producto (párr. 17 permite evaluar conjuntos cuando hay
información razonable y sustentable de que todos los contratos del conjunto están en el mismo grupo).
Si se requiere más granularidad, basta con informar supuestos a nivel de `producto` (o refinar productos).

### Fórmula (PAA)
Bajo PAA, en el reconocimiento inicial:

```
LRC_0 = P − IACF          (política IACF = DIFERIR)
LRC_0 = P                 (política IACF = GASTO, párr. 59(a))
FCF_0 = siniestros esperados + RA + gastos de mantenimiento atribuibles
```

El conjunto es oneroso si `FCF_0 > LRC_0` (párr. 57–58). Dividiendo por la prima `P`:

```
ratio = SIN × (1 + RA%) + MANT [+ ADQ si DIFERIR]
```

| Ratio | Clase (párr. 16) |
|---|---|
| `ratio > umbral_oneroso` (1.0) | `ONEROSO` — componente de pérdida inicial = `FCF_0 − LRC_0` |
| `ratio ≤ umbral_sin_riesgo_significativo` (0.90) | `SIN_RIESGO_SIGNIFICATIVO` |
| en medio | `RESTANTE` |

- Los gastos `NO_ATRIBUIBLE` no entran (B66(d)).
- El umbral de "sin posibilidad significativa" es un juicio de la compañía (párr. 19); se deja configurable
  y debe documentarse en la política contable.
- Bajo PAA el párr. 18 permite suponer que no hay onerosos salvo que hechos y circunstancias indiquen lo
  contrario; aquí el test se calcula siempre, lo que sirve como evidencia de esos hechos y circunstancias.

### Supuestos
Se buscan con esta prioridad: (portafolio, cohorte, producto) → (portafolio, cohorte, todos) →
(portafolio, 0, producto) → (portafolio, 0, todos). `cohorte = 0` significa "todas las cohortes".
En gastos se toma **el conjunto de filas** de la clave más específica que exista.

### Simplificaciones actuales (se levantan en pasos siguientes)
- Flujos sin descontar (válido para coberturas ≤ 1 año; el descuento llega en el paso 4).
- El portafolio GMM se evalúa con la misma fórmula; el test GMM completo (primas futuras y flujos
  descontados, párr. 47) llega en el paso 6.

## 4. Formación de grupos y persistencia (párr. 24)

Grupo = portafolio × cohorte × clase. Los grupos se fijan en el reconocimiento inicial y **no se
reevalúan**. Por eso el Excel de resultados trae la hoja `clasificacion_contratos`; en el siguiente corte se
copia en la hoja `clasificacion_previa` del Excel de insumos y los contratos allí listados conservan su clase, aunque
los supuestos hayan cambiado. Solo los contratos nuevos se clasifican con los supuestos vigentes.

Los supuestos del grupo (para la medición posterior) son el promedio ponderado por prima de los conjuntos
que lo forman.
