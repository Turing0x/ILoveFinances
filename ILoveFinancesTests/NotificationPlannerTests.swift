import Foundation
import SwiftData
import Testing
@testable import ILoveFinances

/// PLAN.md seccion 8, riesgo del cupo: iOS permite 64 notificaciones locales
/// PENDIENTES por app y descarta las sobrantes en silencio. Es el criterio de
/// cierre mas facil de incumplir sin enterarse, porque no falla nada: solo
/// dejan de llegar avisos.
@Suite("Planificacion de avisos de facturas")
@MainActor
struct NotificationPlannerTests {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(SchemaV1.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func makeBill(
        _ name: String,
        recurrence: Recurrence = .monthly,
        day: Int = 1,
        reminder: Int = 3,
        in context: ModelContext,
        startingDaysAgo: Int = 400
    ) -> RecurringBill {
        let start = Calendar.current.date(byAdding: .day, value: -startingDaysAgo, to: Date()) ?? Date()
        let bill = RecurringBill(
            name: name,
            estimatedAmount: Decimal(string: "50.00")!,
            recurrence: recurrence,
            dayOfMonth: day,
            startDate: start,
            reminderDaysBefore: reminder
        )
        context.insert(bill)
        return bill
    }

    @Test("Veinte facturas activas nunca pasan de 64 avisos")
    func cupoDe64() throws {
        let context = try makeContext()
        // Semanales a proposito: son las que mas ocurrencias generan en la
        // ventana de 60 dias (~8 cada una, ~160 en total). Con mensuales el
        // test pasaria sin ejercitar el corte.
        let bills = (1...20).map { makeBill("Factura \($0)", recurrence: .weekly, in: context) }
        try context.save()

        let plan = NotificationPlanner.plan(bills: bills)

        #expect(plan.count <= NotificationPlanner.systemLimit)
        #expect(plan.count == NotificationPlanner.systemLimit, "con 20 semanales deberia llenarse el cupo")
    }

    @Test("Al cortar por cupo se conservan los avisos mas proximos")
    func elCorteTiraLoMasLejano() throws {
        let context = try makeContext()
        let bills = (1...20).map { makeBill("Factura \($0)", recurrence: .weekly, in: context) }
        try context.save()

        let plan = NotificationPlanner.plan(bills: bills)
        let sinCortar = NotificationPlanner.plan(bills: bills, limit: 1_000)

        #expect(sinCortar.count > plan.count)
        #expect(plan.map(\.id) == sinCortar.prefix(plan.count).map(\.id))
    }

    @Test("Los avisos van ordenados por fecha de disparo")
    func ordenadosPorFecha() throws {
        let context = try makeContext()
        let bills = [
            makeBill("A", day: 5, reminder: 0, in: context),
            makeBill("B", day: 3, reminder: 0, in: context),
            makeBill("C", day: 20, reminder: 10, in: context),
        ]
        try context.save()

        let plan = NotificationPlanner.plan(bills: bills)
        #expect(plan == plan.sorted { $0.fireDate < $1.fireDate })
    }

    @Test("Ninguna fecha de disparo cae en el pasado")
    func nadaEnElPasado() throws {
        let context = try makeContext()
        let ahora = Date()
        // Aviso con 30 dias de antelacion: las ocurrencias de las proximas
        // semanas tendrian disparo ya pasado y hay que descartarlas.
        let bills = [makeBill("Seguro", recurrence: .weekly, reminder: 30, in: context)]
        try context.save()

        let plan = NotificationPlanner.plan(bills: bills, from: ahora)
        #expect(plan.allSatisfy { $0.fireDate > ahora })
    }

    @Test("Una ocurrencia ya pagada no genera aviso")
    func pagadaNoAvisa() throws {
        let context = try makeContext()
        let bill = makeBill("Luz", recurrence: .monthly, day: 1, reminder: 3, in: context)
        try context.save()

        let ahora = Date()
        let antes = NotificationPlanner.plan(bills: [bill], from: ahora)
        guard let primera = antes.first else {
            Issue.record("sin avisos que probar")
            return
        }

        let pago = Transaction(date: primera.occurrenceDate, amount: Decimal(string: "61.20")!, kind: .expense)
        pago.occurrenceDate = primera.occurrenceDate
        pago.isRecurringInstance = true
        pago.recurringBill = bill
        context.insert(pago)
        try context.save()

        let despues = NotificationPlanner.plan(bills: [bill], from: ahora)
        #expect(!despues.contains { $0.id == primera.id })
        #expect(despues.count == antes.count - 1)
    }

    @Test("Una factura desactivada no genera ningun aviso")
    func desactivadaNoAvisa() throws {
        let context = try makeContext()
        let bill = makeBill("Gimnasio", recurrence: .weekly, in: context)
        try context.save()

        #expect(!NotificationPlanner.plan(bills: [bill]).isEmpty)
        bill.isActive = false
        try context.save()
        #expect(NotificationPlanner.plan(bills: [bill]).isEmpty)
    }

    /// La reprogramacion compara el plan nuevo con lo que ya esta pendiente. Si
    /// los identificadores cambiaran entre dos llamadas, cada arranque borraria
    /// y recrearia los 64 avisos, y el usuario veria el permiso parpadear.
    @Test("Los identificadores son estables entre dos planificaciones seguidas")
    func identificadoresEstables() throws {
        let context = try makeContext()
        let bills = (1...5).map { makeBill("Factura \($0)", day: $0 * 5, in: context) }
        try context.save()

        let ahora = Date()
        #expect(
            NotificationPlanner.plan(bills: bills, from: ahora).map(\.id)
                == NotificationPlanner.plan(bills: bills, from: ahora).map(\.id)
        )
    }
}
