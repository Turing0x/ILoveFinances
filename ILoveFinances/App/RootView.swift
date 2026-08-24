import SwiftUI

struct RootView: View {
    let degradedReason: String?

    var body: some View {
        TabView {
            Tab("Resumen", systemImage: "chart.pie") {
                DashboardView(degradedReason: degradedReason)
            }
            Tab("Movimientos", systemImage: "list.bullet") {
                TransactionListView()
            }
        }
    }
}
