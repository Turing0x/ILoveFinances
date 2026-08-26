import Foundation
import Testing
@testable import ILoveFinances

/// PLAN.md seccion 7 bis: "Sumar 1.000 importes de 0,01 EUR da exactamente
/// 10,00 EUR. Es el test que caza un Double colado en un calculo intermedio."
@Suite("Aritmetica de dinero")
struct MoneyArithmeticTests {

    @Test("Mil centimos suman diez euros exactos")
    func milCentimos() {
        let unidad = Decimal(string: "0.01")!
        let total = (0..<1_000).reduce(Decimal.zero) { acumulado, _ in acumulado + unidad }
        #expect(total == Decimal(string: "10.00")!)
    }

    /// El mismo bucle en Double NO da 10. Sin este contraste, el test de arriba
    /// podria estar pasando por casualidad y nadie se enteraria.
    @Test("El mismo bucle en Double falla, que es el motivo de prohibirlo")
    func elControlEnDoubleFalla() {
        let total = (0..<1_000).reduce(0.0) { acumulado, _ in acumulado + 0.01 }
        #expect(total != 10.0)
    }

    @Test("Redondeo a dos decimales, modo plain", arguments: [
        ("0.615", "0.62"),   // 0,5 sube
        ("0.614", "0.61"),
        ("0.005", "0.01"),
        ("-0.615", "-0.62"), // simetrico en negativo
        ("19.99", "19.99"),
        ("1234567.891", "1234567.89"),
    ])
    func redondeo(entrada: String, esperado: String) {
        let resultado = Money.rounded(Decimal(string: entrada)!)
        #expect(resultado == Decimal(string: esperado)!)
    }

    @Test("Serializacion a texto y vuelta, sin perdida", arguments: [
        "0.1", "0.07", "0.30", "19.99", "1234567.89",
        "0.615", "-45.00", "99999999.99", "0.005", "12.345678",
    ])
    func idaYVuelta(raw: String) {
        let original = Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX"))!
        let texto = Money.csvString(original)
        let vuelta = Money.fromCSVString(texto)
        #expect(vuelta == original)
    }

    /// El formateo depende del locale del formateador, no del dispositivo. Sin
    /// esto, la copia de seguridad de un movil en ingles no restauraria en uno
    /// en castellano.
    @Test("El texto para CSV no depende del idioma del dispositivo")
    func textoIndependienteDelIdioma() {
        let valor = Decimal(string: "1234.56")!
        #expect(Money.csvString(valor) == "1234.56")
    }

    // MARK: - Importe tecleado (Fase 6)

    /// `Money.parseInput` sustituyo a seis copias del mismo parseo repartidas
    /// por las vistas. Estos casos son los que cada copia tenia que acertar por
    /// su cuenta.
    @Test("El importe tecleado se lee con coma o con punto", arguments: [
        ("1,20", "1.20"), ("1.20", "1.20"), ("0,05", "0.05"),
        ("1 234,50", "1234.50"), ("-3,40", "-3.40"), ("0", "0"),
    ])
    func importeTecleado(entrada: String, esperado: String) {
        #expect(Money.parseInput(entrada) == Decimal(string: esperado, locale: Locale(identifier: "en_US_POSIX"))!)
    }

    @Test("Un importe vacio o ilegible no se inventa", arguments: ["", "   ", "abc", ","])
    func importeIlegible(entrada: String) {
        #expect(Money.parseInput(entrada) == nil)
    }
}
