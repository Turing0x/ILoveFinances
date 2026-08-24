import Foundation

enum AccountType: String, Codable, CaseIterable {
    case checking      // cuenta corriente
    case savings       // ahorro
    case card          // tarjeta de credito
    case cash          // efectivo
    case brokerage     // broker / cuenta de valores

    var label: String {
        switch self {
        case .checking:  return "Cuenta corriente"
        case .savings:   return "Ahorro"
        case .card:      return "Tarjeta"
        case .cash:      return "Efectivo"
        case .brokerage: return "Broker"
        }
    }

    var symbolName: String {
        switch self {
        case .checking:  return "building.columns"
        case .savings:   return "banknote"
        case .card:      return "creditcard"
        case .cash:      return "eurosign.circle"
        case .brokerage: return "chart.line.uptrend.xyaxis"
        }
    }
}
