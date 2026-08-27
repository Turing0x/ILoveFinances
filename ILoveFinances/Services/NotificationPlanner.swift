import Foundation

/// Decide QUE avisos deben existir. No programa nada: de eso se encarga
/// `NotificationService`.
///
/// La separacion no es ceremonia. La decision es una funcion pura sobre
/// valores y se puede probar entera —incluido el tope de 64, que es un criterio
/// de cierre de la fase—; el efecto secundario que habla con
/// `UNUserNotificationCenter` se queda en unas pocas lineas sin logica.
enum NotificationPlanner {

    /// Cupo de iOS: 64 notificaciones locales PENDIENTES por app. Al pasarse,
    /// el sistema descarta las sobrantes EN SILENCIO — no hay error, solo
    /// avisos que no llegan. De ahi que el corte sea explicito aqui y tenga
    /// test propio.
    ///
    /// Desde la Fase 7 el cupo lo comparten gastos e ingresos. No se reparte por
    /// tipo: se ordena por fecha y se corta, asi que lo que se pierde es siempre
    /// lo mas lejano — que es lo que la siguiente reprogramacion recupera.
    static let systemLimit = 64

    /// Ventana deslizante. Programar todo el futuro de una factura indefinida
    /// agota el cupo con una sola; 60 dias cubren de sobra hasta la siguiente
    /// apertura de la app, que es cuando se reprograma.
    static let defaultWindowDays = 60

    /// Hora del aviso. Fija y por la manana: una factura que se carga hoy
    /// interesa saberla al empezar el dia, no a medianoche.
    static let hour = 9

    struct Planned: Equatable, Identifiable {
        let id: String
        let billID: UUID
        let occurrenceDate: Date
        let fireDate: Date
        let title: String
        let body: String
    }

    static func plan(
        bills: [RecurringBill],
        from now: Date = Date(),
        windowDays: Int = defaultWindowDays,
        limit: Int = systemLimit,
        calendar: Calendar = .current
    ) -> [Planned] {
        let upcoming = RecurringBillService.upcoming(
            bills: bills,
            from: now,
            days: windowDays,
            includingPaid: false,     // lo ya pagado no se avisa
            calendar: calendar
        )

        let planned = upcoming.compactMap { item -> Planned? in
            guard let fireDate = fireDate(for: item, calendar: calendar) else { return nil }
            // Un aviso en el pasado no se puede programar: iOS lo dispararia al
            // instante o lo descartaria, y en los dos casos gastaria cupo.
            guard fireDate > now else { return nil }

            return Planned(
                id: item.id,
                billID: item.bill.id,
                occurrenceDate: item.date,
                fireDate: fireDate,
                title: item.bill.name,
                body: body(for: item, calendar: calendar)
            )
        }

        // Ordenar por fecha ANTES de cortar: si sobra cupo, lo que se pierde es
        // lo mas lejano, que es lo que menos duele y lo que la siguiente
        // reprogramacion recupera.
        return Array(planned.sorted { $0.fireDate < $1.fireDate }.prefix(max(0, limit)))
    }

    private static func fireDate(
        for item: RecurringBillService.Upcoming,
        calendar: Calendar
    ) -> Date? {
        let daysBefore = max(0, item.bill.reminderDaysBefore)
        guard let day = calendar.date(byAdding: .day, value: -daysBefore, to: item.date) else { return nil }
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)
    }

    private static func body(
        for item: RecurringBillService.Upcoming,
        calendar: Calendar
    ) -> String {
        let importe = Money.formatted(item.bill.estimatedAmount)
        let cantidad = item.bill.isVariableAmount ? "~\(importe)" : importe
        let dia = item.date.formatted(.dateTime.day().month(.wide))
        let cuenta = item.bill.account.map { " · \($0.name)" } ?? ""
        // Un ingreso no "se paga": el aviso dice que ENTRA, que es informacion
        // distinta y no debe leerse como algo pendiente de hacer.
        let verbo = item.bill.isIncome ? "Entran " : ""
        return "\(verbo)\(cantidad) el \(dia)\(cuenta)"
    }
}
