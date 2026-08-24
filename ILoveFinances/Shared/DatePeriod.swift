import Foundation

/// Periodo del dashboard: mes, trimestre, ano o rango a medida.
enum DatePeriod: Hashable {
    case month(Date)
    case quarter(Date)
    case year(Date)
    case custom(start: Date, end: Date)

    static var currentMonth: DatePeriod { .month(Date()) }

    var label: String {
        switch self {
        case .month:  return "Mes"
        case .quarter: return "Trimestre"
        case .year:   return "Ano"
        case .custom: return "Personalizado"
        }
    }

    /// Intervalo semiabierto [inicio, fin). Semiabierto y no cerrado para que
    /// una transaccion del ultimo dia a las 23:59 caiga dentro sin depender de
    /// la hora, y no aparezca ademas en el periodo siguiente.
    var interval: DateInterval {
        let calendar = Calendar.current
        switch self {
        case .month(let date):
            return calendar.dateInterval(of: .month, for: date) ?? DateInterval(start: date, duration: 0)
        case .quarter(let date):
            return calendar.dateInterval(of: .quarter, for: date) ?? DateInterval(start: date, duration: 0)
        case .year(let date):
            return calendar.dateInterval(of: .year, for: date) ?? DateInterval(start: date, duration: 0)
        case .custom(let start, let end):
            let from = calendar.startOfDay(for: min(start, end))
            let to = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: max(start, end))) ?? max(start, end)
            return DateInterval(start: from, end: to)
        }
    }

    /// El mismo periodo, corrido uno hacia atras. Es lo que permite mostrar la
    /// variacion respecto al periodo anterior en el dashboard.
    var previous: DatePeriod {
        let calendar = Calendar.current
        switch self {
        case .month(let date):
            return .month(calendar.date(byAdding: .month, value: -1, to: date) ?? date)
        case .quarter(let date):
            return .quarter(calendar.date(byAdding: .month, value: -3, to: date) ?? date)
        case .year(let date):
            return .year(calendar.date(byAdding: .year, value: -1, to: date) ?? date)
        case .custom(let start, let end):
            // Se desplaza el rango por su propia duracion, en dias completos.
            let days = calendar.dateComponents([.day], from: start, to: end).day ?? 0
            let shift = -(days + 1)
            let newStart = calendar.date(byAdding: .day, value: shift, to: start) ?? start
            let newEnd = calendar.date(byAdding: .day, value: shift, to: end) ?? end
            return .custom(start: newStart, end: newEnd)
        }
    }

    var title: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        switch self {
        case .month(let date):
            formatter.dateFormat = "LLLL yyyy"
            return formatter.string(from: date).capitalized
        case .quarter(let date):
            let quarter = (Calendar.current.component(.month, from: date) - 1) / 3 + 1
            return "T\(quarter) \(Calendar.current.component(.year, from: date))"
        case .year(let date):
            return "\(Calendar.current.component(.year, from: date))"
        case .custom:
            formatter.dateStyle = .short
            return "\(formatter.string(from: interval.start)) – \(formatter.string(from: interval.end))"
        }
    }
}
