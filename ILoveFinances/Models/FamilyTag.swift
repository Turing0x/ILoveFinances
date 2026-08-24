import Foundation
import SwiftData

/// Miembro de la familia.
///
/// Deliberadamente pobre: sin email, sin permisos, sin identidad. Es una
/// etiqueta de color con nombre, sirve para filtrar y para el desglose "quien
/// gasta que". Si algun dia hiciera falta un usuario real, se crea una entidad
/// `User` nueva y esta se queda como esta.
@Model
final class FamilyTag {
    var id: UUID = UUID()
    var name: String = ""              // "Raul", "Ana", "Comun", "Ninos"
    var colorHex: String = "#4A90D9"
    var sortOrder: Int = 0
    var createdAt: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \Transaction.familyTag)
    var transactions: [Transaction]? = []

    /// Inversa de `ImportRule.familyTag`, obligatoria para CloudKit.
    @Relationship(deleteRule: .nullify, inverse: \ImportRule.familyTag)
    var importRules: [ImportRule]? = []

    init(name: String = "", colorHex: String = "#4A90D9", sortOrder: Int = 0) {
        self.id = UUID()
        self.name = name
        self.colorHex = colorHex
        self.sortOrder = sortOrder
        self.createdAt = Date()
    }
}
