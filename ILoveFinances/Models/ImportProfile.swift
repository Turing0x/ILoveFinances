import Foundation
import SwiftData

/// Perfil de importacion de un banco. **Sin usar hasta la Fase 3.**
///
/// Entra en el esquema v1 a proposito: el esquema de CloudKit en Production es
/// aditivo, asi que anadir una entidad despues de tener datos reales
/// sincronizados es justo lo que no conviene. Una tabla vacia no cuesta nada.
@Model
final class ImportProfile {
    var id: UUID = UUID()
    var name: String = ""                    // "BBVA cuenta corriente"
    /// SHA-256 de las cabeceras normalizadas: es lo que permite reconocer el
    /// banco en la segunda importacion sin volver a preguntar el mapeo.
    var headerSignature: String = ""
    /// El mapeo va como JSON en un String y no como diccionario: SwiftData no
    /// persiste [Int: String] de forma fiable a traves de CloudKit, y el
    /// contenido nunca se consulta con predicados.
    var columnMappingJSON: String = "{}"
    var separator: String = ";"
    var encodingRaw: String = "utf8"
    var dateFormat: String = "dd/MM/yyyy"
    var amountStyleRaw: String = "singleSigned"   // o "debitCredit"
    var lastUsedAt: Date = Date()
    var createdAt: Date = Date()

    var account: Account?

    init(name: String = "", headerSignature: String = "") {
        self.id = UUID()
        self.name = name
        self.headerSignature = headerSignature
        self.lastUsedAt = Date()
        self.createdAt = Date()
    }
}
