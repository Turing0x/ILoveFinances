import Foundation

/// Raw value `String` y no `Int`: un entero se rompe si se reordenan los casos,
/// y el texto sobrevive a refactors y es legible al depurar la base de datos.
enum TransactionKind: String, Codable, CaseIterable {
    case income
    case expense
    /// Movimiento entre cuentas propias: no es gasto ni ingreso.
    case transfer

    var label: String {
        switch self {
        case .income:   return "Ingreso"
        case .expense:  return "Gasto"
        case .transfer: return "Traspaso"
        }
    }

    var symbolName: String {
        switch self {
        case .income:   return "arrow.down.circle"
        case .expense:  return "arrow.up.circle"
        case .transfer: return "arrow.left.arrow.right.circle"
        }
    }
}
