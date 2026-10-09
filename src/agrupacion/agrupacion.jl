# Reconocimiento, cohortes y formación de grupos (párr. 14–28).

"""
    fecha_reconocimiento(inicio_cobertura, fecha_primer_pago)

Párr. 25: la más temprana entre (a) el inicio del periodo de cobertura y (b) la fecha en que vence
el primer pago del tomador. El literal (c) (cuando un grupo oneroso se vuelve oneroso) no puede ser
posterior a (a) o (b) para contratos ya emitidos, por lo que no cambia el resultado aquí.
"""
fecha_reconocimiento(inicio::Date, primer_pago::Date) = min(inicio, primer_pago)
fecha_reconocimiento(c::Contrato) = fecha_reconocimiento(c.inicio_cobertura, c.fecha_primer_pago)

"Cohorte anual (párr. 22): año calendario de la fecha de reconocimiento."
cohorte(d::Date) = year(d)

"""
    formar_grupos(ins, cfg, onerosidad) -> (grupos, clase_por_contrato)

Asigna cada contrato reconocido a la fecha de corte a su grupo portafolio × cohorte × clase.
Los contratos presentes en `clasificacion_previa` conservan su clase (párr. 24: los grupos no se
reevalúan después del reconocimiento inicial); los nuevos toman la clase de su conjunto en `onerosidad`.
Los supuestos del grupo son el promedio ponderado por prima de los conjuntos que lo componen.
"""
function formar_grupos(ins, cfg::Configuracion, onerosidad::Vector{ResultadoOnerosidad})
    clase_conjunto = Dict((r.portafolio, r.cohorte, r.producto) => r.clase for r in onerosidad)
    idx = IndiceSupuestos(ins)
    prima = prima_por_contrato(ins, cfg.fecha_corte)

    miembros = Dict{ClaveGrupo,Vector{String}}()
    fechas = Dict{ClaveGrupo,Date}()
    pesos = Dict{ClaveGrupo,Vector{Tuple{Float64,SupuestosGrupo}}}()
    clase_por_contrato = Dict{String,ClaseOnerosidad}()

    for c in ins.contratos
        fr = fecha_reconocimiento(c)
        fr > cfg.fecha_corte && continue
        coh = cohorte(fr)
        clase = get(ins.clasificacion_previa, c.id) do
            clase_conjunto[(c.portafolio, coh, c.producto)]
        end
        clase_por_contrato[c.id] = clase
        k = ClaveGrupo(c.portafolio, coh, clase)
        push!(get!(miembros, k, String[]), c.id)
        fechas[k] = min(get(fechas, k, fr), fr)
        push!(get!(pesos, k, Tuple{Float64,SupuestosGrupo}[]),
              (get(prima, c.id, 0.0), supuestos_para(idx, c.portafolio, coh, c.producto)))
    end

    grupos = GrupoContratos[]
    for k in sort!(collect(keys(miembros)))
        push!(grupos, GrupoContratos(k, ins.portafolios[k.portafolio].modelo, fechas[k], miembros[k],
                                     _promedio_ponderado(pesos[k])))
    end
    return grupos, clase_por_contrato
end

function _promedio_ponderado(v::Vector{Tuple{Float64,SupuestosGrupo}})
    w = sum(first, v)
    f(campo) = w == 0 ? sum(getfield(s, campo) for (_, s) in v) / length(v) :
                        sum(p * getfield(s, campo) for (p, s) in v) / w
    return SupuestosGrupo(f(:siniestralidad), f(:ajuste_riesgo), f(:factor_adquisicion),
                          f(:factor_mantenimiento), f(:factor_no_atribuible))
end
