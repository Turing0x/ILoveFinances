import Foundation
import SwiftData

/// Tarjetas de transporte: viajes y saldo (Fase 6).
///
/// El modelo contable esta en dos frases y todo lo demas sale de ahi:
///
/// - **Recargar** la tarjeta es un TRASPASO desde la cuenta que paga. No es un
///   gasto: el dinero sigue siendo tuyo, solo cambia de sitio.
/// - **Viajar** es un GASTO por la tarifa, cargado sobre la PROPIA tarjeta.
///
/// Asi el gasto se reconoce al viajar y no al recargar, que es lo que hace que
/// "Transporte" en el resumen del mes sea el dinero realmente viajado y no un
/// pico de 20 EUR el dia de la recarga. Es la decision cerrada #3 de PLAN.md
/// (las tarjetas de credito) aplicada a otro sitio.
///
/// El saldo NO se guarda en ningun campo nuevo: sale de `Account.balance`, que
/// ya suma las dos orillas de un traspaso. Por eso deshacer un viaje es
/// simplemente borrar su transaccion.
///
/// A diferencia de `PurchaseService`, que es puro, aqui hace falta el
/// `ModelContext`: estas funciones escriben.
enum TransportService {

    /// Nombre de la categoria con la que se apuntan los viajes. Se busca por
    /// nombre porque es la sembrada en `SeedCategories.json` y no tiene un id
    /// estable entre instalaciones.
    static let tripCategoryName = "Transporte"

    /// Concepto del movimiento de viaje.
    static let tripNote = "Viaje"

    // MARK: - Consulta

    /// Tarjetas de transporte activas, ordenadas por nombre.
    static func cards(context: ModelContext) throws -> [Account] {
        // El filtro va en memoria y no en un `#Predicate`: el tipo se guarda en
        // `typeRaw` y comparar contra el rawValue de un enum dentro de un
        // predicado es justo la clase de expresion que SwiftData traduce mal.
        // Las cuentas son unas pocas decenas como mucho.
        let todas = try context.fetch(FetchDescriptor<Account>(sortBy: [SortDescriptor(\.name)]))
        return todas.filter { $0.type == .transport && !$0.isArchived }
    }

    /// Viajes de una tarjeta, del mas reciente al mas antiguo.
    ///
    /// Se leen de la relacion `card.transactions` en vez de con un predicado
    /// sobre `account`: los predicados sobre relacion son la parte fragil de
    /// SwiftData (ver `TransactionFilter`), y una tarjeta tiene los movimientos
    /// de unos meses, no de una vida.
    static func trips(card: Account, limit: Int? = nil) -> [Transaction] {
        let viajes = (card.transactions ?? [])
            .filter { $0.kind == .expense }
            .sorted { $0.date > $1.date }
        guard let limit else { return viajes }
        return Array(viajes.prefix(limit))
    }

    /// Viajes de una tarjeta dentro de un periodo.
    static func trips(card: Account, in period: DateInterval) -> [Transaction] {
        trips(card: card).filter { period.contains($0.date) }
    }

    /// Lo gastado en viajes dentro de un periodo.
    static func spent(card: Account, in period: DateInterval) -> Decimal {
        trips(card: card, in: period)
            .reduce(Decimal.zero) { $0 + $1.amount }
    }

    /// Saldo que quedaria tras un viaje mas. Puede ser negativo, y eso no es un
    /// error: ver `registerTrip`.
    static func balanceAfterTrip(card: Account) -> Decimal {
        card.balance - card.farePerTrip
    }

    // MARK: - Escritura

    enum TransportError: LocalizedError {
        case notATransportCard(String)
        case fareNotConfigured(String)

        var errorDescription: String? {
            switch self {
            case .notATransportCard(let name):
                return "«\(name)» no es una tarjeta de transporte."
            case .fareNotConfigured(let name):
                return "«\(name)» no tiene precio por viaje configurado."
            }
        }
    }

    /// Registra un viaje: gasto por `card.farePerTrip` sobre la propia tarjeta.
    ///
    /// **Un saldo insuficiente NO lo impide.** Dejar la tarjeta en negativo es
    /// un estado transitorio normal: se apuntan los viajes de ayer antes de
    /// apuntar la recarga que ya se hizo, y bloquearlo convertiria una app de
    /// apuntes en un validador que obliga a hacer las cosas en cierto orden.
    /// Quien decide avisar es la interfaz, con el saldo resultante a la vista.
    ///
    /// Devuelve la transaccion creada para poder deshacerla sin volver a
    /// buscarla.
    @discardableResult
    static func registerTrip(
        card: Account,
        date: Date = Date(),
        context: ModelContext
    ) throws -> Transaction {
        guard card.type == .transport else {
            throw TransportError.notATransportCard(card.name)
        }
        guard card.farePerTrip > 0 else {
            throw TransportError.fareNotConfigured(card.name)
        }

        let trip = Transaction(
            date: date,
            amount: card.farePerTrip,
            kind: .expense,
            note: tripNote,
            merchant: card.name,
            account: card,
            category: tripCategory(context: context)
        )
        context.insert(trip)
        try context.save()
        return trip
    }

    /// Deshace un viaje. El saldo se recupera solo porque es derivado: no hay
    /// ningun contador que corregir.
    static func undo(trip: Transaction, context: ModelContext) throws {
        context.delete(trip)
        try context.save()
    }

    // MARK: - Categoria

    /// Categoria "Transporte", sembrada al primer arranque.
    ///
    /// Si no aparece —alguien la borro, o la sembradora aun no ha corrido— el
    /// viaje se guarda SIN categoria en vez de fallar. Perder la categoria de
    /// un movimiento es molesto; no poder apuntar el bus, no.
    private static func tripCategory(context: ModelContext) -> TransactionCategory? {
        let nombre = tripCategoryName
        var descriptor = FetchDescriptor<TransactionCategory>(
            predicate: #Predicate { $0.name == nombre }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
