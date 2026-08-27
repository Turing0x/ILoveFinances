import Foundation
import SwiftData
import Testing
@testable import ILoveFinances

/// Fase 7: los ingresos recurrentes —nomina, facturacion de autonomo,
/// suscripciones cobradas— son la MISMA entidad que las facturas con `kind`
/// distinto.
///
/// Lo que se prueba aqui es exactamente lo que puede romperse por serlo: que
/// una fila antigua sin el campo siga siendo un gasto, que el resumen mensual y
/// anual normalice bien periodicidades distintas, y que marcar un ingreso como
/// cobrado produzca una transaccion de INGRESO y no un gasto.
@Suite("Ingresos recurrentes")
@MainActor
struct RecurringIncomeTests {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(SchemaV3.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func money(_ text: String) -> Decimal { Decimal(string: text)! }

    // MARK: - El campo nuevo

    /// La garantia de compatibilidad: lo que ya estaba sincronizado en CloudKit
    /// antes de la Fase 7 eran facturas, y sin este default se volverian
    /// ingresos al leerlas.
    @Test("Un recurrente sin tipo explicito es un gasto")
    func porDefectoEsGasto() {
        let bill = RecurringBill(name: "Hipoteca", estimatedAmount: money("600.00"))
        #expect(bill.kind == .expense)
        #expect(bill.isIncome == false)
        #expect(bill.kindRaw == "expense")
    }

    /// Ni un raw corrupto ni un traspaso: un recurrente solo puede ser gasto o
    /// ingreso, y el getter lo normaliza en vez de propagar el disparate.
    @Test("Un tipo invalido o un traspaso se leen como gasto")
    func tipoInvalidoCaeAGasto() {
        let bill = RecurringBill(name: "Rara")
        bill.kindRaw = "basura"
        #expect(bill.kind == .expense)

        bill.kind = .transfer
        #expect(bill.kind == .expense)
        #expect(bill.kindRaw == "expense")

        bill.kind = .income
        #expect(bill.kind == .income)
        #expect(bill.isIncome)
    }

    // MARK: - Normalizacion

    @Test("Cada periodicidad sabe cuantas veces cae al ano")
    func ocurrenciasPorAno() {
        #expect(Recurrence.weekly.occurrencesPerYear == 52)
        #expect(Recurrence.biweekly.occurrencesPerYear == 26)
        #expect(Recurrence.monthly.occurrencesPerYear == 12)
        #expect(Recurrence.bimonthly.occurrencesPerYear == 6)
        #expect(Recurrence.quarterly.occurrencesPerYear == 4)
        #expect(Recurrence.semiannual.occurrencesPerYear == 2)
        #expect(Recurrence.annual.occurrencesPerYear == 1)
    }

    /// El caso que justifica todo el resumen: un seguro anual y una nomina
    /// mensual no se pueden comparar hasta que los dos hablan en la misma
    /// unidad.
    @Test("El resumen reparte cada importe por su periodicidad")
    func resumenNormaliza() throws {
        let context = try makeContext()
        let bills = [
            RecurringBill(name: "Hipoteca", estimatedAmount: money("600.00"), recurrence: .monthly),
            RecurringBill(name: "Seguro coche", estimatedAmount: money("600.00"), recurrence: .annual),
            RecurringBill(name: "Nomina", estimatedAmount: money("1800.00"), kind: .income, recurrence: .monthly),
            RecurringBill(name: "Cliente trimestral", estimatedAmount: money("300.00"), kind: .income, recurrence: .quarterly),
        ]
        bills.forEach(context.insert)
        try context.save()

        let resumen = RecurringBillService.summary(bills: bills)

        // 600 al mes + 600 al ano (50 al mes)
        #expect(resumen.monthlyExpense == money("650.00"))
        #expect(resumen.annualExpense == money("7800.00"))
        // 1800 al mes + 300 al trimestre (100 al mes)
        #expect(resumen.monthlyIncome == money("1900.00"))
        #expect(resumen.annualIncome == money("22800.00"))
        #expect(resumen.monthlyNet == money("1250.00"))
        #expect(resumen.annualNet == money("15000.00"))
    }

    @Test("El resumen ignora lo desactivado y lo ya terminado")
    func resumenFiltra() throws {
        let context = try makeContext()
        let ayer = Calendar.current.date(byAdding: .day, value: -1, to: Date())!

        let vigente = RecurringBill(name: "Nomina", estimatedAmount: money("1000.00"), kind: .income)
        let apagada = RecurringBill(name: "Gimnasio", estimatedAmount: money("40.00"), isActive: false)
        let terminada = RecurringBill(
            name: "Prestamo",
            estimatedAmount: money("200.00"),
            startDate: Calendar.current.date(byAdding: .year, value: -3, to: Date())!,
            endDate: ayer
        )
        [vigente, apagada, terminada].forEach(context.insert)
        try context.save()

        let resumen = RecurringBillService.summary(bills: [vigente, apagada, terminada])
        #expect(resumen.monthlyExpense == .zero)
        #expect(resumen.monthlyIncome == money("1000.00"))
    }

    /// Un alquiler que arranca el mes que viene ya es un compromiso: contarlo
    /// solo cuando empieza es descubrirlo el dia 1.
    @Test("El resumen cuenta lo que empieza en el futuro")
    func resumenIncluyeFuturas() throws {
        let context = try makeContext()
        let dentroDeUnMes = Calendar.current.date(byAdding: .month, value: 1, to: Date())!
        let futura = RecurringBill(name: "Alquiler", estimatedAmount: money("700.00"), startDate: dentroDeUnMes)
        context.insert(futura)
        try context.save()

        #expect(RecurringBillService.summary(bills: [futura]).monthlyExpense == money("700.00"))
    }

    // MARK: - Cobrar una ocurrencia

    /// Reproduce lo que hace `QuickAddView` con un `BillPrefill`: el tipo lo
    /// manda el recurrente. Si esto se rompe, una nomina de 1.800 € entra en la
    /// app como un gasto de 1.800 €.
    @Test("Marcar cobrada una nomina crea una transaccion de ingreso")
    func cobrarCreaIngreso() throws {
        let context = try makeContext()
        let cuenta = Account(name: "Corriente", openingBalance: money("1000.00"))
        context.insert(cuenta)
        let categoria = TransactionCategory(name: "Nomina", kind: .income)
        context.insert(categoria)

        let inicio = Calendar.current.date(byAdding: .month, value: -3, to: Date())!
        let nomina = RecurringBill(
            name: "Nomina",
            estimatedAmount: money("1800.00"),
            kind: .income,
            recurrence: .monthly,
            dayOfMonth: 28,
            startDate: inicio,
            account: cuenta,
            category: categoria
        )
        context.insert(nomina)

        let ocurrencia = RecurringBillService.next(1, of: nomina, from: inicio).first!
        let cobro = Transaction(
            date: ocurrencia,
            amount: money("1850.00"),
            kind: nomina.kind,
            note: nomina.name,
            account: cuenta,
            category: categoria
        )
        cobro.recurringBill = nomina
        cobro.occurrenceDate = ocurrencia
        cobro.isRecurringInstance = true
        context.insert(cobro)
        try context.save()

        #expect(cobro.kind == .income)
        #expect(RecurringBillService.isPaid(ocurrencia, of: nomina))
        // El saldo sube: es la comprobacion de que el signo llego hasta el final.
        #expect(cuenta.balance == money("2850.00"))
    }

    // MARK: - Avisos

    @Test("El aviso de un ingreso dice que entra")
    func avisoDeIngreso() throws {
        let context = try makeContext()
        let inicio = Calendar.current.date(byAdding: .day, value: -400, to: Date())!
        let nomina = RecurringBill(
            name: "Nomina",
            estimatedAmount: money("1800.00"),
            kind: .income,
            recurrence: .monthly,
            startDate: inicio,
            reminderDaysBefore: 1
        )
        let luz = RecurringBill(
            name: "Endesa",
            estimatedAmount: money("61.20"),
            recurrence: .monthly,
            startDate: inicio,
            reminderDaysBefore: 1
        )
        [nomina, luz].forEach(context.insert)
        try context.save()

        let plan = NotificationPlanner.plan(bills: [nomina, luz])
        let avisoNomina = plan.first { $0.billID == nomina.id }
        let avisoLuz = plan.first { $0.billID == luz.id }

        #expect(avisoNomina?.body.hasPrefix("Entran ") == true)
        #expect(avisoLuz?.body.hasPrefix("Entran ") == false)
    }

    /// El cupo de 64 pasa a compartirse. Lo que no puede pasar es que los
    /// ingresos desplacen a los gastos por ser de otro tipo: el criterio sigue
    /// siendo la fecha.
    @Test("Gastos e ingresos comparten cupo ordenados por fecha")
    func cupoCompartido() throws {
        let context = try makeContext()
        let inicio = Calendar.current.date(byAdding: .day, value: -400, to: Date())!
        let bills = (1...20).map { indice -> RecurringBill in
            let bill = RecurringBill(
                name: "Recurrente \(indice)",
                estimatedAmount: money("50.00"),
                kind: indice.isMultiple(of: 2) ? .income : .expense,
                recurrence: .weekly,
                startDate: inicio
            )
            context.insert(bill)
            return bill
        }
        try context.save()

        let plan = NotificationPlanner.plan(bills: bills)
        let sinCortar = NotificationPlanner.plan(bills: bills, limit: 1_000)

        #expect(plan.count == NotificationPlanner.systemLimit)
        #expect(plan.map(\.id) == sinCortar.prefix(plan.count).map(\.id))
        // Y en el corte siguen entrando de los dos tipos: si solo hubiera de
        // uno, el orden por fecha no se estaria respetando.
        let ids = Set(plan.map(\.billID))
        #expect(bills.filter { ids.contains($0.id) }.contains { $0.isIncome })
        #expect(bills.filter { ids.contains($0.id) }.contains { !$0.isIncome })
    }

    // MARK: - Copia de seguridad

    @Test("Un ingreso recurrente sobrevive a la ida y vuelta del backup")
    func backupIdaYVuelta() throws {
        let origen = try makeContext()
        let cuenta = Account(name: "Corriente", openingBalance: money("0.00"))
        origen.insert(cuenta)
        let nomina = RecurringBill(
            name: "Nomina",
            estimatedAmount: money("1800.00"),
            kind: .income,
            recurrence: .monthly,
            dayOfMonth: 28,
            account: cuenta
        )
        origen.insert(nomina)
        try origen.save()

        let ficheros = try BackupService.export(context: origen)
        let destino = try makeContext()
        try BackupService.restoreReplacingAll(files: ficheros, context: destino)

        let restaurada = try destino.fetch(FetchDescriptor<RecurringBill>())
        #expect(restaurada.count == 1)
        #expect(restaurada.first?.kind == .income)
    }

    /// Una copia hecha antes de la Fase 7 no trae la columna. Restaurarla tiene
    /// que seguir funcionando y todo lo suyo es gasto.
    @Test("Una copia sin la columna de tipo restaura gastos")
    func backupAntiguoSinColumna() throws {
        let origen = try makeContext()
        let cuenta = Account(name: "Corriente", openingBalance: money("0.00"))
        origen.insert(cuenta)
        origen.insert(RecurringBill(name: "Hipoteca", estimatedAmount: money("600.00"), account: cuenta))
        try origen.save()

        var ficheros = try BackupService.export(context: origen)
        let csv = ficheros[BackupService.FileName.recurringBills]!
        // Quitar la ultima columna de cada linea: es exactamente el fichero que
        // producia la version anterior.
        ficheros[BackupService.FileName.recurringBills] = csv
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { linea in
                guard let corte = linea.lastIndex(of: ",") else { return String(linea) }
                return String(linea[linea.startIndex..<corte])
            }
            .joined(separator: "\n")

        let destino = try makeContext()
        try BackupService.restoreReplacingAll(files: ficheros, context: destino)

        let restaurada = try destino.fetch(FetchDescriptor<RecurringBill>())
        #expect(restaurada.count == 1)
        #expect(restaurada.first?.kind == .expense)
    }
}
