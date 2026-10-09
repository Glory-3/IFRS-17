# Lectura de insumos desde el Excel de insumos (una hoja por tabla) o desde CSV.
# Cada celda se convierte al tipo del esquema y se reporta exactamente qué fila y valor no se pudo interpretar.

const FORMATO_FECHA = dateformat"yyyy-mm-dd"

"Insumos ya validados y convertidos a tipos de dominio."
struct Insumos
    contratos::Vector{Contrato}
    primas::Vector{MovimientoPrima}
    portafolios::Dict{String,Portafolio}
    supuestos_siniestralidad::DataFrame
    supuestos_gastos::DataFrame
    patron_pagos::DataFrame
    curvas::DataFrame
    clasificacion_previa::Dict{String,ClaseOnerosidad}
    incidencias::Vector{Incidencia}
end

_vacio(v) = v === missing || v === nothing || (v isa AbstractString && isempty(strip(v)))

# Conversión desde texto (CSV) ...
_convertir(::Type{Date}, s::AbstractString, ::Char) = tryparse(Date, strip(s), FORMATO_FECHA)
function _convertir(::Type{Float64}, s::AbstractString, dec::Char)
    t = replace(strip(s), " " => "")
    dec == ',' && (t = replace(t, "." => "", "," => "."))
    tryparse(Float64, t)
end
_convertir(::Type{Int}, s::AbstractString, ::Char) = tryparse(Int, strip(s))
_convertir(::Type{String}, s::AbstractString, ::Char) = String(strip(s))
# ... y desde celdas de Excel ya tipadas
_convertir(::Type{Date}, v::Date, ::Char) = v
_convertir(::Type{Date}, v::DateTime, ::Char) = Date(v)
_convertir(::Type{Date}, v::Real, ::Char) = Date(1899, 12, 30) + Day(round(Int, v))   # número de serie Excel
_convertir(::Type{Float64}, v::Real, ::Char) = Float64(v)
_convertir(::Type{Int}, v::Real, ::Char) = isinteger(v) ? Int(v) : nothing
_convertir(::Type{String}, v::Real, ::Char) = isinteger(v) ? string(Int(v)) : string(v)
_convertir(::Type{String}, v, ::Char) = strip(string(v))
_convertir(::Type, v, ::Char) = nothing

"""
    tipar_tabla(crudo, tabla; decimal='.') -> (DataFrame, Vector{Incidencia})

Convierte columnas crudas (`Dict` nombre => vector de valores) al tipo del esquema.
Devuelve columnas `Union{Missing,T}`; las opcionales ausentes se crean vacías.
"""
function tipar_tabla(crudo::AbstractDict, n::Int, tabla::Tabla; decimal::Char = '.')
    inc = Incidencia[]
    df = DataFrame()
    for c in tabla.columnas
        if !haskey(crudo, c.nombre)
            c.obligatoria && push!(inc, Incidencia(:error, tabla.nombre, 0, "falta la columna obligatoria '$(c.nombre)'"))
            df[!, c.nombre] = Vector{Union{Missing,c.tipo}}(missing, n)
            continue
        end
        destino = Vector{Union{Missing,c.tipo}}(missing, n)
        for (i, v) in enumerate(crudo[c.nombre])
            _vacio(v) && continue
            x = _convertir(c.tipo, v, decimal)
            if x === nothing
                push!(inc, Incidencia(:error, tabla.nombre, i, "valor '$v' no válido en '$(c.nombre)' (se esperaba $(_nombre_tipo(c.tipo)))"))
            else
                destino[i] = x
            end
        end
        df[!, c.nombre] = destino
    end
    extras = setdiff(keys(crudo), [c.nombre for c in tabla.columnas])
    isempty(extras) || push!(inc, Incidencia(:advertencia, tabla.nombre, 0, "columnas ignoradas: $(join(sort!(collect(extras)), ", "))"))
    return df, inc
end

_nombre_tipo(T) = T === Date ? "fecha aaaa-mm-dd" : T === Float64 ? "número" : T === Int ? "entero" : "texto"
_normalizar(n) = lowercase(strip(string(n)))

"Lee un CSV de una tabla del esquema."
function leer_tabla(ruta::AbstractString, tabla::Tabla; decimal::Char = '.')
    crudo = CSV.read(ruta, DataFrame; types = String, stringtype = String, strict = false,
                     silencewarnings = true, normalizenames = false)
    cols = Dict(_normalizar(n) => crudo[!, n] for n in names(crudo))
    return tipar_tabla(cols, nrow(crudo), tabla; decimal)
end

"Lee una hoja de Excel: fila 1 = encabezados, datos desde la fila 2. Ignora filas totalmente vacías."
function leer_hoja(xf, nombre::AbstractString, tabla::Tabla)
    datos = XLSX.getdata(xf[nombre])
    datos isa AbstractMatrix || (datos = reshape([datos], 1, 1))
    encabezados = [_vacio(h) ? "" : _normalizar(h) for h in datos[1, :]]
    filas = [i for i in 2:size(datos, 1) if any(!_vacio, datos[i, :])]
    cols = Dict(h => Any[datos[i, j] for i in filas] for (j, h) in enumerate(encabezados) if !isempty(h))
    return tipar_tabla(cols, length(filas), tabla)
end

"""
    leer_tablas(origen; decimal='.') -> (Dict{String,DataFrame}, Vector{Incidencia})

`origen` es el Excel de insumos (una hoja por tabla) o una carpeta con `<tabla>.csv`.
Las tablas opcionales ausentes quedan vacías.
"""
function leer_tablas(origen::AbstractString; decimal::Char = '.')
    es_excel = isfile(origen) && endswith(lowercase(origen), ".xlsx")
    xf = es_excel ? XLSX.readxlsx(origen) : nothing
    hojas = es_excel ? Dict(_normalizar(h) => h for h in XLSX.sheetnames(xf)) : Dict{String,String}()
    tablas = Dict{String,DataFrame}()
    inc = Incidencia[]
    for t in ESQUEMA
        ruta = joinpath(origen, t.nombre * ".csv")
        df, i = if es_excel && haskey(hojas, t.nombre)
            leer_hoja(xf, hojas[t.nombre], t)
        elseif !es_excel && isfile(ruta)
            leer_tabla(ruta, t; decimal)
        else
            t.obligatoria && push!(inc, Incidencia(:error, t.nombre, 0,
                es_excel ? "falta la hoja '$(t.nombre)' en el Excel" : "no se encontró el archivo $ruta"))
            DataFrame([c.nombre => Vector{Union{Missing,c.tipo}}() for c in t.columnas]), Incidencia[]
        end
        tablas[t.nombre] = df
        append!(inc, i)
    end
    return tablas, inc
end

"Lee la hoja `configuracion` (columnas parametro, valor) del Excel de insumos."
function leer_parametros_excel(ruta::AbstractString)
    xf = XLSX.readxlsx(ruta)
    hojas = Dict(_normalizar(h) => h for h in XLSX.sheetnames(xf))
    haskey(hojas, "configuracion") || throw(ArgumentError("el Excel no tiene la hoja 'configuracion'"))
    datos = XLSX.getdata(xf[hojas["configuracion"]])
    d = Dict{String,Any}()
    for i in 2:size(datos, 1)
        _vacio(datos[i, 1]) || _vacio(datos[i, 2]) || (d[_normalizar(datos[i, 1])] = datos[i, 2])
    end
    return d
end

function _clase_desde_texto(s::AbstractString)
    s == "ONEROSO" && return ONEROSO
    s == "SIN_RIESGO_SIGNIFICATIVO" && return SIN_RIESGO_SIGNIFICATIVO
    s == "RESTANTE" && return RESTANTE
    throw(ArgumentError("clase de onerosidad desconocida: $s"))
end

"Convierte tablas ya validadas en tipos de dominio."
function construir_insumos(tablas::Dict{String,DataFrame}, inc::Vector{Incidencia})
    tc = tablas["contratos"]
    contratos = [Contrato(r.contrato_id, r.portafolio_id, coalesce(r.producto, ""), r.fecha_emision,
                          r.inicio_cobertura, r.fin_cobertura, coalesce(r.fecha_primer_pago, r.fecha_emision))
                 for r in eachrow(tc)]
    por_id = Dict(c.id => c for c in contratos)
    primas = [begin
                  c = por_id[r.contrato_id]
                  MovimientoPrima(r.contrato_id, r.fecha_contable, r.tipo_movimiento, r.monto,
                                  coalesce(r.inicio_cobertura, c.inicio_cobertura),
                                  coalesce(r.fin_cobertura, c.fin_cobertura))
              end for r in eachrow(tablas["primas"])]
    portafolios = Dict(r.portafolio_id => Portafolio(r.portafolio_id, coalesce(r.descripcion, ""),
                                                     r.modelo_medicion == "GMM" ? GMM : PAA,
                                                     coalesce(r.curva_id, ""))
                       for r in eachrow(tablas["portafolios"]))
    previa = Dict(r.contrato_id => _clase_desde_texto(r.clase_onerosidad)
                  for r in eachrow(tablas["clasificacion_previa"]) if haskey(por_id, r.contrato_id))
    return Insumos(contratos, primas, portafolios, tablas["supuestos_siniestralidad"],
                   tablas["supuestos_gastos"], tablas["patron_pagos"], tablas["curvas"], previa, inc)
end

"""
    cargar_insumos(cfg::Configuracion) -> Insumos

Lee, valida y convierte. Lanza un error con el resumen si la validación encuentra errores;
las advertencias quedan en `insumos.incidencias`.
"""
function cargar_insumos(cfg::Configuracion)
    tablas, inc = leer_tablas(cfg.origen; decimal = cfg.separador_decimal)
    append!(inc, validar(tablas, cfg; previas = inc))
    hay_errores(inc) && error("Insumos con errores:\n" * resumen_incidencias(inc))
    return construir_insumos(tablas, inc)
end
