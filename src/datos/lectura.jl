# Lectura de insumos CSV según el esquema. Todo se lee como texto y se convierte columna a columna,
# para poder reportar exactamente qué fila y qué valor no se pudo interpretar.

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

_vacio(s) = s === missing || isempty(strip(s))

function _convertir(::Type{Date}, s::AbstractString, ::Char)
    tryparse(Date, strip(s), FORMATO_FECHA)
end
function _convertir(::Type{Float64}, s::AbstractString, dec::Char)
    t = replace(strip(s), " " => "")
    dec == ',' && (t = replace(t, "." => "", "," => "."))
    tryparse(Float64, t)
end
_convertir(::Type{Int}, s::AbstractString, ::Char) = tryparse(Int, strip(s))
_convertir(::Type{String}, s::AbstractString, ::Char) = String(strip(s))

"""
    leer_tabla(ruta, tabla; decimal='.') -> (DataFrame, Vector{Incidencia})

Devuelve un DataFrame con las columnas del esquema tipadas (`Union{Missing,T}`).
Las columnas opcionales ausentes se crean vacías.
"""
function leer_tabla(ruta::AbstractString, tabla::Tabla; decimal::Char = '.')
    inc = Incidencia[]
    crudo = CSV.read(ruta, DataFrame; types = String, stringtype = String, strict = false,
                     silencewarnings = true, normalizenames = false)
    rename!(crudo, [strip(lowercase(String(n))) for n in names(crudo)])
    n = nrow(crudo)
    df = DataFrame()
    for c in tabla.columnas
        if !(c.nombre in names(crudo))
            c.obligatoria && push!(inc, Incidencia(:error, tabla.nombre, 0, "falta la columna obligatoria '$(c.nombre)'"))
            df[!, c.nombre] = Vector{Union{Missing,c.tipo}}(missing, n)
            continue
        end
        destino = Vector{Union{Missing,c.tipo}}(missing, n)
        for (i, s) in enumerate(crudo[!, c.nombre])
            _vacio(s) && continue
            v = _convertir(c.tipo, s, decimal)
            if v === nothing
                push!(inc, Incidencia(:error, tabla.nombre, i, "valor '$s' no válido en '$(c.nombre)' (se esperaba $(c.tipo))"))
            else
                destino[i] = v
            end
        end
        df[!, c.nombre] = destino
    end
    extras = setdiff(names(crudo), [c.nombre for c in tabla.columnas])
    isempty(extras) || push!(inc, Incidencia(:advertencia, tabla.nombre, 0, "columnas ignoradas: $(join(extras, ", "))"))
    return df, inc
end

"""
    leer_tablas(carpeta; decimal='.') -> (Dict{String,DataFrame}, Vector{Incidencia})

Lee todas las tablas del esquema desde `carpeta/<tabla>.csv`. Las opcionales ausentes quedan vacías.
"""
function leer_tablas(carpeta::AbstractString; decimal::Char = '.')
    tablas = Dict{String,DataFrame}()
    inc = Incidencia[]
    for t in ESQUEMA
        ruta = joinpath(carpeta, t.nombre * ".csv")
        if isfile(ruta)
            df, i = leer_tabla(ruta, t; decimal)
            tablas[t.nombre] = df
            append!(inc, i)
        else
            t.obligatoria && push!(inc, Incidencia(:error, t.nombre, 0, "no se encontró el archivo $ruta"))
            tablas[t.nombre] = DataFrame([c.nombre => Vector{Union{Missing,c.tipo}}() for c in t.columnas])
        end
    end
    return tablas, inc
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
    tablas, inc = leer_tablas(cfg.carpeta_datos; decimal = cfg.separador_decimal)
    append!(inc, validar(tablas, cfg; previas = inc))
    hay_errores(inc) && error("Insumos con errores:\n" * resumen_incidencias(inc))
    return construir_insumos(tablas, inc)
end
