import SwiftUI

/// Importe formateado en euros, con el color y el signo que corresponden al
/// tipo de movimiento.
struct AmountText: View {
    let amount: Decimal
    let kind: TransactionKind
    var font: Font = .body

    init(transaction: Transaction, font: Font = .body) {
        self.amount = transaction.amount
        self.kind = transaction.kind
        self.font = font
    }

    /// Para importes que todavia no son un movimiento: el estimado de un
    /// recurrente, que necesita el mismo color y el mismo signo para que la
    /// lista se lea igual que la de movimientos.
    init(amount: Decimal, kind: TransactionKind, font: Font = .body) {
        self.amount = amount
        self.kind = kind
        self.font = font
    }

    var body: some View {
        Text(texto)
            .font(font)
            .monospacedDigit()
            .foregroundStyle(color)
    }

    private var texto: String {
        switch kind {
        case .income:   return "+\(Money.formatted(amount))"
        case .expense:  return "−\(Money.formatted(amount))"
        case .transfer: return Money.formatted(amount)
        }
    }

    private var color: Color {
        switch kind {
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
