import Foundation
import SwiftData
import Testing
@testable import ILoveFinances

/// PLAN.md seccion 7 Fase 2: "Marcar pagada crea una transaccion enlazada,
/// editable, con el importe real si difiere del estimado", y "desaparece de
/// proximas al marcarla pagada".
///
/// El enlace se hace por `occurrenceDate`, no por la fecha del pago. Los tests
/// de aqui son los que justifican esa decision: el caso del pago tardio falla
/// con cualquier deteccion por ventana.
@Suite("Pagos de facturas recurrentes")
@MainActor
struct BillPaymentTests {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(SchemaV1.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func makeBill(in context: ModelContext) -> RecurringBill {
        let cuenta = Account(name: "Corriente", openingBalance: Decimal(string: "1000.00")!)
        context.insert(cuenta)
        let categoria = TransactionCategory(name: "Luz", kind: .expense)
        context.insert(categoria)

        let inicio = Calendar.current.date(byAdding: .month, value: -6, to: Date()) ?? Date()
        let bill = RecurringBill(
            name: "Endesa",
            estimatedAmount: Decimal(string: "61.20")!,
            isVariableAmount: true,
            recurrence: .monthly,
            dayOfMonth: 5,
            startDate: inicio,
            account: cuenta,
            category: categoria
        )
        context.insert(bill)
        return bill
    }

    /// Reproduce lo que hace `QuickAddView` con un `BillPrefill`.
    @discardableResult
    private func pagar(
        _ bill: RecurringBill,
        ocurrencia: Date,
        importe: String,
        fechaDePago: Date? = nil,
        in context: ModelContext
    ) throws -> Transaction {
        let pago = Transaction(
            date: fechaDePago ?? ocurrencia,
            amount: Decimal(string: importe)!,
            kind: .expense,
            note: bill.name,
            account: bill.account,
            category: bill.category
        )
        pago.recurringBill = bill
        pago.occurrenceDate = ocurrencia
        pago.isRecurringInstance = true
        context.insert(pago)
        try context.save()
        return pago
    }

    @Test("Marcar pagada crea una transaccion enlazada con la ocurrencia")
    func pagoEnlazado() throws {
        let context = try makeContext()
        let bill = makeBill(in: context)
        try context.save()

        let ocurrencia = try #require(RecurringBillService.next(1, of: bill).first)
        let pago = try pagar(bill, ocurrencia: ocurrencia, importe: "73.45", in: context)

        #expect(pago.recurringBill?.id == bill.id)
        #expect(pago.isRecurringInstance)
        #expect(bill.payments?.count == 1)
        // El importe real manda sobre el estimado: es el sentido de confirmar
        // el pago en vez de generarlo solo.
        #expect(pago.amount == Decimal(string: "73.45")!)
        #expect(pago.amount != bill.estimatedAmount)
        // Y mueve el saldo de la cuenta como cualquier otro gasto.
        #expect(bill.account?.balance == Decimal(string: "926.55")!)
    }

    @Test("Una ocurrencia pagada deja de aparecer entre las proximas")
    func pagadaSaleDeProximas() throws {
        let context = try makeContext()
        let bill = makeBill(in: context)
        try context.save()

        let antes = RecurringBillService.upcoming(bills: [bill], days: 60, includingPaid: false)
        let ocurrencia = try #require(antes.first?.date)

        try pagar(bill, ocurrencia: ocurrencia, importe: "61.20", in: context)

        let despues = RecurringBillService.upcoming(bills: [bill], days: 60, includingPaid: false)
        #expect(!despues.contains { $0.date == ocurrencia })
        #expect(despues.count == antes.count - 1)
        // Y con `includingPaid` sigue estando, marcada como pagada: el listado
        // de la pantalla no pierde la fila, la tacha.
        let conPagadas = RecurringBillService.upcoming(bills: [bill], days: 60)
        #expect(conPagadas.first { $0.date == ocurrencia }?.isPaid == true)
    }

    /// El caso que justifica el campo `occurrenceDate`: pagar con doce dias de
    /// retraso marca la ocurrencia correcta y no la siguiente.
    @Test("Un pago tardio marca la ocurrencia a la que corresponde")
    func pagoTardio() throws {
        let context = try makeContext()
        let bill = makeBill(in: context)
        try context.save()

        let proximas = RecurringBillService.next(2, of: bill)
        let primera = try #require(proximas.first)
        let segunda = try #require(proximas.last)

        let tarde = try #require(Calendar.current.date(byAdding: .day, value: 12, to: primera))
        try pagar(bill, ocurrencia: primera, importe: "61.20", fechaDePago: tarde, in: context)

        #expect(RecurringBillService.isPaid(primera, of: bill))
        #expect(!RecurringBillService.isPaid(segunda, of: bill))
    }

    @Test("Dos ocurrencias pagadas no se confunden entre si")
    func dosPagosDistintos() throws {
        let context = try makeContext()
        let bill = makeBill(in: context)
        try context.save()

        let proximas = RecurringBillService.next(2, of: bill)
        try pagar(bill, ocurrencia: proximas[0], importe: "61.20", in: context)
        try pagar(bill, ocurrencia: proximas[1], importe: "88.90", in: context)

        #expect(RecurringBillService.payment(for: proximas[0], of: bill)?.amount == Decimal(string: "61.20")!)
        #expect(RecurringBillService.payment(for: proximas[1], of: bill)?.amount == Decimal(string: "88.90")!)
    }

    /// Los pagos creados a mano —o importados de un CSV en la Fase 3— no traen
    /// `occurrenceDate`. El respaldo por ventana evita que el historial de una
    /// factura antigua salga vacio.
    @Test("Un pago sin ocurrencia marcada se empareja por cercania")
    func respaldoPorVentana() throws {
        let context = try makeContext()
        let bill = makeBill(in: context)
        try context.save()

        let ocurrencia = try #require(RecurringBillService.next(1, of: bill).first)
        let dosDiasDespues = try #require(Calendar.current.date(byAdding: .day, value: 2, to: ocurrencia))

        let pago = Transaction(date: dosDiasDespues, amount: Decimal(string: "61.20")!, kind: .expense)
        pago.recurringBill = bill          // enlazada, pero sin occurrenceDate
        context.insert(pago)
        try context.save()

        #expect(RecurringBillService.isPaid(ocurrencia, of: bill))
    }

    @Test("El historial ordena de mas reciente a mas antiguo")
    func historialOrdenado() throws {
        let context = try makeContext()
        let bill = makeBill(in: context)
        try context.save()

        let proximas = RecurringBillService.next(3, of: bill)
        for (index, fecha) in proximas.enumerated() {
            try pagar(bill, ocurrencia: fecha, importe: "\(60 + index).00", in: context)
        }

        let historial = bill.sortedPayments
        #expect(historial.count == 3)
        #expect(historial.map(\.date) == proximas.reversed())
    }
}
