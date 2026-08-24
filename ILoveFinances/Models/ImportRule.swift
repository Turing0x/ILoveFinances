import Foundation
import SwiftData

/// Regla de autocategorizacion por texto. **Sin usar hasta la Fase 3.**
/// Entra en el esquema v1 por el mismo motivo que `ImportProfile`.
@Model
final class ImportRule {
    var id: UUID = UUID()
    var pattern: String = ""                 // subcadena en el concepto: "MERCADONA"
    var priority: Int = 0                    // menor gana; orden editable
    var isActive: Bool = true
    /// Cuantas veces ha acertado. Sirve para detectar reglas muertas o
    /// demasiado golosas.
    var matchCount: Int = 0
    var createdAt: Date = Date()

    var category: TransactionCategory?
    var familyTag: FamilyTag?

    init(pattern: String = "", priority: Int = 0) {
        self.id = UUID()
        self.pattern = pattern
        self.priority = priority
        self.isActive = true
        self.matchCount = 0
        self.createdAt = Date()
    }
}
