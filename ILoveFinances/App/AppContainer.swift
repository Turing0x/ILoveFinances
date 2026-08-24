import Foundation
import SwiftData

/// Construccion del `ModelContainer` y arranque de la base de datos.
enum AppContainer {

    static let cloudKitContainerID = "iCloud.dev.threedots.ilovefinances"

    /// Contenedor con CloudKit. Si no arranca, cae a uno solo local y deja
    /// dicho por que: seguir en silencio significaria que el usuario mete
    /// meses de datos creyendo que se sincronizan.
    static func make() -> (container: ModelContainer, degradedReason: String?) {
        let schema = Schema(SchemaV1.models)
        do {
            let container = try ModelContainer(
                for: schema,
                migrationPlan: ILoveFinancesMigrationPlan.self,
                configurations: ModelConfiguration(
                    schema: schema,
                    cloudKitDatabase: .private(cloudKitContainerID)
                )
            )
            return (container, nil)
        } catch {
            let fallback = try! ModelContainer(
                for: schema,
                migrationPlan: ILoveFinancesMigrationPlan.self,
                configurations: ModelConfiguration(schema: schema, cloudKitDatabase: .none)
            )
            return (fallback, String(describing: error))
        }
    }

    /// Se llama en cada arranque, en este orden.
    ///
    /// `reconcile` va DESPUES y siempre, no solo cuando se ha sembrado: repara
    /// los duplicados que produce la carrera con el mirroring de CloudKit, y
    /// esa carrera ocurre precisamente en los arranques en los que no se
    /// siembra. Ver SeedService.
    @MainActor
    static func bootstrap(context: ModelContext) {
        do {
            try SeedService.seedIfNeeded(context: context)
            try SeedService.reconcile(context: context)
        } catch {
            // Un fallo aqui no debe impedir abrir la app: sin categorias se
            // puede seguir apuntando gastos, y el siguiente arranque reintenta.
            print("Arranque: fallo al sembrar o reconciliar — \(error)")
        }
    }
}
