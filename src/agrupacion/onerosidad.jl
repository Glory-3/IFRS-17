# Test de onerosidad en el reconocimiento inicial (párr. 16–19, 47 para GMM; 18 y 57–58 para PAA).
#
# Bajo PAA el pasivo inicial es LRC_0 = P − IACF (si se difieren) o P (si se llevan a gasto), y los
# flujos de cumplimiento de la cobertura restante son FCF_0 = siniestros + RA + gastos de mantenimiento.
# El conjunto es oneroso si FCF_0 > LRC_0. Dividiendo por la prima:
#
#     ratio = siniestralidad × (1 + RA%) + factor_mantenimiento [+ factor_adquisicion si IACF se difieren]
#     oneroso  ⇔  ratio > umbral_oneroso (1.0)
#
# Los gastos no atribuibles quedan fuera (B66(d)). Por ahora los flujos no se descuentan
# (párr. 56: no es necesario si la cobertura es ≤ 1 año); el descuento se añade con el módulo de curvas.

"""
    clave_supuesto(claves, portafolio, cohorte, producto)

Devuelve la clave más específica disponible en `claves`, en este orden:
(portafolio, cohorte, producto) → (portafolio, cohorte, "") → (portafolio, 0, producto) → (portafolio, 0, "").
`nothing` si no existe ninguna.
"""
function clave_supuesto(claves, p::AbstractString, c::Integer, prod::AbstractString)
    for k in ((p, c, prod), (p, c, ""), (p, 0, prod), (p, 0, ""))
        k in claves && return k
    end
    return nothing
end

"Tablas de supuestos indexadas por (portafolio, cohorte, producto) para búsquedas O(1)."
struct IndiceSupuestos
    siniestralidad::Dict{Tuple{String,Int,String},Tuple{Float64,Float64}}
    gastos::Dict{Tuple{String,Int,String},NTuple{3,Float64}}   # (adquisición, mantenimiento, no atribuible)
end

function IndiceSupuestos(ins)
    sin = Dict{Tuple{String,Int,String},Tuple{Float64,Float64}}()
    for r in eachrow(ins.supuestos_siniestralidad)
        sin[(r.portafolio_id, r.cohorte, coalesce(r.producto, ""))] = (r.siniestralidad_esperada, r.ajuste_riesgo_pct)
    end
    gas = Dict{Tuple{String,Int,String},NTuple{3,Float64}}()
    for r in eachrow(ins.supuestos_gastos)
        k = (r.portafolio_id, r.cohorte, coalesce(r.producto, ""))
        a, m, n = get(gas, k, (0.0, 0.0, 0.0))
        cl = r.clasificacion
        gas[k] = cl == "ADQUISICION" ? (a + r.factor, m, n) :
                 cl == "MANTENIMIENTO" ? (a, m + r.factor, n) : (a, m, n + r.factor)
    end
    return IndiceSupuestos(sin, gas)
end

"Supuestos aplicables a un portafolio, cohorte y producto."
function supuestos_para(idx::IndiceSupuestos, p::AbstractString, c::Integer, prod::AbstractString = "")
    ks = clave_supuesto(keys(idx.siniestralidad), p, c, prod)
    ks === nothing && error("sin supuestos de siniestralidad para ($p, $c, $prod)")
    lr, ra = idx.siniestralidad[ks]
    kg = clave_supuesto(keys(idx.gastos), p, c, prod)
    a, m, n = kg === nothing ? (0.0, 0.0, 0.0) : idx.gastos[kg]
    return SupuestosGrupo(lr, ra, a, m, n)
end
supuestos_para(ins, p::AbstractString, c::Integer, prod::AbstractString = "") =
    supuestos_para(IndiceSupuestos(ins), p, c, prod)

"Ratio combinado esperado relevante para el test de onerosidad (ver encabezado del archivo)."
function ratio_combinado(s::SupuestosGrupo, politica::PoliticaIACF)
    r = s.siniestralidad * (1 + s.ajuste_riesgo) + s.factor_mantenimiento
    return politica == IACF_DIFERIR ? r + s.factor_adquisicion : r
end

"Clase de onerosidad según los umbrales de la configuración (párr. 16)."
function clasificar_onerosidad(ratio::Real, cfg::Configuracion)
    ratio > cfg.umbral_oneroso && return ONEROSO
    ratio <= cfg.umbral_sin_riesgo && return SIN_RIESGO_SIGNIFICATIVO
    return RESTANTE
end

"Resultado del test de onerosidad para un conjunto de contratos (portafolio × cohorte × producto)."
struct ResultadoOnerosidad
    portafolio::String
    cohorte::Int
    producto::String
    n_contratos::Int
    prima::Float64
    siniestros_esperados::Float64
    ajuste_riesgo::Float64
    gastos_mantenimiento::Float64
    iacf::Float64
    lrc_inicial::Float64           # P − IACF (diferir) o P (gasto)
    flujos_cumplimiento::Float64   # siniestros + RA + mantenimiento
    perdida_inicial::Float64       # max(0, FCF − LRC): componente de pérdida inicial
    ratio_combinado::Float64
    clase::ClaseOnerosidad
end

"""
    test_onerosidad_inicial(ins, cfg) -> Vector{ResultadoOnerosidad}

Evalúa cada conjunto portafolio × cohorte × producto con contratos reconocidos a la fecha de corte
(párr. 17: se permite evaluar conjuntos cuando la información razonable y sustentable lo respalda).
La prima de cada contrato es la suma de sus movimientos con `fecha_contable ≤ fecha_corte`.
"""
function test_onerosidad_inicial(ins, cfg::Configuracion)
    idx = IndiceSupuestos(ins)
    prima = prima_por_contrato(ins, cfg.fecha_corte)
    acum = Dict{Tuple{String,Int,String},Tuple{Int,Float64}}()
    for c in ins.contratos
        fr = fecha_reconocimiento(c)
        fr > cfg.fecha_corte && continue
        k = (c.portafolio, cohorte(fr), c.producto)
        n, p = get(acum, k, (0, 0.0))
        acum[k] = (n + 1, p + get(prima, c.id, 0.0))
    end
    res = ResultadoOnerosidad[]
    for k in sort!(collect(keys(acum)))
        (p, coh, prod) = k
        n, P = acum[k]
        s = supuestos_para(idx, p, coh, prod)
        sin = s.siniestralidad * P
        ra = sin * s.ajuste_riesgo
        mant = s.factor_mantenimiento * P
        iacf = s.factor_adquisicion * P
        lrc = cfg.politica_iacf == IACF_DIFERIR ? P - iacf : P
        fcf = sin + ra + mant
        ratio = ratio_combinado(s, cfg.politica_iacf)
        push!(res, ResultadoOnerosidad(p, coh, prod, n, P, sin, ra, mant, iacf, lrc, fcf,
                                       max(0.0, fcf - lrc), ratio, clasificar_onerosidad(ratio, cfg)))
    end
    return res
end

"Prima emitida acumulada por contrato hasta `corte`."
function prima_por_contrato(ins, corte::Date)
    d = Dict{String,Float64}()
    for m in ins.primas
        m.fecha_contable <= corte && (d[m.contrato_id] = get(d, m.contrato_id, 0.0) + m.monto)
    end
    return d
end
