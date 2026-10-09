# Configuración de la corrida: fecha de corte, políticas contables y umbrales.
# Se lee de un archivo TOML (ver datos/ejemplo/configuracion.toml).

"""
Configuración de una corrida.

- `umbral_oneroso`: ratio combinado por encima del cual el conjunto es oneroso (normalmente 1.0).
- `umbral_sin_riesgo`: ratio combinado hasta el cual se considera que no hay posibilidad significativa
  de volverse oneroso (párr. 16(b), 19). Entre ambos umbrales queda la clase `RESTANTE`.
"""
struct Configuracion
    fecha_corte::Date
    moneda::String
    carpeta_datos::String
    carpeta_salidas::String
    separador_decimal::Char
    politica_iacf::PoliticaIACF
    base_devengo::Symbol
    descontar_lrc::Bool
    umbral_oneroso::Float64
    umbral_sin_riesgo::Float64
end

function _enum_desde_texto(::Type{PoliticaIACF}, s::AbstractString)
    s = uppercase(strip(s))
    s == "DIFERIR" && return IACF_DIFERIR
    s == "GASTO" && return IACF_GASTO
    throw(ArgumentError("politicas.iacf debe ser DIFERIR o GASTO, no '$s'"))
end

"""
    cargar_configuracion(ruta) -> Configuracion

Lee el TOML. Las carpetas relativas se resuelven respecto a la ubicación del archivo.
"""
function cargar_configuracion(ruta::AbstractString)
    cfg = TOML.parsefile(ruta)
    base = dirname(abspath(ruta))
    resolver(p) = isabspath(p) ? p : normpath(joinpath(base, p))
    sec(n) = get(cfg, n, Dict{String,Any}())
    corrida, datos, pol, oner = sec("corrida"), sec("datos"), sec("politicas"), sec("onerosidad")

    fc = corrida["fecha_corte"]
    fecha_corte = fc isa Date ? fc : Date(string(fc))
    fecha_corte == fin_de_mes(fecha_corte) ||
        throw(ArgumentError("corrida.fecha_corte debe ser fin de mes: $fecha_corte"))

    dec = string(get(datos, "separador_decimal", "."))
    length(dec) == 1 || throw(ArgumentError("datos.separador_decimal debe ser un carácter"))

    devengo = Symbol(lowercase(get(pol, "devengo", "diario")))
    devengo in (:diario, :mensual) || throw(ArgumentError("politicas.devengo debe ser DIARIO o MENSUAL"))

    u_on = Float64(get(oner, "umbral_oneroso", 1.0))
    u_sr = Float64(get(oner, "umbral_sin_riesgo_significativo", 0.90))
    u_sr <= u_on || throw(ArgumentError("umbral_sin_riesgo_significativo debe ser <= umbral_oneroso"))

    return Configuracion(
        fecha_corte,
        get(corrida, "moneda", "COP"),
        resolver(get(datos, "carpeta", ".")),
        resolver(get(datos, "carpeta_salidas", "salidas")),
        dec[1],
        _enum_desde_texto(PoliticaIACF, get(pol, "iacf", "DIFERIR")),
        devengo,
        Bool(get(pol, "descontar_lrc", false)),
        u_on, u_sr,
    )
end
