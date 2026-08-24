import SwiftData
import SwiftUI

struct RootView: View {
    let degradedReason: String?

    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            Tab("Resumen", systemImage: "chart.pie") {
                DashboardView(degradedReason: degradedReason)
            }
            Tab("Movimientos", systemImage: "list.bullet") {
                TransactionListView()
            }
            Tab("Facturas", systemImage: "calendar.badge.clock") {
                BillsView()
            }
            Tab("Compras", systemImage: "cart") {
                PurchasesView()
            }
        }
        // Los avisos se reprograman al arrancar y en cada vuelta a primer
        // plano: la ventana es deslizante (60 dias) y solo avanza si alguien la
        // empuja. Es ademas lo que retira los de las facturas que ya se pagaron
        // desde otro dispositivo.
        .task { NotificationService.shared.reschedule(context: context) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { NotificationService.shared.reschedule(context: context) }
        }
    }
}
