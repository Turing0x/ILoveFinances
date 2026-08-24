import Foundation
import Testing
@testable import ILoveFinances

/// Sin esto el comparador de precios miente: comparar 750 g con 1 kg exige
/// llevar las dos a la misma unidad antes de dividir.
@Suite("Normalizacion de unidades de medida")
struct UnitOfMeasureTests {

    @Test("Cada unidad se lleva a su base con el factor correcto", arguments: [
        ("500", UnitOfMeasure.g, "0.5"),
        ("1000", UnitOfMeasure.g, "1"),
        ("2.5", UnitOfMeasure.kg, "2.5"),
        ("1500", UnitOfMeasure.ml, "1.5"),
        ("750", UnitOfMeasure.ml, "0.75"),
        ("1", UnitOfMeasure.l, "1"),
        ("3", UnitOfMeasure.unit, "3"),
    ])
    func aLaBase(cantidad: String, unidad: UnitOfMeasure, esperado: String) {
        let resultado = PurchaseService.quantityInBase(Decimal(string: cantidad)!, unit: unidad)
        #expect(resultado == Decimal(string: esperado)!)
    }

    @Test("Cada unidad pertenece a la dimension que le toca", arguments: [
        (UnitOfMeasure.unit, UnitDimension.count),
        (UnitOfMeasure.kg, UnitDimension.mass),
        (UnitOfMeasure.g, UnitDimension.mass),
        (UnitOfMeasure.l, UnitDimension.volume),
        (UnitOfMeasure.ml, UnitDimension.volume),
    ])
    func dimensiones(unidad: UnitOfMeasure, dimension: UnitDimension) {
        #expect(unidad.dimension == dimension)
    }

    /// Convertir la unidad base a si misma no puede cambiar el numero, o el
    /// precio por kilo de una compra en kilos saldria escalado.
    @Test("La unidad base de cada dimension tiene factor 1")
    func baseIdempotente() {
        for dimension in UnitDimension.allCases {
            #expect(dimension.baseUnit.factorToBase == 1)
            #expect(dimension.baseUnit.dimension == dimension)
        }
    }

    /// El factor de gramos y mililitros se construye desde String justamente
    /// para no pasar por Double: 0,001 en binario no es 0,001.
    @Test("El factor de las unidades pequenas es exactamente una milesima")
    func milesimaExacta() {
        #expect(UnitOfMeasure.g.factorToBase == Decimal(string: "0.001")!)
        #expect(UnitOfMeasure.ml.factorToBase == Decimal(string: "0.001")!)
        #expect(UnitOfMeasure.g.factorToBase * 1000 == 1)
    }
}
