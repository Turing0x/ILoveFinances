import SwiftData
import SwiftUI

@main
struct ILoveFinancesApp: App {
    private let container: ModelContainer
    private let degradedReason: String?

    init() {
        let made = AppContainer.make()
        container = made.container
        degradedReason = made.degradedReason
    }

    var body: some Scene {
        WindowGroup {
            RootView(degradedReason: degradedReason)
                .task {
                    AppContainer.bootstrap(context: container.mainContext)
                }
        }
        .modelContainer(container)
    }
}
