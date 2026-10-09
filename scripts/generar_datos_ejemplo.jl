# Genera un juego de datos sintético (no son datos reales) en datos/ejemplo/.
# Uso: julia --project=. scripts/generar_datos_ejemplo.jl [n_contratos] [carpeta]
using Random, Dates, CSV, DataFrames

n = length(ARGS) >= 1 ? parse(Int, ARGS[1]) : 2000
carpeta = length(ARGS) >= 2 ? ARGS[2] : joinpath(@__DIR__, "..", "datos", "ejemplo")
mkpath(carpeta)
rng = MersenneTwister(2024)

# portafolio => (productos, meses de vigencia posibles, prima media)
portafolios = [
    ("AUTOS",        ["AUTOS_LIVIANOS", "AUTOS_PESADOS"], [12],         2_400_000.0),
    ("HOGAR",        ["HOGAR"],                           [12],           650_000.0),
    ("SOAT",         ["SOAT"],                            [12],           900_000.0),
    ("CUMPLIMIENTO", ["CUMPL_PRIVADO", "CUMPL_ESTATAL"],  [12, 24, 36], 3_500_000.0),
    ("VIDA_DEUDORES",["VIDA_DEUDORES"],                   [36, 48, 60], 1_200_000.0),
]

contratos = DataFrame(contrato_id = String[], portafolio_id = String[], producto = String[],
                      fecha_emision = Date[], inicio_cobertura = Date[], fin_cobertura = Date[],
                      fecha_primer_pago = Union{Missing,Date}[])
primas = DataFrame(contrato_id = String[], fecha_contable = Date[], tipo_movimiento = String[],
                   monto = Float64[], inicio_cobertura = Union{Missing,Date}[], fin_cobertura = Union{Missing,Date}[])

for i in 1:n
    p, prods, vig, media = portafolios[rand(rng, 1:length(portafolios))]
    prod = rand(rng, prods)
    inicio = Date(2023, 1, 1) + Day(rand(rng, 0:729))            # emisiones 2023–2024
    emision = inicio - Day(rand(rng, 0:15))
    fin = inicio + Month(rand(rng, vig)) - Day(1)
    id = string("POL", lpad(i, 7, '0'))
    push!(contratos, (id, p, prod, emision, inicio, fin, rand(rng) < 0.2 ? inicio + Day(30) : missing))
    prima = round(media * exp(0.4 * randn(rng)), digits = 0)
    push!(primas, (id, emision, "EMISION", prima, missing, missing))
    u = rand(rng)
    if u < 0.05                                                  # cancelación con devolución a prorrata
        fc = inicio + Day(rand(rng, 30:Dates.value(fin - inicio) - 1))
        dev = -round(prima * Dates.value(fin - fc) / (Dates.value(fin - inicio) + 1), digits = 0)
        push!(primas, (id, fc, "CANCELACION", dev, fc + Day(1), fin))
    elseif u < 0.10                                              # endoso de aumento
        fe = inicio + Day(rand(rng, 30:Dates.value(fin - inicio)))
        push!(primas, (id, fe, "ENDOSO", round(0.1 * prima, digits = 0), fe, fin))
    end
end

portafolios_df = DataFrame(
    portafolio_id = ["AUTOS", "HOGAR", "SOAT", "CUMPLIMIENTO", "VIDA_DEUDORES"],
    descripcion = ["Automóviles", "Hogar", "Seguro obligatorio de tránsito", "Cumplimiento", "Vida deudores"],
    modelo_medicion = ["PAA", "PAA", "PAA", "PAA", "GMM"],
    curva_id = fill("YC_COP", 5))

siniestralidad = DataFrame(
    portafolio_id = ["AUTOS", "HOGAR", "SOAT", "SOAT", "CUMPLIMIENTO", "CUMPLIMIENTO", "VIDA_DEUDORES"],
    cohorte =       [0,       0,       0,      2024,   0,              0,              0],
    producto =      ["",      "",      "",     "",     "",             "CUMPL_ESTATAL", ""],
    siniestralidad_esperada = [0.60, 0.35, 0.80, 0.70, 0.25, 0.55, 0.40],
    ajuste_riesgo_pct =       [0.05, 0.05, 0.06, 0.06, 0.08, 0.08, 0.07])

g(p, concepto, clas, f; coh = 0, prod = "") = (p, coh, prod, concepto, clas, f)
gastos = DataFrame([
    g("AUTOS", "Comisiones", "ADQUISICION", 0.15), g("AUTOS", "IVA_comisiones", "ADQUISICION", 0.03),
    g("AUTOS", "Administracion", "MANTENIMIENTO", 0.09), g("AUTOS", "Asistencias", "MANTENIMIENTO", 0.03),
    g("AUTOS", "Gastos_generales", "NO_ATRIBUIBLE", 0.03),
    g("HOGAR", "Comisiones", "ADQUISICION", 0.15), g("HOGAR", "Administracion", "MANTENIMIENTO", 0.10),
    g("SOAT", "Comisiones", "ADQUISICION", 0.05), g("SOAT", "Contribuciones", "MANTENIMIENTO", 0.06),
    g("SOAT", "Administracion", "MANTENIMIENTO", 0.06),
    g("CUMPLIMIENTO", "Comisiones", "ADQUISICION", 0.20), g("CUMPLIMIENTO", "Administracion", "MANTENIMIENTO", 0.10),
    g("VIDA_DEUDORES", "Comisiones", "ADQUISICION", 0.25), g("VIDA_DEUDORES", "Administracion", "MANTENIMIENTO", 0.08),
], [:portafolio_id, :cohorte, :producto, :concepto, :clasificacion, :factor])

patron = DataFrame(portafolio_id = String[], mes_desarrollo = Int[], proporcion = Float64[])
for (p, pat) in [("AUTOS", [0.40, 0.25, 0.15, 0.10, 0.10]), ("HOGAR", [0.50, 0.30, 0.20]),
                 ("SOAT", [0.30, 0.30, 0.20, 0.10, 0.10]), ("CUMPLIMIENTO", fill(1 / 12, 12)),
                 ("VIDA_DEUDORES", [0.70, 0.30])]
    for (k, x) in enumerate(pat)
        push!(patron, (p, k - 1, x))
    end
end

curvas = DataFrame(curva_id = String[], fecha_curva = Date[], plazo_meses = Int[], tasa_ea = Float64[])
for fc in (Date(2023, 12, 31), Date(2024, 12, 31)), m in [1, 3, 6, 12, 24, 36, 60, 120]
    push!(curvas, ("YC_COP", fc, m, round((year(fc) == 2023 ? 0.11 : 0.095) - 0.01 * log(1 + m / 12) / log(11), digits = 5)))
end

for (nombre, df) in ["contratos" => contratos, "primas" => primas, "portafolios" => portafolios_df,
                     "supuestos_siniestralidad" => siniestralidad, "supuestos_gastos" => gastos,
                     "patron_pagos" => patron, "curvas" => curvas]
    CSV.write(joinpath(carpeta, nombre * ".csv"), df)
end
println("Datos de ejemplo: $n contratos en $carpeta")
