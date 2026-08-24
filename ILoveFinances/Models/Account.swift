import Foundation
import SwiftData

@Model
final class Account {
    var id: UUID = UUID()
    var name: String = ""
    var typeRaw: String = AccountType.checking.rawValue
    var openingBalance: Decimal = Decimal.zero   // saldo al dar de alta
    var iban: String?                            // ultimos 4 digitos, para reconocer el CSV
    var colorHex: String?
    var isArchived: Bool = false
    var createdAt: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \Transaction.account)
    var transactions: [Transaction]? = []

    /// Inversa obligatoria de `Transaction.counterpartAccount`: traspasos
    /// ENTRANTES a esta cuenta. CloudKit exige inversa declarada en toda
    /// relacion; sin esto la sincronizacion falla.
    @Relationship(deleteRule: .nullify, inverse: \Transaction.counterpartAccount)
    var incomingTransfers: [Transaction]? = []

    /// Inversa de `ImportProfile.account`. Sin usar hasta la Fase 3, pero
    /// obligatoria ya: CloudKit rechaza el store entero si falta una sola
    /// inversa, y el fallo es en tiempo de EJECUCION, no de compilacion.
    @Relationship(deleteRule: .nullify, inverse: \ImportProfile.account)
    var importProfiles: [ImportProfile]? = []

    /// Inversa de `RecurringBill.account` (Fase 2). Misma regla: sin inversa
    /// declarada CloudKit rechaza el store entero, en ejecucion y sin aviso.
    @Relationship(deleteRule: .nullify, inverse: \RecurringBill.account)
    var recurringBills: [RecurringBill]? = []

    init(
        name: String = "",
        type: AccountType = .checking,
        openingBalance: Decimal = .zero,
        iban: String? = nil,
        colorHex: String? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.typeRaw = type.rawValue
        self.openingBalance = openingBalance
        self.iban = iban
        self.colorHex = colorHex
        self.isArchived = false
        self.createdAt = Date()
    }

    var type: AccountType {
        get { AccountType(rawValue: typeRaw) ?? .checking }
        set { typeRaw = newValue.rawValue }
    }
}

extension Account {
    /// El saldo NO se persiste: se deriva. Persistirlo obliga a mantenerlo
    /// consistente en cada alta, edicion, borrado e importacion, y bajo
    /// CloudKit eso se desincroniza. Derivarlo es correcto por construccion.
    ///
    /// Los traspasos se miran desde las dos orillas: uno esta en
    /// `transactions` de la cuenta origen y en `incomingTransfers` de la
    /// destino, nunca en las dos listas de la MISMA cuenta — de ahi que sumar
    /// ambas no duplique. Salvo que alguien traspase una cuenta a si misma,
    /// que el formulario impide.
    var balance: Decimal {
        let salientes = (transactions ?? []).reduce(Decimal.zero) { $0 + $1.signedAmount(for: self) }
        let entrantes = (incomingTransfers ?? []).reduce(Decimal.zero) { $0 + $1.signedAmount(for: self) }
        return openingBalance + salientes + entrantes
    }
}
