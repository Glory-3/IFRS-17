# Regenera la plantilla vacía, el Excel de ejemplo y el diccionario de datos desde el esquema.
# Uso: julia --project=. scripts/generar_plantillas.jl
using IFRS17, CSV, DataFrames

raiz = joinpath(@__DIR__, "..")
generar_plantilla(joinpath(raiz, "plantillas", "IFRS17_Insumos_PLANTILLA.xlsx"))
write(joinpath(raiz, "plantillas", "DICCIONARIO_DE_DATOS.md"), diccionario_datos())

csv = joinpath(raiz, "datos", "ejemplo", "csv")
datos = Dict(splitext(f)[1] => CSV.read(joinpath(csv, f), DataFrame) for f in readdir(csv) if endswith(f, ".csv"))
generar_plantilla(joinpath(raiz, "datos", "ejemplo", "IFRS17_Insumos_ejemplo.xlsx"); datos)
println("Plantillas generadas.")
