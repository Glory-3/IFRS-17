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

"""
    ejecutar(ruta_configuracion; escribir=true)

Corrida completa de la fase actual: carga y valida insumos, test de onerosidad inicial y formación
de grupos. Escribe los resultados en `carpeta_salidas` y devuelve un `NamedTuple` con todo.
"""
function ejecutar(ruta_configuracion::AbstractString; escribir::Bool = true)
    cfg = cargar_configuracion(ruta_configuracion)
    ins = cargar_insumos(cfg)
    oner = test_onerosidad_inicial(ins, cfg)
    grupos, clases = formar_grupos(ins, cfg, oner)
    if escribir
        mkpath(cfg.carpeta_salidas)
        out(n, df) = CSV.write(joinpath(cfg.carpeta_salidas, n), df)
        out("incidencias.csv", tabla_incidencias(ins.incidencias))
        out("onerosidad_inicial.csv", tabla_onerosidad(oner))
        out("grupos.csv", tabla_grupos(grupos))
        out("clasificacion_contratos.csv", tabla_clasificacion(clases, cfg.fecha_corte))
    end
    return (; configuracion = cfg, insumos = ins, onerosidad = oner, grupos, clase_por_contrato = clases)
end
