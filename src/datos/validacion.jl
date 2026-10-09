# Validación de insumos: estructura (esquema) y coherencia de negocio.
# Errores detienen la corrida; advertencias se reportan pero no la detienen.

hay_errores(inc::Vector{Incidencia}) = any(i -> i.nivel === :error, inc)

function resumen_incidencias(inc::Vector{Incidencia}; max_por_tabla::Int = 20)
    io = IOBuffer()
    for tabla in unique(i.tabla for i in inc)
        lista = filter(i -> i.tabla == tabla, inc)
        ne = count(i -> i.nivel === :error, lista)
        println(io, "[$tabla] $ne errores, $(length(lista) - ne) advertencias")
        for i in first(lista, max_por_tabla)
            println(io, "  ", i.nivel === :error ? "ERROR " : "AVISO ", i.fila > 0 ? "fila $(i.fila): " : "", i.mensaje)
        end
        length(lista) > max_por_tabla && println(io, "  ... y $(length(lista) - max_por_tabla) más")
    end
    return String(take!(io))
end

"""
    validar(tablas, cfg; previas=Incidencia[]) -> Vector{Incidencia}

`previas` son las incidencias de lectura; se usan para no reportar dos veces la misma celda.
"""
function validar(tablas::Dict{String,DataFrame}, cfg::Configuracion; previas::Vector{Incidencia} = Incidencia[])
    inc = Incidencia[]
    err(t, f, m) = push!(inc, Incidencia(:error, t, f, m))
    adv(t, f, m) = push!(inc, Incidencia(:advertencia, t, f, m))
    con_error_lectura = Set((i.tabla, i.fila) for i in previas if i.nivel === :error)

    # 1. Esquema: obligatorios y valores permitidos
    for t in ESQUEMA
        df = tablas[t.nombre]
        for c in t.columnas, i in 1:nrow(df)
            v = df[i, c.nombre]
            if v === missing
                c.obligatoria && !((t.nombre, i) in con_error_lectura) &&
                    err(t.nombre, i, "'$(c.nombre)' es obligatorio")
            elseif !isempty(c.valores) && !(uppercase(string(v)) in c.valores)
                err(t.nombre, i, "'$(c.nombre)' = '$v' no permitido (use: $(join(c.valores, ", ")))")
            end
        end
    end
    # Normaliza a mayúsculas los campos con lista de valores
    for t in ESQUEMA, c in t.columnas
        isempty(c.valores) && continue
        col = tablas[t.nombre][!, c.nombre]
        tablas[t.nombre][!, c.nombre] = [v === missing ? missing : uppercase(v) for v in col]
    end

    completa(r) = all(x -> x !== missing, r)   # fila sin vacíos en las columnas indicadas

    # 2. Portafolios
    port = tablas["portafolios"]
    ids_port = Set(skipmissing(port.portafolio_id))
    _duplicados!(inc, "portafolios", port.portafolio_id)

    # 3. Contratos
    tc = tablas["contratos"]
    _duplicados!(inc, "contratos", tc.contrato_id)
    usados = Set{Tuple{String,Int,String}}()   # (portafolio, cohorte, producto) con contratos
    for (i, r) in enumerate(eachrow(tc))
        completa((r.contrato_id, r.portafolio_id, r.fecha_emision, r.inicio_cobertura, r.fin_cobertura)) || continue
        r.portafolio_id in ids_port || err("contratos", i, "portafolio '$(r.portafolio_id)' no existe en portafolios")
        r.inicio_cobertura > r.fin_cobertura && err("contratos", i, "inicio_cobertura posterior a fin_cobertura")
        r.fecha_emision > r.fin_cobertura && err("contratos", i, "fecha_emision posterior a fin_cobertura")
        fr = fecha_reconocimiento(r.inicio_cobertura, coalesce(r.fecha_primer_pago, r.fecha_emision))
        push!(usados, (r.portafolio_id, cohorte(fr), coalesce(r.producto, "")))
    end

    # 4. Primas
    tp = tablas["primas"]
    ids_contr = Set(skipmissing(tc.contrato_id))
    con_prima = Set{String}()
    for (i, r) in enumerate(eachrow(tp))
        r.contrato_id === missing && continue
        push!(con_prima, r.contrato_id)
        r.contrato_id in ids_contr || err("primas", i, "contrato '$(r.contrato_id)' no existe en contratos")
        (r.inicio_cobertura === missing) != (r.fin_cobertura === missing) &&
            err("primas", i, "informe inicio_cobertura y fin_cobertura juntos, o ninguno")
        completa((r.inicio_cobertura, r.fin_cobertura)) && r.inicio_cobertura > r.fin_cobertura &&
            err("primas", i, "inicio_cobertura posterior a fin_cobertura")
        if completa((r.monto, r.tipo_movimiento))
            r.monto == 0 && adv("primas", i, "movimiento con monto 0")
            uppercase(r.tipo_movimiento) == "CANCELACION" && r.monto > 0 &&
                adv("primas", i, "cancelación con monto positivo (se esperaba negativo)")
        end
    end
    sin_prima = setdiff(ids_contr, con_prima)
    isempty(sin_prima) || adv("contratos", 0, "$(length(sin_prima)) contratos sin movimientos de prima")

    # 5. Supuestos de siniestralidad
    ts = tablas["supuestos_siniestralidad"]
    _duplicados!(inc, "supuestos_siniestralidad",
                 collect(zip(ts.portafolio_id, ts.cohorte, coalesce.(ts.producto, ""))))
    for (i, r) in enumerate(eachrow(ts))
        completa((r.siniestralidad_esperada, r.ajuste_riesgo_pct)) || continue
        r.siniestralidad_esperada < 0 && err("supuestos_siniestralidad", i, "siniestralidad negativa")
        r.siniestralidad_esperada > 3 && adv("supuestos_siniestralidad", i, "siniestralidad > 300%: ¿está en fracción?")
        r.ajuste_riesgo_pct < 0 && err("supuestos_siniestralidad", i, "ajuste por riesgo negativo")
        r.ajuste_riesgo_pct > 1 && adv("supuestos_siniestralidad", i, "ajuste por riesgo > 100%: ¿está en fracción?")
    end
    claves_sin = Set(zip(ts.portafolio_id, ts.cohorte, coalesce.(ts.producto, "")))
    for (p, c, prod) in sort!(collect(usados))
        clave_supuesto(claves_sin, p, c, prod) === nothing &&
            err("supuestos_siniestralidad", 0, "no hay supuestos para portafolio '$p', cohorte $c, producto '$prod' (ni genéricos)")
    end

    # 6. Supuestos de gastos
    tg = tablas["supuestos_gastos"]
    _duplicados!(inc, "supuestos_gastos",
                 collect(zip(tg.portafolio_id, tg.cohorte, coalesce.(tg.producto, ""), tg.concepto)))
    for (i, r) in enumerate(eachrow(tg))
        r.factor === missing && continue
        r.factor < 0 && err("supuestos_gastos", i, "factor negativo")
        r.factor > 1 && adv("supuestos_gastos", i, "factor > 100%: ¿está en fracción?")
    end
    port_gastos = Set(skipmissing(tg.portafolio_id))
    for p in sort!(unique(first.(collect(usados))))
        p in port_gastos || adv("supuestos_gastos", 0, "portafolio '$p' sin gastos: se asumen 0")
    end

    # 7. Patrón de pagos
    tpp = tablas["patron_pagos"]
    for g in groupby(dropmissing(tpp, [:portafolio_id, :proporcion]), :portafolio_id)
        s = sum(g.proporcion)
        abs(s - 1) > 1e-6 && err("patron_pagos", 0, "el patrón de '$(g.portafolio_id[1])' suma $(round(s, digits=6)), debe sumar 1")
    end
    for (i, r) in enumerate(eachrow(tpp))
        r.mes_desarrollo !== missing && r.mes_desarrollo < 0 && err("patron_pagos", i, "mes_desarrollo negativo")
    end

    # 8. Curvas
    tcu = tablas["curvas"]
    _duplicados!(inc, "curvas", collect(zip(tcu.curva_id, tcu.fecha_curva, tcu.plazo_meses)))
    for (i, r) in enumerate(eachrow(tcu))
        r.plazo_meses !== missing && r.plazo_meses <= 0 && err("curvas", i, "plazo_meses debe ser positivo")
        r.tasa_ea !== missing && r.tasa_ea <= -1 && err("curvas", i, "tasa_ea debe ser mayor a -100%")
    end
    for r in eachrow(port)
        c = r.curva_id
        c === missing || c in Set(skipmissing(tcu.curva_id)) ||
            (cfg.descontar_lrc ? err : adv)("portafolios", 0, "curva '$c' de '$(r.portafolio_id)' no existe en curvas")
    end
    # 9. Clasificación previa
    tcp = tablas["clasificacion_previa"]
    _duplicados!(inc, "clasificacion_previa", tcp.contrato_id)
    for (i, r) in enumerate(eachrow(tcp))
        r.contrato_id === missing || r.contrato_id in ids_contr ||
            adv("clasificacion_previa", i, "contrato '$(r.contrato_id)' no está en contratos (se ignora)")
    end
    return inc
end

function _duplicados!(inc, tabla, claves)
    vistos = Dict{Any,Int}()
    for (i, k) in enumerate(claves)
        (k === missing || (k isa Tuple && any(ismissing, k))) && continue
        if haskey(vistos, k)
            push!(inc, Incidencia(:error, tabla, i, "registro duplicado $(k) (ya aparece en la fila $(vistos[k]))"))
        else
            vistos[k] = i
        end
    end
end
