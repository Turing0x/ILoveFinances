import Foundation
import SwiftData

/// Conjunto de filtros de la pantalla de Movimientos.
///
/// **Reparto deliberado entre predicado y memoria.**
///
/// Al predicado van solo comparaciones sobre atributos escalares —fecha, tipo,
/// importe—, que es lo que SwiftData traduce a Core Data sin sorpresas. La
/// fecha ademas esta indexada (`#Index` en `Transaction`), asi que es el filtro
/// que mas reduce y el que conviene bajar a la consulta.
///
/// En memoria quedan los filtros por relacion (cuenta, categoria, miembro) y la
/// busqueda de texto. Los predicados que atraviesan relaciones opcionales son
/// la parte fragil de SwiftData, y con volumenes domesticos —miles de filas ya
/// recortadas por fecha— filtrar en memoria es instantaneo y no falla. Cambiar
/// robustez por una optimizacion que no se nota seria mal negocio.
struct TransactionFilter: Equatable {
    var period: DatePeriod?
    var kind: TransactionKind?
    var minAmount: Decimal?
    var maxAmount: Decimal?

    var accountID: UUID?
    var categoryID: UUID?
    var familyTagID: UUID?
    var searchText: String = ""

    static let empty = TransactionFilter()

    var isEmpty: Bool { self == .empty }

    // MARK: - Parte que baja a la consulta

    var predicate: Predicate<Transaction> {
        let start = period?.interval.start ?? .distantPast
        let end = period?.interval.end ?? .distantFuture
        let kindRaw = kind?.rawValue
        let minimum = minAmount
        let maximum = maxAmount

        return #Predicate<Transaction> { transaction in
            transaction.date >= start
                && transaction.date < end
                && (kindRaw == nil || transaction.kindRaw == kindRaw!)
                && (minimum == nil || transaction.amount >= minimum!)
                && (maximum == nil || transaction.amount <= maximum!)
        }
    }

    // MARK: - Parte que se aplica en memoria

    func matches(_ transaction: Transaction) -> Bool {
        if let accountID {
            // Un traspaso pertenece a las dos cuentas: filtrar por la de
            // destino tiene que encontrarlo igual, o el saldo de esa cuenta no
            // cuadraria con la lista que la explica.
            let pertenece = transaction.account?.id == accountID
                || transaction.counterpartAccount?.id == accountID
            if !pertenece { return false }
        }
        if let categoryID, transaction.category?.id != categoryID { return false }
        if let familyTagID, transaction.familyTag?.id != familyTagID { return false }

        if !searchText.isEmpty {
            let enConcepto = transaction.note.localizedStandardContains(searchText)
            let enComercio = transaction.merchant?.localizedStandardContains(searchText) ?? false
            if !enConcepto && !enComercio { return false }
        }
        return true
    }

    // MARK: - Chips

    struct Chip: Identifiable {
        let id: String
        let label: String
        let clear: (inout TransactionFilter) -> Void
    }

    func chips(
        accountName: (UUID) -> String?,
        categoryName: (UUID) -> String?,
        familyTagName: (UUID) -> String?
    ) -> [Chip] {
        var chips: [Chip] = []
        if let kind {
            chips.append(Chip(id: "kind", label: kind.label) { $0.kind = nil })
        }
        if let accountID, let name = accountName(accountID) {
            chips.append(Chip(id: "account", label: name) { $0.accountID = nil })
        }
        if let categoryID, let name = categoryName(categoryID) {
            chips.append(Chip(id: "category", label: name) { $0.categoryID = nil })
        }
        if let familyTagID, let name = familyTagName(familyTagID) {
            chips.append(Chip(id: "tag", label: name) { $0.familyTagID = nil })
        }
        if minAmount != nil || maxAmount != nil {
            let desde = minAmount.map(Money.formatted) ?? "…"
            let hasta = maxAmount.map(Money.formatted) ?? "…"
            chips.append(Chip(id: "amount", label: "\(desde) – \(hasta)") {
                $0.minAmount = nil
                $0.maxAmount = nil
            })
        }
        return chips
    }
}
