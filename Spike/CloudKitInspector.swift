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
                swiftType: storageType(of: raw),
                value: describe(raw)
            )
        }
        return RecordDump(
            recordType: record.recordType,
            recordName: record.recordID.recordName,
            fields: fields
        )
    }

    /// El tipo de almacenamiento REAL.
    ///
    /// No vale `type(of:)`: todo numero llega como `__NSCFNumber`, la clase
    /// puente de NSNumber, que no distingue un double de un entero. Y tampoco
    /// vale intentar `as? Double`, porque NSNumber se puentea a Double aunque
    /// dentro lleve un entero. Lo unico que lo dice es `objCType`.
    private static func storageType(of value: Any?) -> String {
        guard let value else { return "nil" }
        if let number = value as? NSNumber {
            switch String(cString: number.objCType) {
            case "d": return "Double"
            case "f": return "Float"
            case "q", "l", "i", "s": return "Int64"
            case "c", "B": return "Bool/Int8"
            default: return "NSNumber(\(String(cString: number.objCType)))"
            }
        }
        return String(describing: type(of: value))
    }

    /// Imprime el valor sin redondear, con 20 cifras significativas cuando es
    /// un double: es la unica forma de ver la diferencia entre 0,01 exacto y el
    /// double mas cercano a 0,01.
    private static func describe(_ value: Any?) -> String {
        switch value {
        case let number as NSNumber:
            let objCType = String(cString: number.objCType)
            if objCType == "d" || objCType == "f" {
                return String(format: "%.20g", number.doubleValue)
            }
            return number.stringValue
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
                lines.append("  \(field.name.padded(24))\(field.swiftType.padded(12))\(field.value)")
            }
            lines.append("")
        }

        let decimalField = dumps.first?.fields.first { $0.name.hasSuffix("asDecimal") }
        if let decimalField {
            lines.append("VEREDICTO PARCIAL")
            lines.append("  CD_asDecimal viaja como: \(decimalField.swiftType)")
            let intField = dumps.first?.fields.first { $0.name.hasSuffix("asScaledInt") }
            if let intField {
                lines.append("  CD_asScaledInt viaja como: \(intField.swiftType)  (referencia: es un Int)")
            }
            if decimalField.swiftType == "Double" {
                lines.append("  -> ES Double. CloudKit no tiene tipo decimal y el mirroring")
                lines.append("     lo degrada. La perdida de precision es casi segura;")
                lines.append("     confirmarla con el viaje de ida y vuelta (Paso 4).")
            } else {
                lines.append("  -> NO es Double. Decimal puede sobrevivir intacto.")
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
