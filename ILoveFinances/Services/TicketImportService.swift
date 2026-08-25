import Foundation

/// Importacion de un ticket completo desde JSON (Fase 5).
///
/// El JSON lo produce un modelo de lenguaje leyendo la foto del ticket, FUERA
/// de la app: aqui solo entra texto. La decision de no meter OCR en la app
/// sigue en pie — esto no lee imagenes, lee un pegado del portapapeles.
///
/// Funciones PURAS sobre valores, sin `ModelContext`, igual que
/// `PurchaseService`: el parseo se prueba entero sin levantar un contenedor.
///
/// **Los numeros viajan como texto, no como numero JSON.** Un `Double` no
/// representa 0,1 exacto y el importe de una linea es dinero: la regla de la
/// casa lo prohibe (PLAN.md seccion 3). `JSONDecoder` sabe decodificar
/// `Decimal`, pero pasando por `Double` primero, asi que se parsea a mano
/// desde `String` con locale POSIX.
enum TicketImportService {

    // MARK: - Formato de entrada

    /// Lo que se espera del modelo de lenguaje. Todo opcional salvo `lines`,
    /// para que un JSON incompleto sirva igual: lo que falte lo pone el
    /// usuario en la pantalla, que es donde va a revisarlo de todas formas.
    struct Payload: Decodable {
        var shop: String?
        var date: String?
        var ticketTotal: String?
        var lines: [Line]
        var warnings: [String]?

        struct Line: Decodable {
            var rawName: String
            var product: String?
            var quantity: String?
            var unit: String?
            /// Importe BRUTO de la linea, el que aparece impreso.
            var lineTotal: String
            /// Descuento de esa linea, EN POSITIVO. El parseo lo resta.
            var discount: String?
            var isOffer: Bool?
        }
    }

    // MARK: - Resultado

    /// Ticket ya parseado y validado, listo para volcar en el editor.
    struct ParsedTicket {
        var shopName: String?
        var date: Date?
        /// Total que dice el papel, solo para comprobar. El importe que se
        /// guarda sigue siendo la suma de las lineas (decision de la Fase 5).
        var declaredTotal: Decimal?
        var lines: [ParsedLine]
        /// Avisos del modelo mas los que anade el propio parseo.
        var warnings: [String]

        var linesTotal: Decimal {
            lines.reduce(Decimal.zero) { $0 + $1.lineTotal }
        }

        /// Lo descontado en todo el ticket. Solo informativo: no se guarda en
        /// ningun sitio, se usa para poder decirlo al importar.
        var discountTotal: Decimal {
            lines.reduce(Decimal.zero) { $0 + $1.discount }
        }

        /// Diferencia entre lo que dice el papel y lo que suman las lineas.
        /// `nil` si el JSON no trae total declarado.
        var totalMismatch: Decimal? {
            guard let declaredTotal else { return nil }
            let diferencia = declaredTotal - linesTotal
            return diferencia == 0 ? nil : diferencia
        }
    }

    struct ParsedLine {
        var rawName: String
        var productName: String
        var quantity: Decimal
        var unit: UnitOfMeasure
        /// Ya NETO: el descuento viene restado. Es lo que se guardara.
        var lineTotal: Decimal
        /// Lo que se descontó, en positivo. Informativo: la app no lo persiste.
        var discount: Decimal
        var isOffer: Bool
    }

    // MARK: - Errores

    enum ImportError: LocalizedError {
        case notJSON
        case noLines
        case badNumber(line: String, field: String, value: String)

        var errorDescription: String? {
            switch self {
            case .notJSON:
                return "Eso no es un JSON válido. Copia la respuesta entera de Claude, desde la primera llave hasta la última."
            case .noLines:
                return "El JSON no trae ninguna línea de producto."
            case .badNumber(let line, let field, let value):
                return "En «\(line)», el campo \(field) no es un número: «\(value)»."
            }
        }
    }

    // MARK: - Parseo

    /// Acepta el JSON pelado o envuelto en un bloque de codigo markdown, que
    /// es como lo suele devolver un chat. Limpiar eso aqui evita que el
    /// usuario tenga que editar a mano lo que acaba de copiar.
    static func parse(_ raw: String) throws -> ParsedTicket {
        let limpio = stripCodeFence(raw)

        guard let data = limpio.data(using: .utf8),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            throw ImportError.notJSON
        }

        guard !payload.lines.isEmpty else { throw ImportError.noLines }

        var warnings = payload.warnings ?? []
        var lines: [ParsedLine] = []

        for line in payload.lines {
            guard let total = decimal(from: line.lineTotal) else {
                throw ImportError.badNumber(line: line.rawName, field: "lineTotal", value: line.lineTotal)
            }

            // Sin cantidad se asume 1: es el caso mayoritario de un ticket y
            // fallar por eso obligaria a editar el JSON a mano.
            let quantityText = line.quantity ?? "1"
            guard let quantity = decimal(from: quantityText) else {
                throw ImportError.badNumber(line: line.rawName, field: "quantity", value: quantityText)
            }

            let unit: UnitOfMeasure
            if let unitText = line.unit, !unitText.isEmpty {
                if let conocida = UnitOfMeasure(rawValue: unitText) {
                    unit = conocida
                } else {
                    unit = .unit
                    warnings.append("«\(line.rawName)»: unidad «\(unitText)» desconocida, se usa «unidad».")
                }
            } else {
                unit = .unit
            }

            // El descuento llega aparte para que el JSON refleje el papel y se
            // pueda verificar linea a linea contra el ticket. Lo que se guarda
            // es el neto: el desglose no se persiste (ver el plan de la Fase 5).
            var discount = Decimal.zero
            if let discountText = line.discount, !discountText.isEmpty {
                guard let valor = self.decimal(from: discountText) else {
                    throw ImportError.badNumber(line: line.rawName, field: "discount", value: discountText)
                }
                discount = abs(valor)
            }

            let neto = total - discount

            if discount > 0 && neto < 0 {
                warnings.append("«\(line.rawName)»: el descuento (\(Money.formatted(discount))) es mayor que el importe (\(Money.formatted(total))). Revísala antes de guardar.")
            }

            if neto < 0 && discount == 0 {
                warnings.append("«\(line.rawName)»: importe negativo. La app no admite líneas de descuento sueltas; revísala antes de guardar.")
            }

            lines.append(
                ParsedLine(
                    rawName: line.rawName,
                    productName: (line.product?.isEmpty == false ? line.product! : line.rawName),
                    quantity: quantity,
                    unit: unit,
                    lineTotal: neto,
                    discount: discount,
                    // Un descuento en una linea es una oferta puntual: se marca
                    // sola para que quede fuera del ranking por defecto sin que
                    // haya que acordarse de hacerlo a mano.
                    isOffer: (line.isOffer ?? false) || discount > 0
                )
            )
        }

        var declaredTotal: Decimal?
        if let totalText = payload.ticketTotal, !totalText.isEmpty {
            declaredTotal = decimal(from: totalText)
            if declaredTotal == nil {
                warnings.append("El total declarado «\(totalText)» no se entiende; se ignora.")
            }
        }

        let parsed = ParsedTicket(
            shopName: payload.shop?.isEmpty == false ? payload.shop : nil,
            date: date(from: payload.date),
            declaredTotal: declaredTotal,
            lines: lines,
            warnings: warnings
        )

        return parsed
    }

    // MARK: - Auxiliares

    /// Quita el ```json ... ``` con el que un chat suele envolver la respuesta.
    static func stripCodeFence(_ raw: String) -> String {
        var texto = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard texto.hasPrefix("```") else { return texto }

        // Primera linea: ``` o ```json. Se descarta entera.
        if let finPrimeraLinea = texto.firstIndex(of: "\n") {
            texto = String(texto[texto.index(after: finPrimeraLinea)...])
        }
        if let cierre = texto.range(of: "```", options: .backwards) {
            texto = String(texto[texto.startIndex..<cierre.lowerBound])
        }
        return texto.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Acepta coma o punto decimal y separador de millar, porque el ticket es
    /// espanol y el modelo puede devolver cualquiera de las dos formas.
    static func decimal(from raw: String) -> Decimal? {
        var texto = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "€", with: "")

        // "1.234,56" -> el punto es millar. "1234.56" -> el punto es decimal.
        if texto.contains(",") {
            texto = texto.replacingOccurrences(of: ".", with: "")
            texto = texto.replacingOccurrences(of: ",", with: ".")
        }

        guard !texto.isEmpty else { return nil }
        return Decimal(string: texto, locale: Locale(identifier: "en_US_POSIX"))
    }

    /// Solo `yyyy-MM-dd`, que es lo que pide el prompt. Cualquier otra cosa se
    /// ignora y la fecha la pone el usuario: adivinar formatos de fecha es
    /// como se cuelan tickets con seis meses de desfase.
    static func date(from raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: raw)
    }
}
