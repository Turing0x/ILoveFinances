import Foundation
import SwiftData

/// Tienda donde se hace la compra (Fase 5).
///
/// Es un LOCAL CONCRETO, no una cadena: "Mercadona de casa" y "Mercadona de mi
/// madre" son dos tiendas distintas. Modelar la cadena responderia "donde es
/// mas barato Mercadona", que no es la pregunta; la pregunta es a cual de los
/// sitios a los que puedo ir merece la pena ir a por el pan.
///
/// Sin direccion ni geolocalizacion a proposito: el nombre lo escribe el
/// usuario como lo tiene en la cabeza, que es como va a buscarlo.
@Model
final class Shop {
    var id: UUID = UUID()
    var name: String = ""              // "Mercadona de casa", "el marroqui de la esquina"
    var note: String = ""
    var colorHex: String = "#7FB069"
    var isArchived: Bool = false
    var sortOrder: Int = 0
    var createdAt: Date = Date()

    /// Inversa de `Transaction.shop`, obligatoria para CloudKit.
    ///
    /// `.nullify` y no `.cascade`: borrar una tienda no puede borrar los gastos
    /// hechos en ella. El ticket sobrevive sin tienda; el dinero se gasto igual.
    @Relationship(deleteRule: .nullify, inverse: \Transaction.shop)
    var purchases: [Transaction]? = []

    init(name: String = "", note: String = "", colorHex: String = "#7FB069", sortOrder: Int = 0) {
        self.id = UUID()
        self.name = name
        self.note = note
        self.colorHex = colorHex
        self.isArchived = false
        self.sortOrder = sortOrder
        self.createdAt = Date()
    }
}
