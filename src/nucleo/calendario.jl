# Utilidades de calendario. La rejilla de cálculo es mensual (fin de mes).

"Último día del mes de `d`."
fin_de_mes(d::Date) = lastdayofmonth(d)

"Vector de fines de mes desde el mes de `desde` hasta el mes de `hasta`, ambos incluidos."
function rejilla_mensual(desde::Date, hasta::Date)
    desde > hasta && return Date[]
    meses = (year(hasta) - year(desde)) * 12 + month(hasta) - month(desde)
    return [fin_de_mes(firstdayofmonth(desde) + Month(k)) for k in 0:meses]
end

"""
    fraccion_devengada(inicio, fin, t; base=:diario)

Fracción de la cobertura `[inicio, fin]` (ambos días incluidos) transcurrida al cierre del día `t`.
`base = :mensual` cuenta meses completos de calendario (el mes de inicio se devenga completo).
"""
function fraccion_devengada(inicio::Date, fin::Date, t::Date; base::Symbol = :diario)
    t < inicio && return 0.0
    t >= fin && return 1.0
    if base === :diario
        return (Dates.value(t - inicio) + 1) / (Dates.value(fin - inicio) + 1)
    elseif base === :mensual
        total = length(rejilla_mensual(inicio, fin))
        return length(rejilla_mensual(inicio, t)) / total
    else
        throw(ArgumentError("base de devengo desconocida: $base"))
    end
end
