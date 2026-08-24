import Foundation
import Testing
@testable import ILoveFinances

/// PLAN.md seccion 7 Fase 2: "Doy de alta la hipoteca y veo las proximas 6
/// ocurrencias correctamente calculadas."
///
/// El motor de ocurrencias no toca base de datos ni interfaz, asi que se puede
/// probar entero. Los casos elegidos son los que rompen una implementacion
/// ingenua: el dia 31 en febrero, el fin de mes en las quincenales, y el 29 de
/// febrero de un bisiesto.
@Suite("Ocurrencias de facturas recurrentes")
struct RecurringBillOccurrenceTests {

    // MARK: - Utilidades

    /// Calendario FIJO: gregoriano, hora UTC, locale POSIX. Sin esto los tests
    /// pasarian o fallarian segun la zona horaria de quien los ejecuta.
    private static var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }()

    private static func date(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = calendar.locale
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: text)!
    }

    private static func text(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = calendar.locale
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func next(
        _ count: Int,
        recurrence: Recurrence,
        day: Int,
        start: String,
        from: String,
        end: String? = nil
    ) -> [String] {
        let bill = RecurringBill(
            name: "Prueba",
            recurrence: recurrence,
            dayOfMonth: day,
            startDate: date(start),
            endDate: end.map(date)
        )
        return RecurringBillService
            .next(count, of: bill, from: date(from), calendar: calendar)
            .map(text)
    }

    // MARK: - Tabla de periodicidades

    @Test("Cada periodicidad genera las fechas esperadas", arguments: [
        // Mensual del dia 1: el caso comun.
        (Recurrence.monthly, 1, "2026-01-01", "2026-01-01",
         ["2026-01-01", "2026-02-01", "2026-03-01"]),
        // Dia 31: febrero se RECORTA, no se salta, y marzo vuelve al 31.
        // Contar siempre desde el origen es lo que evita quedarse en el 28.
        (Recurrence.monthly, 31, "2026-01-31", "2026-01-01",
         ["2026-01-31", "2026-02-28", "2026-03-31"]),
        // Bisiesto: 2028 si tiene 29 de febrero.
        (Recurrence.monthly, 31, "2028-01-31", "2028-01-01",
         ["2028-01-31", "2028-02-29", "2028-03-31"]),
        (Recurrence.bimonthly, 15, "2026-01-15", "2026-01-01",
         ["2026-01-15", "2026-03-15", "2026-05-15"]),
        (Recurrence.quarterly, 10, "2026-02-10", "2026-01-01",
         ["2026-02-10", "2026-05-10", "2026-08-10"]),
        (Recurrence.semiannual, 5, "2026-03-05", "2026-01-01",
         ["2026-03-05", "2026-09-05", "2027-03-05"]),
        // Anual arrancando un 29 de febrero: los anos normales dan 28.
        (Recurrence.annual, 29, "2028-02-29", "2028-01-01",
         ["2028-02-29", "2029-02-28", "2030-02-28"]),
        // Semanal y quincenal heredan el dia de la semana y cruzan el fin de
        // mes sin enterarse: `dayOfMonth` no interviene.
        (Recurrence.weekly, 1, "2026-01-29", "2026-01-01",
         ["2026-01-29", "2026-02-05", "2026-02-12"]),
        (Recurrence.biweekly, 1, "2026-01-22", "2026-01-01",
         ["2026-01-22", "2026-02-05", "2026-02-19"]),
    ])
    func periodicidades(caso: (Recurrence, Int, String, String, [String])) {
        let (recurrence, day, start, from, esperado) = caso
        let obtenido = Self.next(esperado.count, recurrence: recurrence, day: day, start: start, from: from)
        #expect(obtenido == esperado)
    }

    // MARK: - Bordes

    @Test("La primera ocurrencia nunca cae antes de la fecha de inicio")
    func nadaAntesDelInicio() {
        // Alta el 20 de enero con cargo el dia 5: enero ya paso, empieza en
        // febrero.
        let obtenido = Self.next(2, recurrence: .monthly, day: 5, start: "2026-01-20", from: "2026-01-01")
        #expect(obtenido == ["2026-02-05", "2026-03-05"])
    }

    @Test("La fecha de fin es inclusiva y corta las siguientes")
    func fechaDeFinInclusiva() {
        let obtenido = Self.next(
            6, recurrence: .monthly, day: 10,
            start: "2026-01-10", from: "2026-01-01", end: "2026-03-10"
        )
        #expect(obtenido == ["2026-01-10", "2026-02-10", "2026-03-10"])
    }

    @Test("Una factura desactivada no genera ninguna ocurrencia")
    func desactivadaNoGeneraNada() {
        let bill = RecurringBill(
            name: "Gimnasio",
            recurrence: .monthly,
            dayOfMonth: 1,
            startDate: Self.date("2026-01-01"),
            isActive: false
        )
        let obtenido = RecurringBillService.next(6, of: bill, from: Self.date("2026-01-01"), calendar: Self.calendar)
        #expect(obtenido.isEmpty)
    }

    @Test("La hipoteca da seis ocurrencias correctas: criterio de cierre")
    func seisDeLaHipoteca() {
        let obtenido = Self.next(6, recurrence: .monthly, day: 5, start: "2026-01-05", from: "2026-01-01")
        #expect(obtenido == [
            "2026-01-05", "2026-02-05", "2026-03-05",
            "2026-04-05", "2026-05-05", "2026-06-05",
        ])
    }

    @Test("Consultar un intervalo lejano no itera desde el origen ni pierde fechas")
    func intervaloLejano() {
        let bill = RecurringBill(
            name: "Seguro",
            recurrence: .monthly,
            dayOfMonth: 31,
            startDate: Self.date("2010-01-31")
        )
        let interval = DateInterval(start: Self.date("2026-02-01"), end: Self.date("2026-05-01"))
        let obtenido = RecurringBillService
            .occurrences(of: bill, in: interval, calendar: Self.calendar)
            .map(Self.text)
        #expect(obtenido == ["2026-02-28", "2026-03-31", "2026-04-30"])
    }

    @Test("El intervalo es semiabierto: el limite superior queda fuera")
    func intervaloSemiabierto() {
        let bill = RecurringBill(
            name: "Cuota",
            recurrence: .monthly,
            dayOfMonth: 1,
            startDate: Self.date("2026-01-01")
        )
        let interval = DateInterval(start: Self.date("2026-01-01"), end: Self.date("2026-03-01"))
        let obtenido = RecurringBillService
            .occurrences(of: bill, in: interval, calendar: Self.calendar)
            .map(Self.text)
        #expect(obtenido == ["2026-01-01", "2026-02-01"])
    }
}
