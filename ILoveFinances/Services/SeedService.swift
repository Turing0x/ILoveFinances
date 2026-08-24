import Foundation
import SwiftData

/// Siembra las categorias por defecto y repara los duplicados que CloudKit
/// puede provocar.
///
/// **El problema.** La siembra ingenua es "si no hay categorias, crea las 16".
/// Con CloudKit eso se rompe en el escenario mas normal: instalacion nueva
/// sobre una cuenta de iCloud que YA tiene datos. La app arranca, el store
/// local esta vacio porque el mirroring todavia no ha importado, siembra 16, y
/// un minuto despues llegan las 16 de la nube. Resultado: 32 categorias
/// duplicadas y el grafico del dashboard partido en dos mitades de cada cosa.
///
/// Y no se puede arreglar con `@Attribute(.unique)`, que CloudKit prohibe.
///
/// **La solucion, en tres capas, porque ninguna sola basta:**
/// 1. UUID deterministas en `SeedCategories.json`, para que las dos copias
///    compartan `id` y el duplicado sea REPARABLE en vez de indistinguible.
/// 2. Marca en `NSUbiquitousKeyValueStore`, que viaja con la cuenta de iCloud
///    y sobrevive a la reinstalacion. Evita la mayoria de las carreras, no
///    todas: tarda unos segundos en sincronizar.
/// 3. `reconcile`, que colapsa lo que se haya colado. Es la unica capa que
///    garantiza el resultado.
enum SeedService {

    static let didSeedKey = "didSeedCategoriesV1"

    struct SeedCategory: Decodable {
        let id: UUID
        let name: String
        let symbolName: String
        let colorHex: String
        let kind: TransactionKind
        let sortOrder: Int
    }

    // MARK: - Carga

    static func loadSeedCategories(bundle: Bundle = .main) throws -> [SeedCategory] {
        guard let url = bundle.url(forResource: "SeedCategories", withExtension: "json") else {
            throw SeedError.resourceMissing
        }
        return try JSONDecoder().decode([SeedCategory].self, from: Data(contentsOf: url))
    }

    enum SeedError: Error { case resourceMissing }

    // MARK: - Siembra

    /// Siembra solo si el flag de iCloud no esta puesto Y no hay ya categorias
    /// de sistema. La doble condicion es intencionada: el flag puede no haber
    /// sincronizado todavia, y las categorias presentes son evidencia directa.
    @discardableResult
    static func seedIfNeeded(
        context: ModelContext,
        store: SeedFlagStore = .iCloud,
        bundle: Bundle = .main
    ) throws -> Int {
        if store.didSeed { return 0 }

        let existing = try context.fetch(
            FetchDescriptor<TransactionCategory>(predicate: #Predicate { $0.isSystem })
        )
        guard existing.isEmpty else {
            store.didSeed = true
            return 0
        }

        let seeds = try loadSeedCategories(bundle: bundle)
        for seed in seeds {
            context.insert(
                TransactionCategory(
                    id: seed.id,
                    name: seed.name,
                    symbolName: seed.symbolName,
                    colorHex: seed.colorHex,
                    kind: seed.kind,
                    isSystem: true,
                    sortOrder: seed.sortOrder
                )
            )
        }
        try context.save()
        store.didSeed = true
        return seeds.count
    }

    // MARK: - Reconciliacion

    /// Colapsa las categorias de sistema duplicadas por `id`.
    ///
    /// Conserva la mas antigua por `createdAt` —criterio estable y
    /// determinista, para que dos dispositivos lleguen a la misma
    /// superviviente— repunta a ella las transacciones de las demas y borra el
    /// resto. Idempotente: se puede llamar en cada arranque sin efecto si no
    /// hay nada que reparar.
    @discardableResult
    static func reconcile(context: ModelContext) throws -> Int {
        let system = try context.fetch(
            FetchDescriptor<TransactionCategory>(predicate: #Predicate { $0.isSystem })
        )
        let grouped = Dictionary(grouping: system, by: \.id)

        var removed = 0
        for (_, duplicates) in grouped where duplicates.count > 1 {
            let ordered = duplicates.sorted { $0.createdAt < $1.createdAt }
            guard let survivor = ordered.first else { continue }

            for extra in ordered.dropFirst() {
                // Repuntar ANTES de borrar: el deleteRule es .nullify, asi que
                // borrar primero dejaria esas transacciones sin categoria.
                for transaction in extra.transactions ?? [] {
                    transaction.category = survivor
                }
                context.delete(extra)
                removed += 1
            }
        }

        if removed > 0 { try context.save() }
        return removed
    }
}

/// Donde vive la marca de "ya sembrado".
///
/// Se inyecta para poder probar la siembra sin tocar el iCloud del que ejecuta
/// los tests.
final class SeedFlagStore {
    private let read: () -> Bool
    private let write: (Bool) -> Void

    init(read: @escaping () -> Bool, write: @escaping (Bool) -> Void) {
        self.read = read
        self.write = write
    }

    var didSeed: Bool {
        get { read() }
        set { write(newValue) }
    }

    /// Almacen clave-valor de iCloud: viaja con la cuenta y sobrevive a la
    /// reinstalacion, que es justo lo que hace falta aqui. `UserDefaults` no
    /// serviria: se borra al desinstalar y la app volveria a sembrar.
    static let iCloud = SeedFlagStore(
        read: {
            let store = NSUbiquitousKeyValueStore.default
            store.synchronize()
            return store.bool(forKey: SeedService.didSeedKey)
        },
        write: { value in
            let store = NSUbiquitousKeyValueStore.default
            store.set(value, forKey: SeedService.didSeedKey)
            store.synchronize()
        }
    )

    /// En memoria, para tests.
    static func inMemory(initial: Bool = false) -> SeedFlagStore {
        var value = initial
        return SeedFlagStore(read: { value }, write: { value = $0 })
    }
}
