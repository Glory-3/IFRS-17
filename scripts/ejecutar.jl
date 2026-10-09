# Corrida completa del motor.
# Uso: julia --project=. scripts/ejecutar.jl <Excel de insumos>
# Sin argumento usa el ejemplo: datos/ejemplo/IFRS17_Insumos_ejemplo.xlsx
using IFRS17, Printf

ruta = isempty(ARGS) ? joinpath(@__DIR__, "..", "datos", "ejemplo", "IFRS17_Insumos_ejemplo.xlsx") : ARGS[1]
println("Leyendo: ", abspath(ruta))
r = try
    ejecutar(ruta)
catch e
    println("\n*** No se pudo ejecutar ***\n")
    println(e isa ErrorException || e isa ArgumentError ? e.msg : sprint(showerror, e))
    println("\nCorrija el Excel y vuelva a ejecutar.")
    exit(1)
end
inc = r.insumos.incidencias
isempty(inc) || (println("\nAdvertencias en los datos (no detienen la corrida):"); print(resumen_incidencias(inc)))

println("\nRESUMEN")
for f in eachrow(tabla_resumen(r.configuracion, r.insumos, r.onerosidad, r.grupos))
    @printf("  %-48s %s\n", f.concepto, f.valor)
end
println("\nTEST DE ONEROSIDAD INICIAL")
@printf("  %-15s %-8s %-16s %10s %8s  %s\n", "Portafolio", "Cohorte", "Producto", "Contratos", "Ratio", "Clase")
for x in r.onerosidad
    @printf("  %-15s %-8d %-16s %10d %8.4f  %s\n", x.portafolio, x.cohorte, x.producto, x.n_contratos,
            x.ratio_combinado, x.clase)
end
println("\nResultados completos en:\n  ", r.archivo)
