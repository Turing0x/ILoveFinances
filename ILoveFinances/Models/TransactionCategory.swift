import Foundation
import SwiftData

/// Categoria de gasto o de ingreso.
///
/// Se llama `TransactionCategory` y no `Category` porque el runtime de
/// Objective-C ya exporta un tipo `Category` (objc/runtime.h), y la colision
/// hace ambiguo cualquier uso generico como `FetchDescriptor<Category>` en
/// cuanto ese header entra en ambito. Renombrarlo ahora es gratis; despues de
/// que existan datos en Production seria imposible: el RecordType de CloudKit
/// no se puede borrar ni renombrar.
@Model
final class TransactionCategory {
    var id: UUID = UUID()
    var name: String = ""
    var symbolName: String = "tag"     // SF Symbol
    var colorHex: String = "#888888"
    /// Categoria de gasto o de ingreso.
    var kindRaw: String = TransactionKind.expense.rawValue
    /// Las sembradas al primer arranque. No se pueden borrar desde la UI.
    var isSystem: Bool = false
    var sortOrder: Int = 0
    var createdAt: Date = Date()

    /// Jerarquia por ID plano, NO por relacion auto-referencial.
    /// `parent` + `children` es el patron natural en SwiftData, pero las
    /// relaciones de una entidad consigo misma son fragiles bajo
    /// NSPersistentCloudKitContainer. Con dos niveles fijos, un UUID sale
    /// mas barato. Precio: al borrar una padre hay que poner a nil el
    /// parentID de sus hijas a mano, no hay deleteRule que lo haga.
    var parentID: UUID?

    @Relationship(deleteRule: .nullify, inverse: \Transaction.category)
    var transactions: [Transaction]? = []

    /// Inversa de `ImportRule.category`, obligatoria para CloudKit.
    @Relationship(deleteRule: .nullify, inverse: \ImportRule.category)
    var importRules: [ImportRule]? = []

    init(
        id: UUID = UUID(),
        name: String = "",
        symbolName: String = "tag",
        colorHex: String = "#888888",
        kind: TransactionKind = .expense,
        isSystem: Bool = false,
        sortOrder: Int = 0,
        parentID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.symbolName = symbolName
        self.colorHex = colorHex
        self.kindRaw = kind.rawValue
        self.isSystem = isSystem
        self.sortOrder = sortOrder
        self.parentID = parentID
        self.createdAt = Date()
    }

    var kind: TransactionKind {
        get { TransactionKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    var isSubcategory: Bool { parentID != nil }
}
