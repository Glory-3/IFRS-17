# Tipos de dominio. Todos concretos para que el compilador genere código eficiente.

"Modelo de medición del grupo (párr. 29–30, 53)."
@enum ModeloMedicion PAA GMM

"Clasificación de onerosidad en el reconocimiento inicial (párr. 16)."
@enum ClaseOnerosidad begin
    ONEROSO                    # 16(a): onerosos en el reconocimiento inicial
    SIN_RIESGO_SIGNIFICATIVO   # 16(b): sin posibilidad significativa de volverse onerosos
    RESTANTE                   # 16(c): resto de contratos del portafolio
end

"Clasificación de un concepto de gasto según su tratamiento en IFRS 17."
@enum ClasificacionGasto begin
    ADQUISICION      # flujos de adquisición atribuibles (IACF, Apéndice A, B65(e))
    MANTENIMIENTO    # otros gastos atribuibles dentro del límite del contrato (B65)
    NO_ATRIBUIBLE    # fuera de los flujos de cumplimiento (B66(d))
end

"Tratamiento de IACF bajo PAA (párr. 28A, 59(a))."
@enum PoliticaIACF IACF_DIFERIR IACF_GASTO

"Contrato de seguro (póliza). Atributos estáticos."
struct Contrato
    id::String
    portafolio::String
    producto::String
    fecha_emision::Date
    inicio_cobertura::Date
    fin_cobertura::Date
    fecha_primer_pago::Date      # vencimiento del primer pago; si no se informa = fecha_emision
end

"Movimiento de prima emitida (emisión, endoso, cancelación). Cancelaciones con monto negativo."
struct MovimientoPrima
    contrato_id::String
    fecha_contable::Date
    tipo::String
    monto::Float64
    inicio_cobertura::Date
    fin_cobertura::Date
end

"Portafolio: contratos con riesgos similares gestionados conjuntamente (párr. 14)."
struct Portafolio
    id::String
    descripcion::String
    modelo::ModeloMedicion
    curva_id::String
end

"""
Supuestos que aplican a un portafolio y cohorte, expresados como fracción de la prima.

- `siniestralidad`: siniestros esperados / prima.
- `ajuste_riesgo`: RA como % de los siniestros esperados.
- `factor_adquisicion`, `factor_mantenimiento`, `factor_no_atribuible`: suma de factores por clasificación.
"""
struct SupuestosGrupo
    siniestralidad::Float64
    ajuste_riesgo::Float64
    factor_adquisicion::Float64
    factor_mantenimiento::Float64
    factor_no_atribuible::Float64
end

"Clave que identifica un grupo de contratos: portafolio × cohorte anual × clase de onerosidad (párr. 14–22)."
struct ClaveGrupo
    portafolio::String
    cohorte::Int
    clase::ClaseOnerosidad
end

Base.isless(a::ClaveGrupo, b::ClaveGrupo) =
    isless((a.portafolio, a.cohorte, Int(a.clase)), (b.portafolio, b.cohorte, Int(b.clase)))

"Identificador legible del grupo, p. ej. `AUTOS-2024-ONEROSO`."
Base.string(k::ClaveGrupo) = string(k.portafolio, "-", k.cohorte, "-", k.clase)

"Grupo de contratos: unidad de medición."
struct GrupoContratos
    clave::ClaveGrupo
    modelo::ModeloMedicion
    fecha_reconocimiento::Date      # párr. 25: la más temprana de los contratos del grupo
    contratos::Vector{String}
    supuestos::SupuestosGrupo
end

"Hallazgo de la validación de insumos."
struct Incidencia
    nivel::Symbol        # :error o :advertencia
    tabla::String
    fila::Int            # fila del archivo (1 = primera fila de datos); 0 si aplica a toda la tabla
    mensaje::String
end
