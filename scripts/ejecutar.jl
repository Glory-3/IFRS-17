# Corrida completa. Uso: julia --project=. scripts/ejecutar.jl [ruta/configuracion.toml]
using IFRS17, DataFrames

ruta = isempty(ARGS) ? joinpath(@__DIR__, "..", "datos", "ejemplo", "configuracion.toml") : ARGS[1]
t = @elapsed r = ejecutar(ruta)
inc = r.insumos.incidencias
isempty(inc) || print(resumen_incidencias(inc))
println("\nTest de onerosidad inicial (portafolio × cohorte × producto):")
show(select(tabla_onerosidad(r.onerosidad), :portafolio, :cohorte, :producto, :n_contratos, :prima,
            :ratio_combinado, :perdida_inicial, :clase); allrows = true, allcols = true)
println("\n\nGrupos de contratos:")
show(select(tabla_grupos(r.grupos), :grupo_id, :modelo, :fecha_reconocimiento, :n_contratos); allrows = true)
println("\n\nSalidas en $(r.configuracion.carpeta_salidas)  ($(round(t, digits = 2)) s)")
