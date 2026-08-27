import Foundation

/// Periodicidad de una factura recurrente.
///
/// Raw value `String` por el mismo motivo que `TransactionKind`: un `Int` se
/// rompe si se reordenan los casos, y el texto sobrevive a refactors y es
/// legible al depurar la base de datos.
enum Recurrence: String, Codable, CaseIterable {
    case weekly
    case biweekly
    case monthly
    case bimonthly
    case quarterly
    case semiannual
    case annual

    var label: String {
        switch self {
        case .weekly:     return "Semanal"
        case .biweekly:   return "Quincenal"
        case .monthly:    return "Mensual"
        case .bimonthly:  return "Bimestral"
        case .quarterly:  return "Trimestral"
        case .semiannual: return "Semestral"
        case .annual:     return "Anual"
        }
    }

    /// Paso en MESES, para las periodicidades ancladas al dia del mes.
    /// `nil` en semanal y quincenal, que van por dias.
    var monthStep: Int? {
        switch self {
        case .weekly, .biweekly: return nil
        case .monthly:    return 1
        case .bimonthly:  return 2
        case .quarterly:  return 3
        case .semiannual: return 6
        case .annual:     return 12
        }
    }

    /// Paso en DIAS, para semanal y quincenal. `nil` en las mensuales.
    ///
    /// Estas dos heredan el dia de la semana de `startDate` y por eso ignoran
    /// `dayOfMonth`: "todos los martes" no se puede expresar como dia del mes.
    var dayStep: Int? {
        switch self {
        case .weekly:   return 7
        case .biweekly: return 14
        default:        return nil
        }
    }

    /// Cuantas veces cae al ano. Es lo que normaliza importes de periodicidades
    /// distintas a un mismo mensual o anual comparable: un trimestral de 300 €
    /// son 1.200 €/ano y 100 €/mes.
    ///
    /// Semanal y quincenal son aproximaciones DELIBERADAS: 52 semanas son 364
    /// dias, no 365. El error es de un dia al ano y la alternativa —365/7—
    /// devuelve un decimal periodico que ensucia todas las sumas para no ganar
    /// nada en una cifra que ya es una estimacion.
    var occurrencesPerYear: Decimal {
        switch self {
        case .weekly:     return 52
        case .biweekly:   return 26
        case .monthly:    return 12
        case .bimonthly:  return 6
        case .quarterly:  return 4
        case .semiannual: return 2
        case .annual:     return 1
        }
    }

    /// Duracion aproximada del ciclo en dias. Solo se usa como respaldo para
    /// emparejar pagos antiguos sin `occurrenceDate`; nunca para calcular las
    /// ocurrencias, que van por calendario real.
    var approximateDays: Int {
        if let dayStep { return dayStep }
        return (monthStep ?? 1) * 30
    }
}
