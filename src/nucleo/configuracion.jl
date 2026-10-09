# Configuración de la corrida: fecha de corte, políticas contables y umbrales.
# Se lee de la hoja `configuracion` del Excel de insumos (forma recomendada) o de un archivo TOML.

"""
Configuración de una corrida.

- `origen`: archivo Excel de insumos, o carpeta con un CSV por tabla.
- `umbral_oneroso`: ratio combinado por encima del cual el conjunto es oneroso (normalmente 1.0).
- `umbral_sin_riesgo`: ratio combinado hasta el cual se considera que no hay posibilidad significativa
  de volverse oneroso (párr. 16(b), 19). Entre ambos umbrales queda la clase `RESTANTE`.
"""
struct Configuracion
    fecha_corte::Date
    moneda::String
    origen::String
    carpeta_salidas::String
    separador_decimal::Char
    politica_iacf::PoliticaIACF
    base_devengo::Symbol
    descontar_lrc::Bool
    umbral_oneroso::Float64
    umbral_sin_riesgo::Float64
end

"Parámetros de la hoja `configuracion`: (nombre, valor por defecto, descripción)."
const PARAMETROS = [
    ("fecha_corte", Date(2024, 12, 31), "Fecha de cierre a calcular. Debe ser fin de mes (aaaa-mm-dd)."),
    ("moneda", "COP", "Moneda de los montos."),
    ("politica_iacf", "DIFERIR", "Gastos de adquisición: DIFERIR (se amortizan con el devengo) o GASTO (al emitir)."),
    ("devengo", "DIARIO", "Devengo de la prima: DIARIO o MENSUAL."),
    ("descontar_lrc", "NO", "Descontar el LRC (componente financiero): SI o NO."),
    ("umbral_oneroso", 1.0, "Ratio combinado por encima del cual un conjunto es ONEROSO."),
    ("umbral_sin_riesgo_significativo", 0.90, "Ratio combinado hasta el cual el conjunto es SIN_RIESGO_SIGNIFICATIVO."),
]

_texto(v) = uppercase(strip(string(v)))
_fecha(v) = v isa Date ? v : v isa DateTime ? Date(v) : Date(strip(string(v)))
_booleano(v) = v isa Bool ? v : _texto(v) in ("SI", "SÍ", "TRUE", "1", "S", "YES")
_numero(v) = v isa Real ? Float64(v) : parse(Float64, replace(strip(string(v)), "," => "."))

function _politica_iacf(v)
    s = _texto(v)
    s == "DIFERIR" && return IACF_DIFERIR
    s == "GASTO" && return IACF_GASTO
    throw(ArgumentError("politica_iacf debe ser DIFERIR o GASTO, no '$s'"))
end

"Construye la configuración a partir de un diccionario plano de parámetros."
function _configuracion(d::AbstractDict, origen::AbstractString, salidas::AbstractString)
    val(k) = get(d, k, nothing) === nothing ? first(p[2] for p in PARAMETROS if p[1] == k) : d[k]
    fecha_corte = _fecha(val("fecha_corte"))
    fecha_corte == fin_de_mes(fecha_corte) ||
        throw(ArgumentError("fecha_corte debe ser fin de mes: $fecha_corte"))
    devengo = Symbol(lowercase(_texto(val("devengo"))))
    devengo in (:diario, :mensual) || throw(ArgumentError("devengo debe ser DIARIO o MENSUAL"))
    u_on, u_sr = _numero(val("umbral_oneroso")), _numero(val("umbral_sin_riesgo_significativo"))
    u_sr <= u_on || throw(ArgumentError("umbral_sin_riesgo_significativo debe ser <= umbral_oneroso"))
    dec = string(get(d, "separador_decimal", "."))
    length(dec) == 1 || throw(ArgumentError("separador_decimal debe ser un carácter"))
    return Configuracion(fecha_corte, strip(string(val("moneda"))), origen, salidas, dec[1],
                         _politica_iacf(val("politica_iacf")), devengo, _booleano(val("descontar_lrc")), u_on, u_sr)
end

"""
    cargar_configuracion(ruta) -> Configuracion

- `ruta` = Excel de insumos (`.xlsx`): lee la hoja `configuracion`; los resultados se escriben en la
  carpeta `resultados` junto al Excel.
- `ruta` = archivo `.toml`: formato avanzado (ver `datos/ejemplo/configuracion.toml`).
"""
function cargar_configuracion(ruta::AbstractString)
    isfile(ruta) || throw(ArgumentError("no existe el archivo $ruta"))
    base = dirname(abspath(ruta))
    if endswith(lowercase(ruta), ".xlsx")
        d = leer_parametros_excel(ruta)
        return _configuracion(d, abspath(ruta), joinpath(base, "resultados"))
    end
    cfg = TOML.parsefile(ruta)
    plano = Dict{String,Any}()
    for (_, sec) in cfg, (k, v) in sec
        plano[k == "iacf" ? "politica_iacf" : k] = v
    end
    resolver(p) = isabspath(p) ? p : normpath(joinpath(base, p))
    return _configuracion(plano, resolver(get(plano, "carpeta", ".")), resolver(get(plano, "carpeta_salidas", "resultados")))
end
