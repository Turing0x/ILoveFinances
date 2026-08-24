import Foundation

/// Calculo de las ocurrencias de una factura recurrente.
///
/// Funciones PURAS sobre valores, sin `ModelContext` (PLAN.md seccion 2): son
/// baratas de probar y no hay estado que pueda desincronizarse. Nada de lo que
/// se calcula aqui se persiste — las ocurrencias futuras no existen en base de
/// datos, se derivan cada vez de `recurrence` + `dayOfMonth` + `startDate`.
enum RecurringBillService {

    // MARK: - Ocurrencias

    /// Ocurrencias dentro de un intervalo SEMIABIERTO `[inicio, fin)`, mismo
    /// convenio que `DatePeriod.interval`.
    static func occurrences(
        of bill: RecurringBill,
        in interval: DateInterval,
        calendar: Calendar = .current
    ) -> [Date] {
        generate(
            of: bill,
            notBefore: interval.start,
            before: interval.end,
            limit: hardLimit,
            calendar: calendar
        )
    }

    /// Las `count` siguientes a partir de `date`, sin tope de calendario.
    ///
    /// Es lo que ve el usuario debajo del formulario al dar de alta la
    /// hipoteca: si estas seis salen bien, la periodicidad esta bien puesta.
    static func next(
        _ count: Int,
        of bill: RecurringBill,
        from date: Date = Date(),
        calendar: Calendar = .current
    ) -> [Date] {
        generate(
            of: bill,
            notBefore: calendar.startOfDay(for: date),
            before: nil,
            limit: count,
            calendar: calendar
        )
    }

    /// Tope de seguridad: una factura semanal indefinida consultada a diez anos
    /// vista genera ~520 fechas. El limite evita que un intervalo absurdo
    /// (`.distantFuture`) cuelgue la interfaz.
    private static let hardLimit = 2_000

    /// Generador unico del que salen las dos funciones publicas.
    ///
    /// - `notBefore`: inclusive.
    /// - `before`: exclusivo; `nil` = sin tope.
    private static func generate(
        of bill: RecurringBill,
        notBefore: Date,
        before: Date?,
        limit: Int,
        calendar: Calendar
    ) -> [Date] {
        guard bill.isActive, limit > 0 else { return [] }

        let start = calendar.startOfDay(for: bill.startDate)
        let floorDate = max(calendar.startOfDay(for: notBefore), start)
        let endDate = bill.endDate.map { calendar.startOfDay(for: $0) }

        // La factura ya termino antes de la ventana que se consulta.
        if let endDate, endDate < floorDate { return [] }

        var result: [Date] = []
        var index = firstIndex(of: bill, notBefore: floorDate, start: start, calendar: calendar)
        var guardRail = 0

        while result.count < limit {
            guardRail += 1
            if guardRail > hardLimit * 2 { break }

            guard let candidate = occurrence(of: bill, index: index, start: start, calendar: calendar) else { break }
            index += 1

            if candidate < floorDate { continue }
            if let before, candidate >= before { break }
            // `endDate` es INCLUSIVA: una factura que acaba el 31 de diciembre
            // tiene ocurrencia ese dia.
            if let endDate, candidate > endDate { break }

            result.append(candidate)
        }
        return result
    }

    /// Ocurrencia numero `index` (0 = la primera), contada siempre desde
    /// `startDate`.
    ///
    /// Contar desde el origen y no ir sumando sobre la anterior es lo que evita
    /// la deriva del dia 31: `enero 31 + 1 mes` da el 28 de febrero, y sumarle
    /// otro mes daria el 28 de marzo en vez del 31.
    private static func occurrence(
        of bill: RecurringBill,
        index: Int,
        start: Date,
        calendar: Calendar
    ) -> Date? {
        if let dayStep = bill.recurrence.dayStep {
            // Semanal y quincenal heredan el dia de la semana de `startDate`,
            // asi que `dayOfMonth` no pinta nada aqui.
            return calendar.date(byAdding: .day, value: index * dayStep, to: start)
        }

        let monthStep = bill.recurrence.monthStep ?? 1
        guard let anchor = calendar.date(byAdding: .month, value: index * monthStep, to: start) else { return nil }
        return dayInMonth(of: anchor, day: bill.dayOfMonth, calendar: calendar)
    }

    /// El dia pedido dentro del mes de `anchor`, RECORTADO a la longitud real
    /// del mes: dia 31 en febrero es el 28 (o el 29), no el 3 de marzo ni un
    /// mes saltado.
    private static func dayInMonth(of anchor: Date, day: Int, calendar: Calendar) -> Date? {
        guard let range = calendar.range(of: .day, in: .month, for: anchor) else { return nil }
        var components = calendar.dateComponents([.year, .month], from: anchor)
        components.day = min(max(day, 1), range.count)
        return calendar.date(from: components)
    }

    /// Salto directo al entorno de la ventana pedida, para no iterar mes a mes
    /// desde 2010 cuando se preguntan las facturas de este trimestre.
    ///
    /// Se retrocede un paso a proposito: el recorte de dia puede hacer que la
    /// ocurrencia calculada caiga un poco antes de lo que sugiere la aritmetica
    /// de meses, y perder la primera fecha seria peor que evaluar una de mas.
    private static func firstIndex(
        of bill: RecurringBill,
        notBefore: Date,
        start: Date,
        calendar: Calendar
    ) -> Int {
        guard notBefore > start else { return 0 }

        if let dayStep = bill.recurrence.dayStep {
            let days = calendar.dateComponents([.day], from: start, to: notBefore).day ?? 0
            return max(0, days / dayStep - 1)
        }

        let monthStep = bill.recurrence.monthStep ?? 1
        let months = calendar.dateComponents([.month], from: start, to: notBefore).month ?? 0
        return max(0, months / monthStep - 1)
    }

    // MARK: - Pagos

    /// La transaccion que paga esa ocurrencia, si existe.
    ///
    /// Coincidencia EXACTA por `occurrenceDate`, que es el motivo de que ese
    /// campo exista: pagar la factura de febrero el 12 de marzo sigue marcando
    /// febrero. El respaldo por ventana solo cubre pagos sin `occurrenceDate`
    /// —creados a mano o importados de un CSV— para que el historial de una
    /// factura antigua no salga vacio.
    static func payment(
        for occurrence: Date,
        of bill: RecurringBill,
        calendar: Calendar = .current
    ) -> Transaction? {
        let day = calendar.startOfDay(for: occurrence)
        let payments = bill.payments ?? []

        if let exact = payments.first(where: { payment in
            guard let marked = payment.occurrenceDate else { return false }
            return calendar.startOfDay(for: marked) == day
        }) {
            return exact
        }

        let halfWindow = max(1, bill.recurrence.approximateDays / 2)
        return payments.first { payment in
            guard payment.occurrenceDate == nil else { return false }
            let diff = calendar.dateComponents(
                [.day],
                from: day,
                to: calendar.startOfDay(for: payment.date)
            ).day ?? Int.max
            return abs(diff) <= halfWindow
        }
    }

    static func isPaid(_ occurrence: Date, of bill: RecurringBill, calendar: Calendar = .current) -> Bool {
        payment(for: occurrence, of: bill, calendar: calendar) != nil
    }

    // MARK: - Proximas, para la interfaz y para los avisos

    struct Upcoming: Identifiable {
        let bill: RecurringBill
        let date: Date
        let payment: Transaction?

        var id: String { RecurringBillService.key(bill: bill, occurrence: date) }
        var isPaid: Bool { payment != nil }
    }

    /// Ocurrencias de todas las facturas en los proximos `days` dias,
    /// ordenadas por fecha. Fuente unica de la seccion "Proximas" de Facturas,
    /// de la del dashboard y del planificador de avisos: si las tres miran lo
    /// mismo, no pueden contradecirse.
    static func upcoming(
        bills: [RecurringBill],
        from now: Date = Date(),
        days: Int,
        includingPaid: Bool = true,
        calendar: Calendar = .current
    ) -> [Upcoming] {
        let start = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: days, to: start) else { return [] }
        let interval = DateInterval(start: start, end: end)

        var result: [Upcoming] = []
        for bill in bills {
            for date in occurrences(of: bill, in: interval, calendar: calendar) {
                let paid = payment(for: date, of: bill, calendar: calendar)
                if paid != nil && !includingPaid { continue }
                result.append(Upcoming(bill: bill, date: date, payment: paid))
            }
        }
        return result.sorted { ($0.date, $0.bill.name) < ($1.date, $1.bill.name) }
    }

    // MARK: - Identidad de una ocurrencia

    /// `bill-<uuid>-<yyyy-MM-dd>`. Determinista y estable entre ejecuciones:
    /// permite recalcular el plan de avisos entero y compararlo con lo que ya
    /// esta programado sin llevar contabilidad de identificadores.
    static func key(bill: RecurringBill, occurrence: Date) -> String {
        "bill-\(bill.id.uuidString)-\(dayFormatter.string(from: occurrence))"
    }

    static let keyPrefix = "bill-"

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
