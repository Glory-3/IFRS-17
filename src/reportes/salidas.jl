# Conversión de resultados a tablas y escritura de salidas.

function tabla_onerosidad(res::Vector{ResultadoOnerosidad})
    DataFrame(
        portafolio = [r.portafolio for r in res], cohorte = [r.cohorte for r in res],
        producto = [r.producto for r in res], n_contratos = [r.n_contratos for r in res],
        prima = [r.prima for r in res], siniestros_esperados = [r.siniestros_esperados for r in res],
        ajuste_riesgo = [r.ajuste_riesgo for r in res], gastos_mantenimiento = [r.gastos_mantenimiento for r in res],
        iacf = [r.iacf for r in res], lrc_inicial = [r.lrc_inicial for r in res],
        flujos_cumplimiento = [r.flujos_cumplimiento for r in res], perdida_inicial = [r.perdida_inicial for r in res],
        ratio_combinado = [r.ratio_combinado for r in res], clase = [string(r.clase) for r in res])
end

function tabla_grupos(grupos::Vector{GrupoContratos})
    DataFrame(
        grupo_id = [string(g.clave) for g in grupos], portafolio = [g.clave.portafolio for g in grupos],
        cohorte = [g.clave.cohorte for g in grupos], clase = [string(g.clave.clase) for g in grupos],
        modelo = [string(g.modelo) for g in grupos], fecha_reconocimiento = [g.fecha_reconocimiento for g in grupos],
        n_contratos = [length(g.contratos) for g in grupos],
        siniestralidad = [g.supuestos.siniestralidad for g in grupos],
        ajuste_riesgo_pct = [g.supuestos.ajuste_riesgo for g in grupos],
        factor_adquisicion = [g.supuestos.factor_adquisicion for g in grupos],
        factor_mantenimiento = [g.supuestos.factor_mantenimiento for g in grupos],
        factor_no_atribuible = [g.supuestos.factor_no_atribuible for g in grupos])
end

"Clasificación por contrato, con el formato de la tabla de insumo `clasificacion_previa`."
function tabla_clasificacion(clase_por_contrato::Dict{String,ClaseOnerosidad}, corte::Date)
    ids = sort!(collect(keys(clase_por_contrato)))
    DataFrame(contrato_id = ids, clase_onerosidad = [string(clase_por_contrato[i]) for i in ids],
              fecha_clasificacion = fill(corte, length(ids)))
end

function tabla_incidencias(inc::Vector{Incidencia})
    DataFrame(nivel = [string(i.nivel) for i in inc], tabla = [i.tabla for i in inc],
              fila = [i.fila for i in inc], mensaje = [i.mensaje for i in inc])
end

"Número con separador de miles y dos decimales, p. ej. 1,234,567.89"
function miles(x::Real)
    ent, dec = split(@sprintf("%.2f", abs(x)), '.')
    ent = reverse(join(join.(Iterators.partition(reverse(ent), 3)), ","))
    return (x < 0 ? "-" : "") * ent * "." * dec
end

"Hoja de resumen con las cifras principales de la corrida."
function tabla_resumen(cfg::Configuracion, ins, oner, grupos)
    n_on = count(g -> g.clave.clase == ONEROSO, grupos)
    filas = [
        ("Fecha de corte", string(cfg.fecha_corte)),
        ("Moneda", cfg.moneda),
        ("Política IACF", cfg.politica_iacf == IACF_DIFERIR ? "DIFERIR" : "GASTO"),
        ("Contratos leídos", string(length(ins.contratos))),
        ("Contratos reconocidos al corte", string(sum(length(g.contratos) for g in grupos; init = 0))),
        ("Grupos de contratos", string(length(grupos))),
        ("Grupos onerosos", string(n_on)),
        ("Prima de conjuntos onerosos", miles(sum(r.prima for r in oner if r.clase == ONEROSO; init = 0.0))),
        ("Pérdida inicial total (componente de pérdida)", miles(sum(r.perdida_inicial for r in oner; init = 0.0))),
        ("Advertencias en los datos", string(count(i -> i.nivel === :advertencia, ins.incidencias))),
    ]
    DataFrame(concepto = first.(filas), valor = last.(filas))
end

"Escribe el Excel de resultados y devuelve su ruta."
function escribir_resultados(cfg::Configuracion, ins, oner, grupos, clases)
    mkpath(cfg.carpeta_salidas)
    ruta = joinpath(cfg.carpeta_salidas, "resultados_$(cfg.fecha_corte).xlsx")
    isfile(ruta) && rm(ruta)
    hojas = ["resumen" => tabla_resumen(cfg, ins, oner, grupos),
             "onerosidad_inicial" => tabla_onerosidad(oner),
             "grupos" => tabla_grupos(grupos),
             "clasificacion_contratos" => tabla_clasificacion(clases, cfg.fecha_corte),
             "incidencias" => tabla_incidencias(ins.incidencias)]
    XLSX.openxlsx(ruta, mode = "w") do xf
        for (k, (nombre, df)) in enumerate(hojas)
            h = k == 1 ? xf[1] : XLSX.addsheet!(xf, nombre)
            k == 1 && XLSX.rename!(h, nombre)
            escribir_tabla!(h, df)
        end
    end
    return ruta
end

"""
    ejecutar(ruta; escribir=true)

Corrida completa. `ruta` es el Excel de insumos (o un `.toml` en el formato avanzado).
Carga y valida los datos, hace el test de onerosidad inicial y forma los grupos.
Escribe `resultados/resultados_<corte>.xlsx` y devuelve un `NamedTuple` con todo.
"""
function ejecutar(ruta::AbstractString; escribir::Bool = true)
    cfg = cargar_configuracion(ruta)
    ins = cargar_insumos(cfg)
    oner = test_onerosidad_inicial(ins, cfg)
    grupos, clases = formar_grupos(ins, cfg, oner)
    archivo = escribir ? escribir_resultados(cfg, ins, oner, grupos, clases) : ""
    return (; configuracion = cfg, insumos = ins, onerosidad = oner, grupos, clase_por_contrato = clases, archivo)
end
