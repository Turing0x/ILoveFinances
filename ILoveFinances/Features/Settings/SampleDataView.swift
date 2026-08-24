#if DEBUG
import SwiftData
import SwiftUI

/// Generador de datos sinteticos, solo en DEBUG.
///
/// Existe por un criterio de cierre concreto: "la app arranca en frio en menos
/// de 2 segundos con 1.000 transacciones". Sin una forma comoda de llegar a mil
/// filas, ese criterio no se puede comprobar y se acaba dando por bueno.
struct SampleDataView: View {
    @Environment(\.modelContext) private var context
    @Query private var accounts: [Account]
    @Query private var categories: [TransactionCategory]

    @State private var count = 1_000
    @State private var billCount = 20
    @State private var pendingNotifications: Int?
    @State private var message: String?

    var body: some View {
        List {
            Section {
                Stepper("\(count) movimientos", value: $count, in: 100...20_000, step: 100)
                Button("Generar") { generate() }
                    .disabled(accounts.isEmpty || categories.isEmpty)
            } footer: {
                if accounts.isEmpty {
                    Text("Crea al menos una cuenta primero.")
                } else {
                    Text("Reparte los movimientos entre las cuentas y categorías existentes, con fechas del último año.")
                }
            }
            Section {
                Stepper("\(billCount) facturas", value: $billCount, in: 1...40)
                Button("Generar facturas") { generateBills() }
                    .disabled(accounts.isEmpty || categories.isEmpty)
                LabeledContent("Avisos pendientes") {
                    Text(pendingNotifications.map(String.init) ?? "—")
                        .monospacedDigit()
                        .foregroundStyle((pendingNotifications ?? 0) > 64 ? .red : .secondary)
                }
                .task(id: message) {
                    pendingNotifications = await NotificationService.shared.pendingCount()
                }
            } footer: {
                Text("Sirve para comprobar el cupo de notificaciones: con 20 facturas activas, los avisos pendientes nunca deben pasar de 64.")
            }

            if let message { Section { Text(message) } }
        }
        .navigationTitle("Datos de prueba")
    }

    /// Facturas variadas —semanales, mensuales, trimestrales— para poder
    /// verificar en el dispositivo el tope de 64 avisos pendientes
    /// (PLAN.md seccion 8). Las semanales son las que mas cupo consumen.
    private func generateBills() {
        let gastos = categories.filter { $0.kind == .expense }
        guard !gastos.isEmpty, !accounts.isEmpty else { return }

        let periodicidades: [Recurrence] = [.weekly, .biweekly, .monthly, .quarterly]
        let inicio = Calendar.current.date(byAdding: .month, value: -6, to: Date()) ?? Date()

        for index in 0..<billCount {
            context.insert(
                RecurringBill(
                    name: "Factura de prueba \(index + 1)",
                    estimatedAmount: Decimal(Int.random(in: 1_000...20_000)) / 100,
                    isVariableAmount: index % 3 == 0,
                    recurrence: periodicidades[index % periodicidades.count],
                    dayOfMonth: Int.random(in: 1...28),
                    startDate: inicio,
                    reminderDaysBefore: Int.random(in: 0...5),
                    account: accounts.randomElement(),
                    category: gastos.randomElement()
                )
            )
        }

        do {
            try context.save()
            NotificationService.shared.reschedule(context: context)
            message = "Generadas \(billCount) facturas."
        } catch {
            message = "Fallo: \(error)"
        }
    }

    private func generate() {
        let gastos = categories.filter { $0.kind == .expense }
        let ingresos = categories.filter { $0.kind == .income }
        guard !gastos.isEmpty else { return }

        let inicio = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()

        for index in 0..<count {
            let esIngreso = index % 30 == 0 && !ingresos.isEmpty
            let dias = Int.random(in: 0...365)
            let fecha = Calendar.current.date(byAdding: .day, value: dias, to: inicio) ?? Date()
            let centimos = Int.random(in: 100...25_000)

            context.insert(
                Transaction(
                    date: fecha,
                    amount: Decimal(centimos) / 100,
                    kind: esIngreso ? .income : .expense,
                    note: esIngreso ? "Ingreso \(index)" : "Gasto \(index)",
                    account: accounts.randomElement(),
                    category: esIngreso ? ingresos.randomElement() : gastos.randomElement()
                )
            )
        }

        do {
            try context.save()
            message = "Generados \(count) movimientos."
        } catch {
            message = "Fallo: \(error)"
        }
    }
}
#endif
