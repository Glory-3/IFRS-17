using Test, Dates, DataFrames, CSV
using IFRS17

# --- utilidades para armar un caso pequeño en una carpeta temporal ---------------------------
function escribir_caso(dir; contratos, primas, portafolios, siniestralidad, gastos, extra = Dict{String,DataFrame}(),
                       iacf = "DIFERIR", corte = "2024-12-31")
    for (n, df) in merge(Dict("contratos" => contratos, "primas" => primas, "portafolios" => portafolios,
                              "supuestos_siniestralidad" => siniestralidad, "supuestos_gastos" => gastos), extra)
        CSV.write(joinpath(dir, n * ".csv"), df)
    end
    ruta = joinpath(dir, "configuracion.toml")
    write(ruta, """
    [corrida]
    fecha_corte = $corte
    [datos]
    carpeta = "."
    carpeta_salidas = "salidas"
    [politicas]
    iacf = "$iacf"
    [onerosidad]
    umbral_oneroso = 1.0
    umbral_sin_riesgo_significativo = 0.90
    """)
    return ruta
end

caso_base() = (
    contratos = DataFrame(contrato_id = ["A1", "A2", "S1", "S2"], portafolio_id = ["AUT", "AUT", "SOAT", "SOAT"],
                          producto = ["", "", "", ""],
                          fecha_emision = Date.(["2024-01-10", "2024-03-01", "2024-02-01", "2023-12-20"]),
                          inicio_cobertura = Date.(["2024-01-10", "2024-03-01", "2024-02-01", "2024-01-01"]),
                          fin_cobertura = Date.(["2025-01-09", "2025-02-28", "2025-01-31", "2024-12-31"]),
                          fecha_primer_pago = [missing, missing, missing, missing]),
    primas = DataFrame(contrato_id = ["A1", "A2", "S1", "S2"],
                       fecha_contable = Date.(["2024-01-10", "2024-03-01", "2024-02-01", "2023-12-20"]),
                       tipo_movimiento = fill("EMISION", 4), monto = [1000.0, 3000.0, 2000.0, 500.0],
                       inicio_cobertura = fill(missing, 4), fin_cobertura = fill(missing, 4)),
    portafolios = DataFrame(portafolio_id = ["AUT", "SOAT"], descripcion = ["", ""],
                            modelo_medicion = ["PAA", "PAA"], curva_id = [missing, missing]),
    siniestralidad = DataFrame(portafolio_id = ["AUT", "SOAT"], cohorte = [0, 0], producto = ["", ""],
                               siniestralidad_esperada = [0.50, 0.80], ajuste_riesgo_pct = [0.10, 0.05]),
    gastos = DataFrame(portafolio_id = ["AUT", "AUT", "SOAT", "SOAT"], cohorte = [0, 0, 0, 0], producto = fill("", 4),
                       concepto = ["Com", "Adm", "Com", "Adm"],
                       clasificacion = ["ADQUISICION", "MANTENIMIENTO", "ADQUISICION", "MANTENIMIENTO"],
                       factor = [0.20, 0.10, 0.10, 0.12]),
)

@testset "IFRS17" begin

@testset "Calendario" begin
    @test fin_de_mes(Date(2024, 2, 10)) == Date(2024, 2, 29)
    @test rejilla_mensual(Date(2024, 11, 15), Date(2025, 2, 1)) ==
          Date.(["2024-11-30", "2024-12-31", "2025-01-31", "2025-02-28"])
    @test isempty(rejilla_mensual(Date(2025, 1, 1), Date(2024, 1, 1)))
    i, f = Date(2024, 1, 1), Date(2024, 12, 31)          # 366 días
    @test fraccion_devengada(i, f, Date(2023, 12, 31)) == 0.0
    @test fraccion_devengada(i, f, Date(2024, 1, 1)) ≈ 1 / 366
    @test fraccion_devengada(i, f, Date(2024, 6, 30)) ≈ 182 / 366
    @test fraccion_devengada(i, f, Date(2025, 3, 1)) == 1.0
    @test fraccion_devengada(i, f, Date(2024, 3, 31); base = :mensual) ≈ 3 / 12
end

@testset "Reconocimiento y cohorte (párr. 22, 25)" begin
    @test fecha_reconocimiento(Date(2024, 1, 1), Date(2023, 12, 20)) == Date(2023, 12, 20)
    @test fecha_reconocimiento(Date(2024, 1, 1), Date(2024, 2, 1)) == Date(2024, 1, 1)
    @test cohorte(Date(2023, 12, 20)) == 2023
end

@testset "Test de onerosidad: fórmula y umbrales" begin
    s = SupuestosGrupo(0.80, 0.05, 0.10, 0.12, 0.03)
    @test ratio_combinado(s, IACF_DIFERIR) ≈ 0.80 * 1.05 + 0.12 + 0.10
    @test ratio_combinado(s, IACF_GASTO) ≈ 0.80 * 1.05 + 0.12
    cfg = IFRS17.Configuracion(Date(2024, 12, 31), "COP", ".", ".", '.', IACF_DIFERIR, :diario, false, 1.0, 0.9)
    @test clasificar_onerosidad(1.0001, cfg) == ONEROSO
    @test clasificar_onerosidad(1.0, cfg) == RESTANTE
    @test clasificar_onerosidad(0.9, cfg) == SIN_RIESGO_SIGNIFICATIVO
    claves = Set([("P", 0, ""), ("P", 2024, ""), ("P", 0, "X")])
    @test clave_supuesto(claves, "P", 2024, "X") == ("P", 2024, "")
    @test clave_supuesto(claves, "P", 2023, "X") == ("P", 0, "X")
    @test clave_supuesto(claves, "P", 2023, "Y") == ("P", 0, "")
    @test clave_supuesto(claves, "Q", 2024, "") === nothing
end

@testset "Corrida completa con caso pequeño" begin
    mktempdir() do dir
        c = caso_base()
        r = ejecutar(escribir_caso(dir; c...); escribir = false)
        @test isempty(r.insumos.incidencias)
        t = Dict((x.portafolio, x.cohorte) => x for x in r.onerosidad)
        # AUT 2024: 0.5·1.1 + 0.10 + 0.20 = 0.85 -> sin riesgo significativo
        @test t[("AUT", 2024)].ratio_combinado ≈ 0.85
        @test t[("AUT", 2024)].clase == SIN_RIESGO_SIGNIFICATIVO
        @test t[("AUT", 2024)].prima == 4000.0
        # SOAT: 0.8·1.05 + 0.12 + 0.10 = 1.06 -> oneroso. S2 se reconoce en 2023 (emisión antes del inicio)
        s24 = t[("SOAT", 2024)]
        @test s24.clase == ONEROSO
        @test s24.lrc_inicial ≈ 2000 * 0.9
        @test s24.flujos_cumplimiento ≈ 2000 * (0.8 * 1.05 + 0.12)
        @test s24.perdida_inicial ≈ 2000 * 0.96 - 1800
        @test haskey(t, ("SOAT", 2023))
        @test Set(string(g.clave) for g in r.grupos) ==
              Set(["AUT-2024-SIN_RIESGO_SIGNIFICATIVO", "SOAT-2023-ONEROSO", "SOAT-2024-ONEROSO"])
        # Con IACF a gasto la pérdida se mide contra la prima completa
        r2 = ejecutar(escribir_caso(dir; c..., iacf = "GASTO"); escribir = false)
        s = only(filter(x -> x.portafolio == "SOAT" && x.cohorte == 2024, r2.onerosidad))
        @test s.ratio_combinado ≈ 0.96 && s.clase == RESTANTE && s.perdida_inicial == 0
    end
end

@testset "Clasificación previa se conserva (párr. 24)" begin
    mktempdir() do dir
        c = caso_base()
        previa = DataFrame(contrato_id = ["S1"], clase_onerosidad = ["RESTANTE"], fecha_clasificacion = [Date(2024, 6, 30)])
        r = ejecutar(escribir_caso(dir; c..., extra = Dict("clasificacion_previa" => previa)); escribir = false)
        @test r.clase_por_contrato["S1"] == RESTANTE      # aunque hoy el conjunto sale oneroso
        @test r.clase_por_contrato["S2"] == ONEROSO
    end
end

@testset "Supuestos por cohorte y producto" begin
    mktempdir() do dir
        c = caso_base()
        sin = vcat(c.siniestralidad, DataFrame(portafolio_id = ["SOAT"], cohorte = [2024], producto = [""],
                                               siniestralidad_esperada = [0.60], ajuste_riesgo_pct = [0.05]))
        r = ejecutar(escribir_caso(dir; c..., siniestralidad = sin); escribir = false)
        t = Dict((x.portafolio, x.cohorte) => x.clase for x in r.onerosidad)
        @test t[("SOAT", 2024)] == SIN_RIESGO_SIGNIFICATIVO   # 0.6·1.05+0.22 = 0.85
        @test t[("SOAT", 2023)] == ONEROSO                    # usa cohorte 0
    end
end

@testset "Validación de insumos" begin
    mktempdir() do dir
        c = caso_base()
        contratos = copy(c.contratos)
        contratos[2, :contrato_id] = "A1"                    # duplicado
        contratos[3, :portafolio_id] = "NOEXISTE"
        contratos[4, :fin_cobertura] = Date(2023, 1, 1)      # fin antes del inicio
        sin = filter(r -> r.portafolio_id != "AUT", c.siniestralidad)
        patron = DataFrame(portafolio_id = ["AUT", "AUT"], mes_desarrollo = [0, 1], proporcion = [0.5, 0.4])
        ruta = escribir_caso(dir; c..., contratos, siniestralidad = sin, extra = Dict("patron_pagos" => patron))
        cfg = cargar_configuracion(ruta)
        tablas, inc = leer_tablas(cfg.origen)
        append!(inc, validar(tablas, cfg; previas = inc))
        msgs = [i.mensaje for i in inc if i.nivel === :error]
        @test any(contains("duplicado"), msgs)
        @test any(contains("NOEXISTE"), msgs)
        @test any(contains("inicio_cobertura posterior"), msgs)
        @test any(contains("no hay supuestos para portafolio 'AUT'"), msgs)
        @test any(contains("suma 0.9"), msgs)
        @test_throws ErrorException cargar_insumos(cfg)

        # Fecha mal escrita y columna obligatoria ausente
        p = copy(c.primas); p[!, :fecha_contable] = string.(p.fecha_contable); p[1, :fecha_contable] = "10/01/2024"
        CSV.write(joinpath(dir, "primas.csv"), select(p, Not(:tipo_movimiento)))
        _, inc2 = leer_tablas(dir)
        m2 = [i.mensaje for i in inc2]
        @test any(contains("10/01/2024"), m2)
        @test any(contains("falta la columna obligatoria 'tipo_movimiento'"), m2)
    end
end

@testset "Excel de insumos (flujo normal de uso)" begin
    mktempdir() do dir
        c = caso_base()
        datos = Dict("contratos" => c.contratos, "primas" => c.primas, "portafolios" => c.portafolios,
                     "supuestos_siniestralidad" => c.siniestralidad, "supuestos_gastos" => c.gastos)
        ruta = generar_plantilla(joinpath(dir, "insumos.xlsx"); datos, parametros = Dict("fecha_corte" => Date(2024, 12, 31)))
        r = ejecutar(ruta)
        @test isempty(r.insumos.incidencias)
        @test Set(string(g.clave) for g in r.grupos) ==
              Set(["AUT-2024-SIN_RIESGO_SIGNIFICATIVO", "SOAT-2023-ONEROSO", "SOAT-2024-ONEROSO"])
        @test isfile(r.archivo) && dirname(r.archivo) == joinpath(dir, "resultados")
        # La plantilla vacía se puede leer y reporta lo que falta
        vacia = generar_plantilla(joinpath(dir, "vacia.xlsx"))
        @test_throws ErrorException cargar_insumos(cargar_configuracion(vacia))
        # Política GASTO desde la hoja configuracion
        r2 = ejecutar(generar_plantilla(joinpath(dir, "g.xlsx"); datos, parametros = Dict("politica_iacf" => "GASTO")); escribir = false)
        @test r2.configuracion.politica_iacf == IACF_GASTO
    end
end

@testset "Decimal con coma (Excel en español)" begin
    mktempdir() do dir
        write(joinpath(dir, "curvas.csv"), "curva_id;fecha_curva;plazo_meses;tasa_ea\nYC;2024-12-31;12;0,095\n")
        df, inc = IFRS17.leer_tabla(joinpath(dir, "curvas.csv"), IFRS17.tabla_esquema("curvas"); decimal = ',')
        @test isempty(inc) && df.tasa_ea[1] ≈ 0.095
    end
end

end
