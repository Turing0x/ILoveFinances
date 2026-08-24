import Foundation
import SwiftData
import UserNotifications

/// Programa en `UNUserNotificationCenter` lo que decide `NotificationPlanner`.
///
/// Aqui no hay logica de negocio a proposito: quien decide que avisos deben
/// existir es el planificador, que es puro y tiene tests. Esto solo sincroniza
/// el estado del sistema con esa decision.
///
/// **Idempotente.** `sync` compara lo pendiente con el plan y solo toca la
/// diferencia. Por eso se puede llamar en cada arranque, en cada vuelta a
/// primer plano y despues de cada edicion sin duplicar avisos ni dejar
/// huerfanos — que es justo el criterio de cierre "cambiar la periodicidad
/// reprograma sin dejar huerfanas".
@MainActor
final class NotificationService {

    static let shared = NotificationService()

    private let center: UNUserNotificationCenter
    private var authorizationAsked = false

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    // MARK: - Permiso

    /// Sin badge: un numero rojo permanente en el icono por una factura que
    /// llega dentro de tres dias es ruido, no informacion.
    func requestAuthorizationIfNeeded() async {
        guard !authorizationAsked else { return }
        authorizationAsked = true
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    // MARK: - Reprogramacion

    /// Lee las facturas, planifica y sincroniza. Punto de entrada unico: el
    /// arranque, la vuelta a primer plano y cada edicion de una factura llaman
    /// aqui, para que no haya dos caminos que puedan divergir.
    func reschedule(context: ModelContext) {
        let bills = (try? context.fetch(FetchDescriptor<RecurringBill>())) ?? []
        let plan = NotificationPlanner.plan(bills: bills)
        Task { await sync(plan: plan) }
    }

    func sync(plan: [NotificationPlanner.Planned]) async {
        await requestAuthorizationIfNeeded()

        let pending = await center.pendingNotificationRequests()
        let pendingIDs = Set(
            pending.map(\.identifier).filter { $0.hasPrefix(RecurringBillService.keyPrefix) }
        )
        let plannedIDs = Set(plan.map(\.id))

        // Sobrantes: facturas borradas, desactivadas, ya pagadas o con la fecha
        // cambiada. Si no se retiran, el usuario recibe el aviso de una factura
        // que ya no existe.
        let obsolete = pendingIDs.subtracting(plannedIDs)
        if !obsolete.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: Array(obsolete))
        }

        for planned in plan where !pendingIDs.contains(planned.id) {
            try? await center.add(request(for: planned))
        }
    }

    /// Retira los avisos de UNA factura. Se usa al borrarla, cuando ya no se
    /// puede planificar nada sobre ella porque el objeto va a desaparecer.
    func cancelAll(for billID: UUID, pendingFrom center: UNUserNotificationCenter? = nil) async {
        let target = center ?? self.center
        let prefix = "\(RecurringBillService.keyPrefix)\(billID.uuidString)-"
        let pending = await target.pendingNotificationRequests()
        let ids = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        if !ids.isEmpty {
            target.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    private func request(for planned: NotificationPlanner.Planned) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = planned.title
        content.body = planned.body
        content.sound = .default

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: planned.fireDate
        )
        // `repeats: false`: cada ocurrencia tiene su propio aviso con fecha
        // absoluta. Un disparador repetitivo no sabria saltarse las pagadas.
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        return UNNotificationRequest(identifier: planned.id, content: content, trigger: trigger)
    }

    #if DEBUG
    /// Recuento de avisos pendientes. Sirve para comprobar en el dispositivo
    /// que con 20 facturas nunca se pasa de 64 (PLAN.md seccion 8).
    func pendingCount() async -> Int {
        await center.pendingNotificationRequests().count
    }
    #endif
}
