import Foundation

enum AccountType: String, Codable, CaseIterable {
    case checking      // cuenta corriente
    case savings       // ahorro
    case card          // tarjeta de credito
    case cash          // efectivo
    case brokerage     // broker / cuenta de valores
    /// Tarjeta de transporte (bus): saldo monedero que se recarga y del que
    /// cada viaje descuenta una tarifa fija. No es una tarjeta bancaria: no
    /// tiene IBAN y su saldo no puede gastarse en otra cosa.
    case transport

    var label: String {
        switch self {
        case .checking:  return "Cuenta corriente"
        case .savings:   return "Ahorro"
        case .card:      return "Tarjeta"
        case .cash:      return "Efectivo"
        case .brokerage: return "Broker"
        case .transport: return "Tarjeta de transporte"
        }
    }

    var symbolName: String {
        switch self {
        case .checking:  return "building.columns"
        case .savings:   return "banknote"
        case .card:      return "creditcard"
        case .cash:      return "eurosign.circle"
        case .brokerage: return "chart.line.uptrend.xyaxis"
        case .transport: return "bus"
        }
    }
}
