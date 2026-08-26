import Foundation
import SwiftData
import Testing
@testable import ILoveFinances

/// PLAN.md seccion 7 bis: "Un .transfer de 200 EUR resta 200 en origen, suma
/// 200 en destino, y aporta 0 al gasto del periodo."
///
/// Es el criterio de cierre de la Fase 1 mas facil de romper: el signo de un
/// traspaso no es global, depende de desde que cuenta se mire.
@Suite("Saldos y traspasos")
@MainActor
struct BalanceTests {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(SchemaV2.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    @Test("Un gasto resta del saldo y un ingreso suma")
    func gastoEIngreso() throws {
        let context = try makeContext()
        let cuenta = Account(name: "Corriente", openingBalance: Decimal(string: "1000.00")!)
        context.insert(cuenta)

        context.insert(Transaction(amount: Decimal(string: "150.50")!, kind: .expense, account: cuenta))
        context.insert(Transaction(amount: Decimal(string: "2000.00")!, kind: .income, account: cuenta))
        try context.save()

        #expect(cuenta.balance == Decimal(string: "2849.50")!)
    }

    @Test("Un traspaso resta en origen y suma en destino")
    func traspasoMueveLasDosCuentas() throws {
        let context = try makeContext()
        let origen = Account(name: "Corriente", openingBalance: Decimal(string: "1000.00")!)
        let destino = Account(name: "Ahorro", openingBalance: Decimal(string: "500.00")!)
        context.insert(origen)
        context.insert(destino)

        context.insert(
            Transaction(
                amount: Decimal(string: "200.00")!,
                kind: .transfer,
                account: origen,
                counterpartAccount: destino
            )
        )
        try context.save()

        #expect(origen.balance == Decimal(string: "800.00")!)
        #expect(destino.balance == Decimal(string: "700.00")!)
    }

    /// El criterio literal del PLAN: "un traspaso entre cuentas propias no
    /// aparece como gasto en el dashboard".
    @Test("Un traspaso aporta cero al gasto del periodo")
    func traspasoNoEsGasto() {
        let origen = Account(name: "Corriente")
        let destino = Account(name: "Ahorro")
        let traspaso = Transaction(
            amount: Decimal(string: "200.00")!,
            kind: .transfer,
            account: origen,
            counterpartAccount: destino
        )
        #expect(traspaso.incomeExpenseAmount == .zero)
    }

    @Test("El patrimonio total no cambia con un traspaso")
    func elTraspasoNoCreaNiDestruyeDinero() throws {
        let context = try makeContext()
        let origen = Account(name: "Corriente", openingBalance: Decimal(string: "1000.00")!)
        let destino = Account(name: "Ahorro", openingBalance: Decimal(string: "500.00")!)
        context.insert(origen)
        context.insert(destino)
        context.insert(
            Transaction(amount: Decimal(string: "200.00")!, kind: .transfer,
                        account: origen, counterpartAccount: destino)
        )
        try context.save()

        #expect(origen.balance + destino.balance == Decimal(string: "1500.00")!)
    }

    @Test("Una cuenta sin movimientos vale su saldo de apertura")
    func cuentaVacia() throws {
        let context = try makeContext()
        let cuenta = Account(name: "Efectivo", type: .cash, openingBalance: Decimal(string: "42.00")!)
        context.insert(cuenta)
        try context.save()
        #expect(cuenta.balance == Decimal(string: "42.00")!)
    }

    @Test("Mil gastos de un centimo restan diez euros exactos del saldo")
    func acumulacionDeCentimos() throws {
        let context = try makeContext()
        let cuenta = Account(name: "Corriente", openingBalance: Decimal(string: "100.00")!)
        context.insert(cuenta)
        for _ in 0..<1_000 {
            context.insert(Transaction(amount: Decimal(string: "0.01")!, kind: .expense, account: cuenta))
        }
        try context.save()
        #expect(cuenta.balance == Decimal(string: "90.00")!)
    }
}
