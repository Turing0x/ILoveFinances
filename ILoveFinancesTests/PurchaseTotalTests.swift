import Foundation
import Testing
@testable import ILoveFinances

/// El total del ticket se CALCULA sumando las lineas (decision de la Fase 5).
/// Si esta suma pierde un centimo, el gasto que llega al dashboard es falso.
@Suite("Total de un ticket de compra")
struct PurchaseTotalTests {

    private func linea(_ importe: String, position: Int = 0) -> PurchaseLine {
        PurchaseLine(
            rawName: "L\(position)",
            quantity: 1,
            unit: .unit,
            lineTotal: Decimal(string: importe)!,
            position: position
        )
    }

    @Test("La suma de las lineas es el total, sin perder centimos")
    func sumaExacta() {
        let lineas = [linea("1.20"), linea("5.40", position: 1), linea("4.25", position: 2)]
        #expect(PurchaseService.linesTotal(lineas) == Decimal(string: "10.85")!)
    }

    @Test("Un ticket sin lineas suma cero")
    func ticketVacio() {
        #expect(PurchaseService.linesTotal([]) == .zero)
    }

    /// El mismo test que caza un `Double` colado en cualquier otro sitio de la
    /// app, aplicado a un ticket largo de super.
    @Test("Cien lineas de 0,01 EUR suman exactamente 1,00 EUR")
    func acumulacionSinDeriva() {
        let lineas = (0..<100).map { linea("0.01", position: $0) }
        #expect(PurchaseService.linesTotal(lineas) == Decimal(string: "1.00")!)
    }

    @Test("Importes con tres decimales no se redondean por el camino")
    func sinRedondeoPrematuro() {
        let lineas = [linea("0.615"), linea("0.615", position: 1)]
        #expect(PurchaseService.linesTotal(lineas) == Decimal(string: "1.23")!)
    }

    /// La interfaz no ofrece lineas de ajuste, pero el esquema las admite. Si
    /// algun dia se activan, la suma tiene que seguir siendo la correcta.
    @Test("Una linea negativa resta del total")
    func lineaDeAjuste() {
        let cupon = PurchaseLine(
            rawName: "CUPON DTO", quantity: 1, unit: .unit,
            lineTotal: Decimal(string: "-2.00")!, position: 2
        )
        let lineas = [linea("1.20"), linea("5.40", position: 1), cupon]
        #expect(PurchaseService.linesTotal(lineas) == Decimal(string: "4.60")!)
    }
}
