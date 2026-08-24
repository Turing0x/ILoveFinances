import Foundation
import SwiftData

/// Sonda de la Fase 0: el mismo importe guardado en las cuatro codificaciones
/// candidatas, para ver cual sobrevive intacto al viaje por CloudKit.
///
/// CloudKit no tiene tipo decimal — sus tipos son String, Int64, Double, Data,
/// Date y Reference. NSPersistentCloudKitContainer tiene que traducir `Decimal`
/// a alguno de ellos, y si elige `Double` los importes vuelven de la nube con
/// error de precision. Ver PLAN.md seccion 3.
@Model
final class MoneyProbe {
    /// Comprobacion secundaria del Paso 6: `#Index` es la razon declarada para
    /// subir el deployment target a iOS 18+. Si esto compila, la premisa se
    /// sostiene y la Fase 1 puede apoyarse en ella.
    #Index<MoneyProbe>([\.createdAt], [\.label])

    var id: UUID = UUID()
    var label: String = ""

    /// Candidato A: lo que asume PLAN.md seccion 3 hoy.
    var asDecimal: Decimal = Decimal.zero

    /// Candidato B: el plan B de la seccion 3. Entero escalado.
    /// Escala 10^2 para dinero, 10^6 para cantidades de activo.
    var asScaledInt: Int = 0
    var scale: Int = 100

    /// Candidato C: el decimal serializado como texto.
    var asString: String = ""

    /// Control. Sabemos que pierde precision; sirve de referencia conocida en
    /// el volcado: si asDecimal se comporta igual que este, el diagnostico es
    /// inmediato y no hay nada que interpretar.
    var asDouble: Double = 0

    /// Marca las 200 filas de 0,01 EUR del lote de suma.
    var isBatchItem: Bool = false

    var createdAt: Date = Date()

    init(
        label: String,
        value: Decimal,
        scale: Int = 100,
        isBatchItem: Bool = false
    ) {
        self.id = UUID()
        self.label = label
        self.asDecimal = value
        self.scale = scale
        self.asScaledInt = MoneyProbe.scaledInt(from: value, scale: scale)
        self.asString = MoneyProbe.string(from: value)
        self.asDouble = NSDecimalNumber(decimal: value).doubleValue
        self.isBatchItem = isBatchItem
        self.createdAt = Date()
    }

    // MARK: - Conversiones

    /// Decimal -> entero escalado. Se redondea con `.plain` de forma explicita:
    /// dejarselo a `intValue` truncaria y falsearia el candidato B.
    static func scaledInt(from value: Decimal, scale: Int) -> Int {
        var multiplied = value * Decimal(scale)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &multiplied, 0, .plain)
        return NSDecimalNumber(decimal: rounded).intValue
    }

    static func decimal(fromScaledInt raw: Int, scale: Int) -> Decimal {
        Decimal(raw) / Decimal(scale)
    }

    /// Locale POSIX fijo: sin el, un movil en castellano escribiria "0,1" y el
    /// parseo de vuelta fallaria. Mismo motivo que el DateFormatter de la
    /// seccion 4 del PLAN.
    static func string(from value: Decimal) -> String {
        NSDecimalNumber(decimal: value).description(withLocale: Locale(identifier: "en_US_POSIX"))
    }

    static func decimal(fromString raw: String) -> Decimal {
        Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX")) ?? .nan
    }

    // MARK: - Lectura de vuelta

    var decodedFromScaledInt: Decimal { MoneyProbe.decimal(fromScaledInt: asScaledInt, scale: scale) }
    var decodedFromString: Decimal { MoneyProbe.decimal(fromString: asString) }
    var decodedFromDouble: Decimal { Decimal(asDouble) }
}
