import Foundation
import SwiftData
import Testing
@testable import ILoveFinances

/// Criterio de cierre de la Fase 1: "El export CSV se puede reimportar y
/// reconstruye la base de datos completa. Una copia de seguridad que no se ha
/// probado a restaurar no es una copia de seguridad."
@Suite("Copia de seguridad: ida y vuelta")
@MainActor
struct BackupRoundTripTests {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(SchemaV1.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    /// Datos con las trampas dentro a proposito: comas y comillas en los
    /// conceptos, un traspaso con sus dos cuentas, importes con decimales
    /// incomodos y una categoria hija.
    @discardableResult
    private func poblar(_ context: ModelContext) throws -> (Account, Account) {
        let corriente = Account(name: "Corriente, BBVA", type: .checking,
                                openingBalance: Decimal(string: "1000.00")!, iban: "1234")
        let ahorro = Account(name: "Ahorro", type: .savings,
                             openingBalance: Decimal(string: "500.00")!)
        context.insert(corriente)
        context.insert(ahorro)

        let vivienda = TransactionCategory(name: "Vivienda", kind: .expense, isSystem: true)
        context.insert(vivienda)
        let luz = TransactionCategory(name: "Luz \"contratada\"", kind: .expense, parentID: vivienda.id)
        context.insert(luz)

        let raul = FamilyTag(name: "Raul")
        context.insert(raul)

        context.insert(Transaction(
            amount: Decimal(string: "0.615")!, kind: .expense,
            note: "Cena, restaurante \"El Rincon\"\ncon salto de linea",
            merchant: "EL RINCON", account: corriente, category: luz, familyTag: raul
        ))
        context.insert(Transaction(
            amount: Decimal(string: "1234567.89")!, kind: .income,
            note: "Nomina", account: corriente
        ))
        context.insert(Transaction(
            amount: Decimal(string: "200.00")!, kind: .transfer,
            note: "Al ahorro", account: corriente, counterpartAccount: ahorro
        ))

        // Factura recurrente con un pago enlazado (Fase 2). El pago es lo que
        // prueba que la relacion transaccion→factura sobrevive al viaje.
        let ocurrencia = Calendar.current.startOfDay(for: Date())
        let factura = RecurringBill(
            name: "Luz, Endesa",
            estimatedAmount: Decimal(string: "61.20")!,
            isVariableAmount: true,
            recurrence: .monthly,
            dayOfMonth: 5,
            startDate: ocurrencia,
            reminderDaysBefore: 3,
            account: corriente,
            category: luz,
            familyTag: raul
        )
        context.insert(factura)

        let pago = Transaction(
            date: ocurrencia, amount: Decimal(string: "73.45")!, kind: .expense,
            note: "Luz de enero", account: corriente, category: luz
        )
        pago.recurringBill = factura
        pago.occurrenceDate = ocurrencia
        pago.isRecurringInstance = true
        context.insert(pago)

        try context.save()
        return (corriente, ahorro)
    }

    @Test("Exportar, borrar todo y restaurar deja la misma base de datos")
    func idaYVuelta() throws {
        let origen = try makeContext()
        try poblar(origen)

        let ficheros = try BackupService.export(context: origen)

        let destino = try makeContext()
        let resumen = try BackupService.restoreReplacingAll(files: ficheros, context: destino)

        #expect(resumen.accounts == 2)
        #expect(resumen.categories == 2)
        #expect(resumen.familyTags == 1)
        #expect(resumen.transactions == 4)
        #expect(resumen.recurringBills == 1)

        let cuentas = try destino.fetch(FetchDescriptor<Account>()).sorted { $0.name < $1.name }
        #expect(cuentas.map(\.name) == ["Ahorro", "Corriente, BBVA"])

        // El saldo es la prueba de que las relaciones se reconstruyeron bien:
        // depende de que cada transaccion apunte a su cuenta, y el traspaso a
        // las dos.
        let corriente = cuentas.first { $0.name == "Corriente, BBVA" }!
        let ahorro = cuentas.first { $0.name == "Ahorro" }!
        // 1000,00 − 0,615 + 1234567,89 − 200,00 − 73,45 (el traspaso sale de aqui)
        #expect(corriente.balance == Decimal(string: "1235293.825")!)
        #expect(ahorro.balance == Decimal(string: "700.00")!)
    }

    @Test("Los importes vuelven con igualdad exacta, sin tolerancia")
    func importesExactos() throws {
        let origen = try makeContext()
        try poblar(origen)
        let ficheros = try BackupService.export(context: origen)

        let destino = try makeContext()
        try BackupService.restoreReplacingAll(files: ficheros, context: destino)

        let importes = try destino.fetch(FetchDescriptor<Transaction>())
            .map(\.amount)
            .sorted { $0 < $1 }
        #expect(importes == [
            Decimal(string: "0.615")!,
            Decimal(string: "73.45")!,
            Decimal(string: "200.00")!,
            Decimal(string: "1234567.89")!,
        ])
    }

    /// Comas, comillas y saltos de linea dentro de un campo: sin comillas
    /// RFC 4180 el fichero se parte y la restauracion produce basura.
    @Test("Un concepto con comas, comillas y saltos de linea sobrevive")
    func camposConTrampa() throws {
        let origen = try makeContext()
        try poblar(origen)
        let ficheros = try BackupService.export(context: origen)

        let destino = try makeContext()
        try BackupService.restoreReplacingAll(files: ficheros, context: destino)

        let conceptos = try destino.fetch(FetchDescriptor<Transaction>()).map(\.note)
        #expect(conceptos.contains("Cena, restaurante \"El Rincon\"\ncon salto de linea"))
    }

    @Test("La jerarquia de categorias se conserva por parentID")
    func jerarquia() throws {
        let origen = try makeContext()
        try poblar(origen)
        let ficheros = try BackupService.export(context: origen)

        let destino = try makeContext()
        try BackupService.restoreReplacingAll(files: ficheros, context: destino)

        let categorias = try destino.fetch(FetchDescriptor<TransactionCategory>())
        let vivienda = categorias.first { $0.name == "Vivienda" }!
        let luz = categorias.first { $0.name.hasPrefix("Luz") }!
        #expect(luz.parentID == vivienda.id)
        #expect(vivienda.parentID == nil)
    }

    @Test("Las facturas y sus pagos vuelven enteros y enlazados")
    func facturasIdaYVuelta() throws {
        let origen = try makeContext()
        try poblar(origen)
        let ficheros = try BackupService.export(context: origen)

        let destino = try makeContext()
        try BackupService.restoreReplacingAll(files: ficheros, context: destino)

        let facturas = try destino.fetch(FetchDescriptor<RecurringBill>())
        #expect(facturas.count == 1)
        let factura = facturas[0]
        #expect(factura.name == "Luz, Endesa")
        #expect(factura.estimatedAmount == Decimal(string: "61.20")!)
        #expect(factura.isVariableAmount)
        #expect(factura.recurrence == .monthly)
        #expect(factura.dayOfMonth == 5)
        #expect(factura.reminderDaysBefore == 3)
        #expect(factura.account?.name == "Corriente, BBVA")
        #expect(factura.category?.name.hasPrefix("Luz") == true)
        #expect(factura.familyTag?.name == "Raul")

        // El enlace del pago es lo que da sentido al historial: sin el, la
        // factura restaurada no sabria lo que se ha pagado.
        #expect(factura.payments?.count == 1)
        let pago = factura.payments?.first
        #expect(pago?.amount == Decimal(string: "73.45")!)
        #expect(pago?.isRecurringInstance == true)
        #expect(pago?.occurrenceDate != nil)
        #expect(RecurringBillService.isPaid(pago!.occurrenceDate!, of: factura))
    }

    /// Actualizar la app no puede invalidar las copias hechas antes de
    /// actualizarla: una carpeta de la Fase 1 no trae `recurring_bills.csv` y
    /// eso significa "ninguna factura", no "fichero corrupto".
    @Test("Una copia de la Fase 1, sin facturas, sigue restaurando")
    func copiaAntiguaSinFacturas() throws {
        let origen = try makeContext()
        try poblar(origen)

        var ficheros = try BackupService.export(context: origen)
        ficheros.removeValue(forKey: BackupService.FileName.recurringBills)

        let destino = try makeContext()
        let resumen = try BackupService.restoreReplacingAll(files: ficheros, context: destino)

        #expect(resumen.recurringBills == 0)
        #expect(resumen.transactions == 4)
        #expect(try destino.fetchCount(FetchDescriptor<RecurringBill>()) == 0)
        // Las transacciones se restauran igual, solo que sin factura detras.
        #expect(try destino.fetch(FetchDescriptor<Transaction>()).allSatisfy { $0.recurringBill == nil })
    }

    /// Si el fichero esta corrupto, la base de datos se queda como estaba en
    /// vez de a medias. Por eso se parsea todo ANTES de borrar nada.
    @Test("Si falta un fichero, no se borra nada")
    func ficheroIncompletoNoDestruye() throws {
        let context = try makeContext()
        try poblar(context)
        let antes = try context.fetchCount(FetchDescriptor<Transaction>())

        var incompleto = try BackupService.export(context: context)
        incompleto.removeValue(forKey: BackupService.FileName.transactions)

        #expect(throws: BackupService.BackupError.self) {
            try BackupService.restoreReplacingAll(files: incompleto, context: context)
        }
        #expect(try context.fetchCount(FetchDescriptor<Transaction>()) == antes)
    }
}
