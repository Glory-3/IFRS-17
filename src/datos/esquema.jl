# Esquema de insumos: única fuente de verdad para lectura, validación, plantillas y documentación.

"Definición de una columna de insumo."
struct Columna
    nombre::String
    tipo::DataType            # String, Date, Float64 o Int
    obligatoria::Bool
    descripcion::String
    valores::Vector{String}   # valores permitidos (vacío = libre)
end
Columna(n, t, o, d) = Columna(n, t, o, d, String[])

"Definición de una tabla de insumo (un archivo CSV)."
struct Tabla
    nombre::String
    obligatoria::Bool
    descripcion::String
    columnas::Vector{Columna}
end

const ESQUEMA = Tabla[
    Tabla("contratos", true,
        "Un registro por contrato (póliza). Atributos que no cambian en el tiempo.",
        [Columna("contrato_id", String, true, "Identificador único del contrato."),
         Columna("portafolio_id", String, true, "Portafolio al que pertenece (debe existir en portafolios)."),
         Columna("producto", String, false, "Producto o ramo comercial (informativo)."),
         Columna("fecha_emision", Date, true, "Fecha de emisión del contrato."),
         Columna("inicio_cobertura", Date, true, "Inicio del periodo de cobertura."),
         Columna("fin_cobertura", Date, true, "Fin del periodo de cobertura (incluido)."),
         Columna("fecha_primer_pago", Date, false,
             "Vencimiento del primer pago del tomador (párr. 25(b)). Vacío = fecha_emision.")]),
    Tabla("primas", true,
        "Movimientos de prima emitida. Cancelaciones y devoluciones con monto negativo.",
        [Columna("contrato_id", String, true, "Contrato al que corresponde el movimiento."),
         Columna("fecha_contable", Date, true, "Fecha en que se registra la prima emitida."),
         Columna("tipo_movimiento", String, true, "Tipo de movimiento.",
             ["EMISION", "ENDOSO", "CANCELACION", "RENOVACION"]),
         Columna("monto", Float64, true, "Prima emitida del movimiento (negativa si es devolución)."),
         Columna("inicio_cobertura", Date, false, "Inicio de la cobertura de este movimiento. Vacío = la del contrato."),
         Columna("fin_cobertura", Date, false, "Fin de la cobertura de este movimiento. Vacío = la del contrato.")]),
    Tabla("portafolios", true,
        "Un registro por portafolio (párr. 14).",
        [Columna("portafolio_id", String, true, "Identificador del portafolio."),
         Columna("descripcion", String, false, "Descripción."),
         Columna("modelo_medicion", String, true, "Modelo de medición.", ["PAA", "GMM"]),
         Columna("curva_id", String, false, "Curva de descuento (tabla curvas).")]),
    Tabla("supuestos_siniestralidad", true,
        "Siniestralidad esperada y RA. Se busca primero (portafolio, cohorte, producto), luego sin producto, " *
        "luego cohorte 0 con producto y por último cohorte 0 sin producto.",
        [Columna("portafolio_id", String, true, "Portafolio."),
         Columna("cohorte", Int, true, "Año de la cohorte, o 0 para todas."),
         Columna("producto", String, false, "Producto al que aplica. Vacío = todos los productos del portafolio."),
         Columna("siniestralidad_esperada", Float64, true, "Siniestros esperados / prima (0.65 = 65%)."),
         Columna("ajuste_riesgo_pct", Float64, true, "RA como fracción de los siniestros esperados (0.05 = 5%).")]),
    Tabla("supuestos_gastos", true,
        "Factores de gasto sobre prima emitida, por concepto. Se usa el conjunto de filas de la clave más " *
        "específica que exista, con la misma prioridad que supuestos_siniestralidad.",
        [Columna("portafolio_id", String, true, "Portafolio."),
         Columna("cohorte", Int, true, "Año de la cohorte, o 0 para todas."),
         Columna("producto", String, false, "Producto al que aplica. Vacío = todos los productos del portafolio."),
         Columna("concepto", String, true, "Nombre del gasto (comisión, administración, ...)."),
         Columna("clasificacion", String, true, "Tratamiento IFRS 17.", ["ADQUISICION", "MANTENIMIENTO", "NO_ATRIBUIBLE"]),
         Columna("factor", Float64, true, "Fracción de la prima emitida (0.12 = 12%).")]),
    Tabla("patron_pagos", false,
        "Patrón de pago de siniestros por portafolio (para descontar flujos). Debe sumar 1.",
        [Columna("portafolio_id", String, true, "Portafolio."),
         Columna("mes_desarrollo", Int, true, "Meses desde la ocurrencia (0 = mismo mes)."),
         Columna("proporcion", Float64, true, "Proporción del siniestro pagada en ese mes.")]),
    Tabla("curvas", false,
        "Curvas de descuento. Tasa efectiva anual por plazo.",
        [Columna("curva_id", String, true, "Identificador de la curva."),
         Columna("fecha_curva", Date, true, "Fecha a la que corresponde la curva."),
         Columna("plazo_meses", Int, true, "Plazo en meses."),
         Columna("tasa_ea", Float64, true, "Tasa efectiva anual (0.095 = 9.5%).")]),
    Tabla("clasificacion_previa", false,
        "Clase de onerosidad asignada en corridas anteriores (salida clasificacion_contratos.csv). " *
        "Los contratos aquí listados conservan su grupo (párr. 24); solo se evalúan los nuevos.",
        [Columna("contrato_id", String, true, "Contrato."),
         Columna("clase_onerosidad", String, true, "Clase asignada en el reconocimiento inicial.",
             ["ONEROSO", "SIN_RIESGO_SIGNIFICATIVO", "RESTANTE"]),
         Columna("fecha_clasificacion", Date, false, "Fecha de corte en que se clasificó.")]),
]

tabla_esquema(nombre::AbstractString) = only(filter(t -> t.nombre == nombre, ESQUEMA))

"""
    generar_plantillas(carpeta)

Escribe un CSV vacío (solo encabezados) por tabla y un `LEEME.md` con el diccionario de datos.
"""
function generar_plantillas(carpeta::AbstractString)
    mkpath(carpeta)
    io_doc = IOBuffer()
    println(io_doc, "# Diccionario de datos de insumos\n")
    println(io_doc, "Generado automáticamente desde `src/datos/esquema.jl`. Un archivo CSV por tabla, ",
        "codificación UTF-8, fechas `aaaa-mm-dd`, tasas y factores como fracción.\n")
    for t in ESQUEMA
        open(joinpath(carpeta, t.nombre * ".csv"), "w") do io
            println(io, join((c.nombre for c in t.columnas), ","))
        end
        println(io_doc, "## `", t.nombre, ".csv`", t.obligatoria ? "" : " *(opcional)*", "\n")
        println(io_doc, t.descripcion, "\n")
        println(io_doc, "| Columna | Tipo | Obligatoria | Descripción | Valores |")
        println(io_doc, "|---|---|---|---|---|")
        for c in t.columnas
            tipo = c.tipo === Date ? "fecha" : c.tipo === Float64 ? "número" : c.tipo === Int ? "entero" : "texto"
            println(io_doc, "| `", c.nombre, "` | ", tipo, " | ", c.obligatoria ? "sí" : "no", " | ",
                c.descripcion, " | ", join(c.valores, ", "), " |")
        end
        println(io_doc)
    end
    write(joinpath(carpeta, "LEEME.md"), String(take!(io_doc)))
    return carpeta
end
