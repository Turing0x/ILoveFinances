import Foundation
import SwiftData
import Testing
@testable import ILoveFinances

/// La carrera que este test simula es real y ocurre en el escenario mas normal:
/// instalacion nueva sobre una cuenta de iCloud que ya tiene datos. La app
/// siembra porque el store local esta vacio, y un minuto despues llegan las
/// categorias de la nube.
@Suite("Siembra y reconciliacion de categorias")
@MainActor
struct SeedReconciliationTests {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(SchemaV3.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    @Test("El fichero de siembra trae 16 categorias con UUID distintos")
    func ficheroDeSiembra() throws {
        let seeds = try SeedService.loadSeedCategories()
        #expect(seeds.count == 16)
        #expect(Set(seeds.map(\.id)).count == 16)
        #expect(seeds.filter { $0.kind == .expense }.count == 10)
        #expect(seeds.filter { $0.kind == .income }.count == 6)
    }

    @Test("Sembrar dos veces seguidas no duplica")
    func sembrarEsIdempotente() throws {
        let context = try makeContext()
        let store = SeedFlagStore.inMemory()

        let primera = try SeedService.seedIfNeeded(context: context, store: store)
        let segunda = try SeedService.seedIfNeeded(context: context, store: store)

        #expect(primera == 16)
        #expect(segunda == 0)
        #expect(try context.fetchCount(FetchDescriptor<TransactionCategory>()) == 16)
    }

    /// Simula lo que hace el mirroring de CloudKit al importar: mete OTRA copia
    /// de las mismas categorias, con el mismo `id` y fecha posterior.
    ///
    /// No vale llamar dos veces a `seedIfNeeded` para provocar el duplicado:
    /// su segunda condicion (ya hay categorias de sistema) lo corta, que es
    /// justo lo que debe hacer. El duplicado real no lo crea la siembra, lo
    /// trae la nube.
    private func simulateCloudImport(into context: ModelContext) throws {
        for seed in try SeedService.loadSeedCategories() {
            let copia = TransactionCategory(
                id: seed.id, name: seed.name, symbolName: seed.symbolName,
                colorHex: seed.colorHex, kind: seed.kind,
                isSystem: true, sortOrder: seed.sortOrder
            )
            copia.createdAt = Date().addingTimeInterval(60)
            context.insert(copia)
        }
        try context.save()
    }

    /// El caso que importa: instalacion nueva sobre una cuenta de iCloud que ya
    /// tiene datos. La app siembra porque el store local esta vacio, y despues
    /// llegan las categorias de la nube.
    @Test("Reconciliar colapsa los duplicados de la carrera con CloudKit")
    func reconcileArreglaLaCarrera() throws {
        let context = try makeContext()

        try SeedService.seedIfNeeded(context: context, store: .inMemory())
        try simulateCloudImport(into: context)
        #expect(try context.fetchCount(FetchDescriptor<TransactionCategory>()) == 32)

        let eliminadas = try SeedService.reconcile(context: context)

        #expect(eliminadas == 16)
        #expect(try context.fetchCount(FetchDescriptor<TransactionCategory>()) == 16)
    }

    /// Lo que haria inaceptable la reparacion: que al borrar el duplicado las
    /// transacciones se quedaran sin categoria. El deleteRule es .nullify, asi
    /// que hay que repuntar ANTES de borrar. Por eso el gasto se cuelga de la
    /// copia que va a desaparecer, no de la que sobrevive.
    @Test("Reconciliar no deja transacciones sin categoria")
    func reconcileRepuntaLasTransacciones() throws {
        let context = try makeContext()

        try SeedService.seedIfNeeded(context: context, store: .inMemory())
        try simulateCloudImport(into: context)

        let vivienda = try context.fetch(
            FetchDescriptor<TransactionCategory>(predicate: #Predicate { $0.name == "Vivienda" })
        ).sorted { $0.createdAt < $1.createdAt }
        #expect(vivienda.count == 2)

        let gasto = Transaction(amount: Decimal(string: "80.00")!, kind: .expense, category: vivienda[1])
        context.insert(gasto)
        try context.save()

        try SeedService.reconcile(context: context)

        #expect(gasto.category != nil)
        #expect(gasto.category?.name == "Vivienda")
        #expect(try context.fetchCount(FetchDescriptor<TransactionCategory>()) == 16)
    }

    @Test("Reconciliar sobre una base sana no toca nada")
    func reconcileEsIdempotente() throws {
        let context = try makeContext()
        try SeedService.seedIfNeeded(context: context, store: .inMemory())

        #expect(try SeedService.reconcile(context: context) == 0)
        #expect(try SeedService.reconcile(context: context) == 0)
        #expect(try context.fetchCount(FetchDescriptor<TransactionCategory>()) == 16)
    }
}
