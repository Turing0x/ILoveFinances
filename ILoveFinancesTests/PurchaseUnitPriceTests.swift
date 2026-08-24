import Foundation
import Testing
@testable import ILoveFinances

/// El calculo que justifica toda la Fase 5: sin precio por unidad de medida,
/// el historial de precios es una lista de importes que no dice nada.
@Suite("Precio por unidad de medida")
struct PurchaseUnitPriceTests {

    @Test("El precio por unidad base sale exacto cuando la division lo es", arguments: [
        // (importe, cantidad, unidad, esperado)
        ("4.25", "0.85", UnitOfMeasure.kg, "5"),
        ("1.20", "1", UnitOfMeasure.unit, "1.2"),
        ("5.40", "6", UnitOfMeasure.unit, "0.9"),
        ("1.05", "1", UnitOfMeasure.l, "1.05"),
        ("2.40", "200", UnitOfMeasure.g, "12"),
        ("1.50", "500", UnitOfMeasure.ml, "3"),
    ])
    func precioUnitario(importe: String, cantidad: String, unidad: UnitOfMeasure, esperado: String) throws {
        let resultado = try #require(PurchaseService.unitPrice(
            lineTotal: Decimal(string: importe)!,
            quantity: Decimal(string: cantidad)!,
            unit: unidad
        ))
        #expect(resultado == Decimal(string: esperado)!)
    }

    /// Con division periodica se comprueba el valor MOSTRADO, que es lo unico
    /// con un numero de decimales definido. El valor crudo lleva toda la
    /// precision de `Decimal` a proposito: es el que se ordena.
    @Test("Una division periodica conserva precision y redondea bien al mostrar", arguments: [
        ("0.79", "750", UnitOfMeasure.g, "1.0533"),
        ("0.80", "750", UnitOfMeasure.ml, "1.0667"),
    ])
    func precioPeriodico(importe: String, cantidad: String, unidad: UnitOfMeasure, esperado: String) throws {
        let resultado = try #require(PurchaseService.unitPrice(
            lineTotal: Decimal(string: importe)!,
            quantity: Decimal(string: cantidad)!,
            unit: unidad
        ))
        #expect(Money.rounded(resultado, scale: 4) == Decimal(string: esperado)!)
    }

    /// Una linea a la que se le borro la cantidad mientras se editaba es un
    /// estado normal de la interfaz. No puede reventar ni dividir por cero.
    @Test("Cantidad cero o negativa devuelve nil, no una division por cero", arguments: ["0", "-1", "-0.5"])
    func sinCantidad(cantidad: String) {
        let resultado = PurchaseService.unitPrice(
            lineTotal: Decimal(string: "3.00")!,
            quantity: Decimal(string: cantidad)!,
            unit: .kg
        )
        #expect(resultado == nil)
    }

    @Test("Una linea en litros no se compara con un producto medido en kilos")
    func dimensionesIncompatibles() {
        let producto = GroceryProduct(name: "Aceite de oliva", comparisonUnit: .kg)
        let linea = PurchaseLine(
            rawName: "ACEITE 1L",
            quantity: 1,
            unit: .l,
            lineTotal: Decimal(string: "8.90")!,
            product: producto
        )

        // El precio en su propia unidad si existe: lo que no existe es la comparacion.
        #expect(PurchaseService.unitPrice(of: linea) != nil)
        #expect(PurchaseService.comparableUnitPrice(of: linea, in: producto) == nil)
    }

    @Test("Gramos y kilos del mismo producto si se comparan entre si")
    func mismaDimensionDistintaUnidad() throws {
        let producto = GroceryProduct(name: "Jamon cocido", comparisonUnit: .kg)
        let enGramos = PurchaseLine(
            rawName: "JAMON 200G", quantity: 200, unit: .g,
            lineTotal: Decimal(string: "2.40")!, product: producto
        )

        let precio = try #require(PurchaseService.comparableUnitPrice(of: enGramos, in: producto))
        #expect(precio == 12)   // 2,40 EUR / 0,2 kg
    }

    /// EL test de la funcion: el envase mas barato no es el producto mas
    /// barato. Una botella de 750 ml a 0,80 EUR sale mas cara por litro que
    /// una de 1 l a 1,05 EUR, y el importe de linea dice lo contrario.
    @Test("El importe de linea mas bajo no gana si el formato es menor")
    func elFormatoManda() throws {
        let producto = GroceryProduct(name: "Leche entera Hacendado", comparisonUnit: .l)

        let grande = PurchaseLine(
            rawName: "LECHE 1L", quantity: 1, unit: .l,
            lineTotal: Decimal(string: "1.05")!, product: producto
        )
        let pequena = PurchaseLine(
            rawName: "LECHE 750ML", quantity: 750, unit: .ml,
            lineTotal: Decimal(string: "0.80")!, product: producto
        )

        let precioGrande = try #require(PurchaseService.comparableUnitPrice(of: grande, in: producto))
        let precioPequena = try #require(PurchaseService.comparableUnitPrice(of: pequena, in: producto))

        #expect(pequena.lineTotal < grande.lineTotal)   // parece mas barata
        #expect(precioPequena > precioGrande)           // y no lo es
    }
}
