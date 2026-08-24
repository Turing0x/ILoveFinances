import SwiftUI

/// Importe formateado en euros, con el color y el signo que corresponden al
/// tipo de movimiento.
struct AmountText: View {
    let transaction: Transaction
    var font: Font = .body

    var body: some View {
        Text(texto)
            .font(font)
            .monospacedDigit()
            .foregroundStyle(color)
    }

    private var texto: String {
        switch transaction.kind {
        case .income:   return "+\(Money.formatted(transaction.amount))"
        case .expense:  return "−\(Money.formatted(transaction.amount))"
        case .transfer: return Money.formatted(transaction.amount)
        }
    }

    private var color: Color {
        switch transaction.kind {
        case .income:   return .green
        case .expense:  return .primary
        // Un traspaso no es ni bueno ni malo: no mueve patrimonio.
        case .transfer: return .secondary
        }
    }
}

/// Importe suelto, coloreado por su signo.
struct SignedAmountText: View {
    let value: Decimal
    var font: Font = .body

    var body: some View {
        Text(Money.formatted(value))
            .font(font)
            .monospacedDigit()
            .foregroundStyle(value < 0 ? Color.red : value > 0 ? Color.green : Color.secondary)
    }
}
