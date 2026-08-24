import Foundation
import SwiftData

@Model
final class Transaction {
    /// `#Index` esta disponible con deployment target iOS 26 y se comprobo en
    /// la Fase 0 que compila. Cubre el listado ordenado por fecha y el filtro
    /// por tipo, que son las dos consultas de la pantalla de Movimientos.
    #Index<Transaction>([\.date], [\.date, \.kindRaw], [\.isPurchaseTicket, \.date])

    var id: UUID = UUID()
    var date: Date = Date()
    /// SIEMPRE positivo. El signo lo determina `kind`. Guardar negativos para
    /// los gastos obliga a recordar el convenio en cada suma y produce bugs
    /// silenciosos al importar CSV, porque cada banco usa el suyo.
    var amount: Decimal = Decimal.zero
    var kindRaw: String = TransactionKind.expense.rawValue
    var note: String = ""                     // concepto / descripcion
    var merchant: String?
    var createdAt: Date = Date()

    // Deduplicacion de importaciones CSV (Fase 3)
    var importHash: String?
    var importBatchID: UUID?

    // Marcadores
    var isRecurringInstance: Bool = false     // generada por una RecurringBill (Fase 2)

    /// Este gasto es un ticket de compra con sus lineas detalladas (Fase 5).
    ///
    /// Marcador denormalizado, mismo patron que `isRecurringInstance`. Las dos
    /// alternativas fallan: preguntar por `purchaseLines` no vacio es un
    /// predicado sobre relacion, que es la parte fragil de SwiftData (ver
    /// `TransactionFilter`), y preguntar por `shop != nil` es directamente
    /// incorrecto, porque borrar la tienda pone `shop` a nil y el ticket
    /// dejaria de serlo.
    var isPurchaseTicket: Bool = false

    /// Ocurrencia concreta que paga esta transaccion, a las 00:00 del dia
    /// previsto de cargo — NO el dia en que se pago.
    ///
    /// Es lo que permite saber si la factura de febrero esta pagada aunque se
    /// pagase el 12 de marzo. La alternativa que contemplaba el plan (buscar un
    /// pago dentro de una ventana alrededor de la ocurrencia) falla justo en
    /// ese caso y en el de dos pagos juntos.
    var occurrenceDate: Date?

    /// Foto de ticket. El campo entra en el esquema v1 aunque la UI llegue
    /// despues: anadir un campo a CloudKit es seguro, cambiarlo de tipo no.
    @Attribute(.externalStorage) var receiptData: Data?

    var account: Account?
    var counterpartAccount: Account?          // solo para kind == .transfer
    var category: TransactionCategory?
    var familyTag: FamilyTag?
    /// Inversa de `RecurringBill.payments`.
    var recurringBill: RecurringBill?
    /// Inversa de `Shop.purchases` (Fase 5).
    var shop: Shop?

    /// Lineas del ticket (Fase 5).
    ///
    /// UNICA relacion `.cascade` del esquema, y la desviacion esta fijada por
    /// un test para que nadie la "normalice" al `.nullify` de la casa. Una
    /// linea sin su transaccion pierde a la vez la fecha y la tienda, que son
    /// las dos coordenadas del historial de precios: deja de ser un dato y
    /// pasa a ser basura consultable, imposible de limpiar desde la interfaz.
    /// `.deny` no vale: esta prohibido por `SchemaInvariantTests` y ademas
    /// bloquearia borrar un gasto normal.
    @Relationship(deleteRule: .cascade, inverse: \PurchaseLine.transaction)
    var purchaseLines: [PurchaseLine]? = []

    init(
        date: Date = Date(),
        amount: Decimal = .zero,
        kind: TransactionKind = .expense,
        note: String = "",
        merchant: String? = nil,
        account: Account? = nil,
        counterpartAccount: Account? = nil,
        category: TransactionCategory? = nil,
        familyTag: FamilyTag? = nil
    ) {
        self.id = UUID()
        self.date = date
        self.amount = amount
        self.kindRaw = kind.rawValue
        self.note = note
        self.merchant = merchant
        self.createdAt = Date()
        self.isRecurringInstance = false
        self.account = account
        self.counterpartAccount = counterpartAccount
        self.category = category
        self.familyTag = familyTag
    }

    var kind: TransactionKind {
        get { TransactionKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    /// Importe con signo **relativo a una cuenta concreta**.
    ///
    /// No puede ser una propiedad sin parametro: un traspaso resta en origen y
    /// suma en destino, asi que la misma fila vale -200 para la corriente y
    /// +200 para el ahorro. Un `signedAmount` global es imposible de escribir
    /// correctamente.
    func signedAmount(for account: Account) -> Decimal {
        switch kind {
        case .income:  return amount
        case .expense: return -amount
        case .transfer:
            return account.id == counterpartAccount?.id ? amount : -amount
        }
    }

    /// Aporte al computo de gasto/ingreso del periodo.
    ///
    /// Un traspaso entre cuentas propias no es ni gasto ni ingreso: no mueve
    /// patrimonio, solo lo cambia de sitio. TODO agregado del dashboard, del
    /// grafico por categoria y de los totales de filtro usa esto, no
    /// `signedAmount(for:)`.
    var incomeExpenseAmount: Decimal {
        switch kind {
        case .income:   return amount
        case .expense:  return -amount
        case .transfer: return .zero
        }
    }

    /// Lineas del ticket en el orden en que venian en el papel (Fase 5).
    ///
    /// La relacion no garantiza orden, asi que ordenar por `position` es
    /// obligatorio en cualquier sitio que las muestre.
    var sortedLines: [PurchaseLine] {
        (purchaseLines ?? []).sorted { $0.position < $1.position }
    }
}
