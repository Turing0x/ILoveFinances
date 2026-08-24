import Foundation
import SwiftData

/// Una linea del ticket: un producto, su cantidad y lo que costo (Fase 5).
///
/// El precio por unidad de medida NO se guarda: se deriva en `PurchaseService`
/// a partir de `lineTotal`, `quantity` y `unit`. Guardarlo obligaria a
/// recalcularlo en cada edicion de la cantidad, y es exactamente el tipo de
/// dato duplicado que acaba desincronizado y mintiendo en el comparador.
@Model
final class PurchaseLine {
    var id: UUID = UUID()

    /// Lo que decia LITERALMENTE el ticket ("PAN BARRA 250G").
    ///
    /// Se guarda aunque haya `product` enlazado: es el dato en bruto del que
    /// se puede reconstruir una tabla de alias mas adelante sin tocar el
    /// esquema, y lo unico que queda si algun dia se borra el producto.
    var rawName: String = ""

    var quantity: Decimal = Decimal.zero
    var unitRaw: String = UnitOfMeasure.unit.rawValue

    /// Importe de la linea, no precio unitario. Positivo.
    ///
    /// El tipo admite negativos y `product` es opcional, asi que una linea de
    /// ajuste (un cupon global del super) es REPRESENTABLE en el esquema
    /// aunque la interfaz no la ofrezca. Se decidio no ofrecerla para no tener
    /// que teclear el total del ticket aparte; si algun dia molesta, se activa
    /// en la UI sin migrar nada.
    var lineTotal: Decimal = Decimal.zero

    var isOffer: Bool = false

    /// Orden dentro del ticket, tal y como venia en el papel.
    var position: Int = 0

    var createdAt: Date = Date()

    /// Inversa de `Transaction.purchaseLines`.
    var transaction: Transaction?

    /// Inversa de `GroceryProduct.lines`. Nil = linea fuera del historial.
    var product: GroceryProduct?

    init(
        rawName: String = "",
        quantity: Decimal = .zero,
        unit: UnitOfMeasure = .unit,
        lineTotal: Decimal = .zero,
        isOffer: Bool = false,
        position: Int = 0,
        product: GroceryProduct? = nil
    ) {
        self.id = UUID()
        self.rawName = rawName
        self.quantity = quantity
        self.unitRaw = unit.rawValue
        self.lineTotal = lineTotal
        self.isOffer = isOffer
        self.position = position
        self.product = product
        self.createdAt = Date()
    }

    var unit: UnitOfMeasure {
        get { UnitOfMeasure(rawValue: unitRaw) ?? .unit }
        set { unitRaw = newValue.rawValue }
    }
}
