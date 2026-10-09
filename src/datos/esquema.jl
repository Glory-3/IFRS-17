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
    diccionario_datos() -> String

Diccionario de datos en Markdown, generado desde el esquema.
"""
function diccionario_datos()
    io = IOBuffer()
    println(io, "# Diccionario de datos\n")
    println(io, "Generado automáticamente desde `src/datos/esquema.jl`. Cada tabla es una hoja del Excel de ",
        "insumos (fila 1 = encabezados exactamente como aquí). Fechas como fecha de Excel o texto `aaaa-mm-dd`; ",
        "tasas y factores como fracción (0.12 = 12%).\n")
    for t in ESQUEMA
        println(io, "## Hoja `", t.nombre, "`", t.obligatoria ? "" : " *(opcional)*", "\n")
        println(io, t.descripcion, "\n")
        println(io, "| Columna | Tipo | Obligatoria | Descripción | Valores |")
        println(io, "|---|---|---|---|---|")
        for c in t.columnas
            println(io, "| `", c.nombre, "` | ", _nombre_tipo(c.tipo), " | ", c.obligatoria ? "sí" : "no", " | ",
                c.descripcion, " | ", join(c.valores, ", "), " |")
        end
        println(io)
    end
    return String(take!(io))
end

"""
    generar_plantilla(ruta; datos=Dict(), parametros=Dict())

Escribe el Excel de insumos: hoja INSTRUCCIONES, hoja `configuracion` y una hoja por tabla del esquema.
Si se pasan `datos` (nombre de tabla => DataFrame) se llenan esas hojas (se usa para el ejemplo).
"""
function generar_plantilla(ruta::AbstractString; datos::AbstractDict = Dict{String,DataFrame}(),
                           parametros::AbstractDict = Dict{String,Any}())
    mkpath(dirname(abspath(ruta)))
    instrucciones = String[
        "MOTOR IFRS 17 - EXCEL DE INSUMOS",
        "",
        "CÓMO USARLO",
        "1. Llene la hoja 'configuracion' (fecha de corte y políticas).",
        "2. Llene cada hoja de datos desde la fila 2. NO cambie los nombres de las hojas ni de los encabezados (fila 1).",
        "3. Guarde el archivo y arrástrelo sobre EJECUTAR.bat (Windows) o ejecute: julia --project=. scripts/ejecutar.jl <archivo.xlsx>",
        "4. Los resultados quedan en la carpeta 'resultados', junto a este archivo.",
        "",
        "REGLAS",
        "- Fechas: formato fecha de Excel (o texto aaaa-mm-dd).",
        "- Tasas, factores y porcentajes: como fracción (0.12 = 12%), o con formato % de Excel.",
        "- Montos: número sin símbolos. Devoluciones y cancelaciones en negativo.",
        "- Hojas marcadas (opcional) pueden quedar solo con encabezados.",
        "",
        "HOJAS Y COLUMNAS",
    ]
    for t in ESQUEMA
        push!(instrucciones, "")
        push!(instrucciones, uppercase(t.nombre) * (t.obligatoria ? "" : "  (opcional)") * " - " * t.descripcion)
        for c in t.columnas
            push!(instrucciones, string("   ", rpad(c.nombre, 26), rpad(_nombre_tipo(c.tipo), 18),
                c.obligatoria ? "obligatoria   " : "opcional      ", c.descripcion,
                isempty(c.valores) ? "" : "  [" * join(c.valores, " / ") * "]"))
        end
    end
    isfile(ruta) && rm(ruta)
    XLSX.openxlsx(ruta, mode = "w") do xf
        hoja = xf[1]
        XLSX.rename!(hoja, "INSTRUCCIONES")
        for (i, l) in enumerate(instrucciones)
            hoja[i, 1] = l
        end
        cfg = XLSX.addsheet!(xf, "configuracion")
        cfg[1, 1], cfg[1, 2], cfg[1, 3] = "parametro", "valor", "descripcion"
        for (i, (k, v, d)) in enumerate(PARAMETROS)
            cfg[i + 1, 1], cfg[i + 1, 2], cfg[i + 1, 3] = k, get(parametros, k, v), d
        end
        for t in ESQUEMA
            h = XLSX.addsheet!(xf, t.nombre)
            df = get(datos, t.nombre, nothing)
            escribir_tabla!(h, df === nothing ? DataFrame([c.nombre => Any[] for c in t.columnas]) :
                               select(df, intersect([c.nombre for c in t.columnas], names(df))))
        end
    end
    return ruta
end

"Escribe un DataFrame en una hoja (encabezados en negrilla en la fila 1). Las celdas `missing` quedan vacías."
function escribir_tabla!(hoja, df::DataFrame)
    n = nrow(df)
    for (j, nombre) in enumerate(names(df))
        hoja[1, j] = nombre
        col = df[!, nombre]
        for i in eachindex(col)
            v = col[i]
            (v === missing || v === nothing) && continue
            hoja[i + 1, j] = v isa AbstractString ? String(v) : v
        end
        XLSX.setColumnWidth(hoja, j; width = max(12, length(nombre) + 2))
        n == 0 && continue
        T = nonmissingtype(eltype(col))
        rango = XLSX.CellRange(XLSX.CellRef(2, j), XLSX.CellRef(n + 1, j))
        if T <: Date
            XLSX.setFormat(hoja, rango; format = "yyyy-mm-dd")
        elseif T <: AbstractFloat
            XLSX.setFormat(hoja, rango; format = "#,##0.00##")
        end
    end
    isempty(names(df)) || XLSX.setFont(hoja, XLSX.CellRange(XLSX.CellRef(1, 1), XLSX.CellRef(1, ncol(df))); bold = true)
end
