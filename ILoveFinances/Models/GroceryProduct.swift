import Foundation
import SwiftData

/// Producto de la compra, normalizado (Fase 5).
///
/// No se llama `Product` y el motivo es el mismo que dejo a `TransactionCategory`
/// sin llamarse `Category`: `StoreKit` exporta su propio `Product`, y en cuanto
/// ese import entre en ambito cualquier uso generico —`FetchDescriptor<Product>`—
/// queda ambiguo. Hoy compilaria por sombreado de modulo; el dia que se anada
/// una compra dentro de la app, no. Renombrar ahora sale gratis y despues del
/// despliegue a Production es IMPOSIBLE: el `RecordType` de CloudKit no se
/// puede borrar ni renombrar.
///
/// Sin campo `brand` a proposito: "Leche entera Hacendado" y "Leche entera
/// Pascual" son productos distintos porque no cuestan lo mismo. Una marca
/// aparte obligaria a decidir si el comparador cruza marcas, y esa decision no
/// tiene una respuesta buena para todos los productos.
@Model
final class GroceryProduct {
    var id: UUID = UUID()
    var name: String = ""              // "Leche entera Hacendado", "Pan de barra"

    /// Unidad en la que se COMPARA este producto, no en la que se compra.
    /// Una linea en gramos y otra en kilos se normalizan las dos a esta.
    var comparisonUnitRaw: String = UnitOfMeasure.unit.rawValue

    var symbolName: String = "cart"
    var note: String = ""
    var isArchived: Bool = false
    var createdAt: Date = Date()

    /// Inversa de `PurchaseLine.product`, obligatoria para CloudKit.
    ///
    /// `.nullify` DELIBERADO, y no `.cascade`: borrar un producto no puede
    /// borrar el historial de compras, que sigue siendo verdad. La linea
    /// conserva su `rawName` y su importe; solo pierde con que compararse.
    @Relationship(deleteRule: .nullify, inverse: \PurchaseLine.product)
    var lines: [PurchaseLine]? = []

    init(
        name: String = "",
        comparisonUnit: UnitOfMeasure = .unit,
        symbolName: String = "cart",
        note: String = ""
    ) {
        self.id = UUID()
        self.name = name
        self.comparisonUnitRaw = comparisonUnit.rawValue
        self.symbolName = symbolName
        self.note = note
        self.isArchived = false
        self.createdAt = Date()
    }

    var comparisonUnit: UnitOfMeasure {
        get { UnitOfMeasure(rawValue: comparisonUnitRaw) ?? .unit }
        set { comparisonUnitRaw = newValue.rawValue }
    }

    var dimension: UnitDimension { comparisonUnit.dimension }
}
