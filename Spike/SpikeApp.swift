import SwiftData
import SwiftUI

@main
struct SpikeApp: App {

    /// Contenedor DESECHABLE, nunca el de la app. El esquema de CloudKit en
    /// Production es permanente: CD_MoneyProbe no debe acabar en
    /// iCloud.dev.threedots.ilovefinances, que tiene que llegar virgen a la
    /// Fase 1.
    static let cloudKitContainerID = "iCloud.dev.threedots.ilovefinances.spike"

    let container: ModelContainer

    /// Si el contenedor de CloudKit no arranca, la app cae a un store local.
    /// El fallback es RUIDOSO a proposito: sembrar contra un store local
    /// creyendo que sincroniza daria un "todo OK" que no prueba nada.
    let degradedReason: String?

    init() {
        let schema = Schema([MoneyProbe.self])
        do {
            container = try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(
                    schema: schema,
                    cloudKitDatabase: .private(SpikeApp.cloudKitContainerID)
                )
            )
            degradedReason = nil
        } catch {
            container = try! ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, cloudKitDatabase: .none)
            )
            degradedReason = String(describing: error)
        }
    }

    var body: some Scene {
        WindowGroup {
            SpikeView(degradedReason: degradedReason)
        }
        .modelContainer(container)
    }
}
