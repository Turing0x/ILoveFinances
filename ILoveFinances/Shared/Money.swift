import Foundation

/// Todo lo relacionado con dinero pasa por aqui.
///
/// Regla de la casa (PLAN.md seccion 3): **`Double` esta prohibido en cualquier
/// tipo o calculo que represente dinero.** `Double` no representa 0,1 exacto y
/// sumar 300 gastos de centimos acumula error visible. La Fase 0 confirmo que
/// `Decimal` sobrevive intacto al viaje por CloudKit.
enum Money {

    /// Redondeo a 2 decimales con `.plain` (el de toda la vida: 0,5 sube).
    /// Solo al MOSTRAR o al cerrar un importe; nunca en pasos intermedios de
    /// un calculo, que es donde el redondeo prematuro descuadra los totales.
    static func rounded(_ value: Decimal, scale: Int = 2) -> Decimal {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, scale, .plain)
        return result
    }

    /// Formato para la interfaz: "1.234,56 €" con la configuracion espanola.
    static func formatted(_ value: Decimal) -> String {
        value.formatted(.currency(code: "EUR").locale(Locale(identifier: "es_ES")))
    }

    /// Con signo explicito, para listas donde conviene distinguir de un vistazo.
    static func formattedSigned(_ value: Decimal) -> String {
        let text = formatted(abs(value))
        return value < 0 ? "−\(text)" : "+\(text)"
    }

    /// Precio por unidad de medida: "1,05 €/kg".
    ///
    /// Redondea a dos decimales SOLO al mostrar. El valor crudo es el que se
    /// ordena y compara en `PurchaseService`: dos tiendas a 1,234 y 1,236 €/kg
    /// empatarian si se redondease antes de ordenar.
    static func formattedRate(_ value: Decimal, unit: String) -> String {
        "\(formatted(rounded(value)))/\(unit)"
    }

    /// Serializacion estable, para el CSV de la copia de seguridad.
    ///
    /// Locale POSIX fijo: un movil en castellano escribiria "0,1" y el parseo
    /// de vuelta fallaria. En la Fase 0, el codec de texto fue el unico que no
    /// perdio nada en ninguna de las diez sondas.
    static func csvString(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).description(withLocale: posixLocale)
    }

    static func fromCSVString(_ raw: String) -> Decimal? {
        Decimal(string: raw, locale: posixLocale)
    }

    private static let posixLocale = Locale(identifier: "en_US_POSIX")
}
