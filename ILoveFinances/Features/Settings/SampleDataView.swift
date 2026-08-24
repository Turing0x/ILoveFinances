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
            if let message { Section { Text(message) } }
        }
        .navigationTitle("Datos de prueba")
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
