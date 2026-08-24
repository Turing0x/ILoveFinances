import Foundation

/// Lectura y escritura de CSV para la copia de seguridad.
///
/// Todas las reglas de aqui existen por un fallo concreto que evitan:
/// - **Comillas RFC 4180**: sin ellas, un concepto como `Cena, restaurante`
///   parte la fila en dos y el fichero deja de restaurar.
/// - **Locale POSIX** en numeros y fechas: un movil en castellano escribiria
///   `0,1` y el parseo de vuelta fallaria. En la Fase 0 el codec de texto fue
///   el unico que no perdio nada en ninguna de las diez sondas.
/// - **Cabecera leida por nombre, no por posicion**: asi una copia de hoy
///   sigue restaurando cuando el modelo tenga un campo mas.
enum CSVCodec {

    // MARK: - Escritura

    static func encode(header: [String], rows: [[String]]) -> String {
        var output = line(header)
        for row in rows { output += line(row) }
        return output
    }

    private static func line(_ fields: [String]) -> String {
        fields.map(escape).joined(separator: ",") + "\n"
    }

    /// Se entrecomilla si el campo lleva coma, comilla o salto de linea. La
    /// comilla interna se duplica, que es como manda RFC 4180.
    static func escape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") else {
            return field
        }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: - Lectura

    struct Table {
        let header: [String]
        let rows: [[String: String]]
    }

    static func decode(_ text: String) throws -> Table {
        let records = parse(text)
        guard let header = records.first else { return Table(header: [], rows: []) }

        let rows = records.dropFirst().compactMap { record -> [String: String]? in
            // Una fila totalmente vacia es el salto final del fichero, no un dato.
            if record.count == 1 && record[0].isEmpty { return nil }
            var dictionary: [String: String] = [:]
            for (index, column) in header.enumerated() {
                dictionary[column] = index < record.count ? record[index] : ""
            }
            return dictionary
        }
        return Table(header: header, rows: rows)
    }

    /// Analizador de estados. No vale partir por comas: dentro de comillas
    /// puede haber comas, comillas dobladas y hasta saltos de linea.
    private static func parse(_ text: String) -> [[String]] {
        var records: [[String]] = []
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var iterator = text.makeIterator()
        var pending: Character?

        func endField() { fields.append(current); current = "" }
        func endRecord() { endField(); records.append(fields); fields = [] }

        while let character = pending ?? iterator.next() {
            pending = nil

            if inQuotes {
                if character == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" {
                            current.append("\"")      // comilla escapada
                        } else {
                            inQuotes = false
                            pending = next
                        }
                    } else {
                        inQuotes = false
                    }
                } else {
                    current.append(character)
                }
                continue
            }

            switch character {
            case "\"": inQuotes = true
            case ",":  endField()
            case "\n": endRecord()
            case "\r": break                       // ficheros con CRLF
            default:   current.append(character)
            }
        }

        if !current.isEmpty || !fields.isEmpty { endRecord() }
        return records
    }

    // MARK: - Tipos

    private static let posixLocale = Locale(identifier: "en_US_POSIX")

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func string(from date: Date) -> String { dateFormatter.string(from: date) }
    static func date(from raw: String) -> Date? { dateFormatter.date(from: raw) }

    static func string(from value: Decimal) -> String { Money.csvString(value) }
    static func decimal(from raw: String) -> Decimal? { Money.fromCSVString(raw) }

    static func string(from uuid: UUID?) -> String { uuid?.uuidString ?? "" }
    static func uuid(from raw: String) -> UUID? { raw.isEmpty ? nil : UUID(uuidString: raw) }

    static func string(from flag: Bool) -> String { flag ? "true" : "false" }
    static func bool(from raw: String) -> Bool { raw == "true" }
}
