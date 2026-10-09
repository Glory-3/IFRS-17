"""
    IFRS17

Motor de medición IFRS 17. Organización por capas, siguiendo el orden de la norma:

1. `nucleo/`      tipos de dominio, calendario y configuración de la corrida.
2. `datos/`       esquema de insumos, lectura y validación.
3. `agrupacion/`  reconocimiento, cohortes, test de onerosidad inicial y grupos (párr. 14–28, 47, 57).
4. `reportes/`    tablas de resultados y corrida completa (`ejecutar`).
"""
module IFRS17

using Dates
using CSV
using DataFrames
using TOML

include("nucleo/tipos.jl")
include("nucleo/calendario.jl")
include("nucleo/configuracion.jl")
include("datos/esquema.jl")
include("datos/lectura.jl")
include("datos/validacion.jl")
include("agrupacion/onerosidad.jl")
include("agrupacion/agrupacion.jl")
include("reportes/salidas.jl")

# Tipos
export ModeloMedicion, PAA, GMM
export ClaseOnerosidad, ONEROSO, SIN_RIESGO_SIGNIFICATIVO, RESTANTE
export ClasificacionGasto, ADQUISICION, MANTENIMIENTO, NO_ATRIBUIBLE
export PoliticaIACF, IACF_DIFERIR, IACF_GASTO
export Contrato, MovimientoPrima, Portafolio, SupuestosGrupo, ClaveGrupo, GrupoContratos
export Configuracion, Insumos, Incidencia, ResultadoOnerosidad

# Funciones
export fin_de_mes, rejilla_mensual, fraccion_devengada
export cargar_configuracion, leer_tablas, construir_insumos, cargar_insumos, validar, hay_errores, resumen_incidencias
export fecha_reconocimiento, cohorte, supuestos_para, ratio_combinado, clasificar_onerosidad
export clave_supuesto, prima_por_contrato, test_onerosidad_inicial, formar_grupos, generar_plantillas
export tabla_onerosidad, tabla_grupos, tabla_clasificacion, tabla_incidencias, ejecutar

end # module
