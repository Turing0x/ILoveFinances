import CloudKit
import Foundation

/// Comprobacion A del Paso 3: de que tipo es realmente cada campo dentro del
/// CKRecord que sube el mirroring.
///
/// Detalle que ahorra una hora: la via intuitiva —CKQueryOperation con
/// NSPredicate(value: true)— FALLA. El esquema que genera
/// NSPersistentCloudKitContainer no marca los campos como queryable y la
/// consulta devuelve un error de indice en vez de datos. Con cambios de zona
/// no hace falta ningun indice.
enum CloudKitInspector {

    static let containerID = "iCloud.dev.threedots.ilovefinances.spike"

    struct FieldDump {
        let name: String
        let swiftType: String
        let value: String
    }

    struct RecordDump {
        let recordType: String
        let recordName: String
        let fields: [FieldDump]
    }

    // MARK: - Volcado

    static func dump() async throws -> [RecordDump] {
        let database = CKContainer(identifier: containerID).privateCloudDatabase

        // La zona del mirroring sera com.apple.coredata.cloudkit.zone, pero se
        // descubre en vez de codificarse: si Apple la renombra, esto sigue.
        let databaseChanges = try await database.databaseChanges(since: nil)
        let zoneIDs = databaseChanges.modifications.map(\.zoneID)

        var dumps: [RecordDump] = []
        for zoneID in zoneIDs {
            dumps.append(contentsOf: try await records(in: zoneID, database: database))
        }
        return dumps
    }

    private static func records(
        in zoneID: CKRecordZone.ID,
        database: CKDatabase
    ) async throws -> [RecordDump] {
        var dumps: [RecordDump] = []
        var token: CKServerChangeToken?

        while true {
            let result = try await database.recordZoneChanges(inZoneWith: zoneID, since: token)

            for (_, modification) in result.modificationResultsByID {
                guard let record = try? modification.get().record else { continue }
                dumps.append(dump(of: record))
            }

            token = result.changeToken
            // moreComing: sin este bucle solo se ven los primeros registros y
            // el recuento parece que falta la mitad del lote.
            guard result.moreComing else { break }
        }
        return dumps
    }

    private static func dump(of record: CKRecord) -> RecordDump {
        let fields = record.allKeys().sorted().map { key -> FieldDump in
            let raw = record[key]
            return FieldDump(
                name: key,
                swiftType: raw.map { String(describing: type(of: $0)) } ?? "nil",
                value: describe(raw)
            )
        }
        return RecordDump(
            recordType: record.recordType,
            recordName: record.recordID.recordName,
            fields: fields
        )
    }

    /// Imprime el valor sin redondear. Un `String(format:)` con dos decimales
    /// escondería exactamente lo que se está buscando.
    private static func describe(_ value: Any?) -> String {
        switch value {
        case let number as Double:  return "\(number)"
        case let number as Int64:   return "\(number)"
        case let number as Int:     return "\(number)"
        case let text as String:    return "\"\(text)\""
        case let data as Data:      return "<\(data.count) bytes>"
        case let date as Date:      return "\(date)"
        case .none:                 return "nil"
        case .some(let other):      return "\(other)"
        }
    }

    // MARK: - Informe

    static func report(_ dumps: [RecordDump]) -> String {
        guard !dumps.isEmpty else {
            return """
            Sin registros en CloudKit todavia.

            Si acabas de sembrar, es normal: el mirroring tarda. Espera y vuelve
            a inspeccionar. No concluyas que se han perdido datos sin mirar el
            log de exportacion (argumento -com.apple.CoreData.CloudKitDebug 1).
            """
        }

        var lines: [String] = []
        lines.append("Registros en CloudKit: \(dumps.count) (esperados \(ProbeFixtures.totalRecordCount))")
        lines.append("")

        // El esquema de campos es identico en todos: basta uno para responder
        // la pregunta de la comprobacion A.
        if let sample = dumps.first {
            lines.append("Esquema de \(sample.recordType) — tipo REAL de cada campo:")
            lines.append("")
            for field in sample.fields {
                lines.append("  \(field.name.padded(28))\(field.swiftType.padded(14))\(field.value)")
            }
            lines.append("")
        }

        let decimalField = dumps.first?.fields.first { $0.name.hasSuffix("asDecimal") }
        if let decimalField {
            lines.append("VEREDICTO PARCIAL")
            lines.append("  CD_asDecimal viaja como: \(decimalField.swiftType)")
            if decimalField.swiftType.contains("Double") {
                lines.append("  -> Es Double. La perdida de precision es casi segura.")
                lines.append("     Confirmarlo con el viaje de ida y vuelta (Paso 4).")
            } else {
                lines.append("  -> No es Double. Decimal puede sobrevivir intacto.")
                lines.append("     Confirmarlo igualmente con el viaje de ida y vuelta.")
            }
        }

        return lines.joined(separator: "\n")
    }
}

private extension String {
    func padded(_ width: Int) -> String {
        count >= width ? self + " " : self + String(repeating: " ", count: width - count)
    }
}
