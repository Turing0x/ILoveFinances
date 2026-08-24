import Foundation

/// Calculo sobre tickets de compra y su historial de precios (Fase 5).
///
/// Funciones PURAS sobre valores, sin `ModelContext`, igual que
/// `RecurringBillService` (PLAN.md seccion 2). Nada de lo que se calcula aqui
/// se persiste: el precio por unidad de medida se deriva siempre, porque
/// guardarlo obligaria a recalcularlo en cada edicion de una cantidad.
///
/// Regla transversal: NO se redondea en el calculo. Se redondea al mostrar
/// (`Money.formattedRate`). Ordenar por valores redondeados empataria dos
/// tiendas a 1,234 y 1,236 EUR/kg, que es justo la diferencia que se busca.
enum PurchaseService {

    // MARK: - Unidades

    /// Cantidad llevada a la unidad base de su dimension: 500 g -> 0,5 kg.
    static func quantityInBase(_ quantity: Decimal, unit: UnitOfMeasure) -> Decimal {
        quantity * unit.factorToBase
    }

    /// Precio por unidad base: EUR/kg, EUR/l o EUR/ud.
    ///
    /// Devuelve `nil` con cantidad cero o negativa en vez de reventar. Una
    /// linea a la que se le borro la cantidad mientras se editaba es un estado
    /// normal de la interfaz, no un error del que haya que avisar.
    static func unitPrice(lineTotal: Decimal, quantity: Decimal, unit: UnitOfMeasure) -> Decimal? {
        let base = quantityInBase(quantity, unit: unit)
        guard base > 0 else { return nil }
        return lineTotal / base
    }

    static func unitPrice(of line: PurchaseLine) -> Decimal? {
        unitPrice(lineTotal: line.lineTotal, quantity: line.quantity, unit: line.unit)
    }

    /// Precio comparable con el resto del historial del producto.
    ///
    /// `nil` si la linea esta en otra dimension que el producto (litros contra
    /// kilos). NO es un error y no impide guardar: convertir volumen a peso
    /// exigiria una densidad que la app no tiene y que seria inventada. El
    /// comparador avisa de cuantas compras se quedan fuera.
    static func comparableUnitPrice(of line: PurchaseLine, in product: GroceryProduct) -> Decimal? {
        guard line.unit.dimension == product.dimension else { return nil }
        return unitPrice(of: line)
    }

    // MARK: - Total del ticket

    /// El importe del gasto ES esto (decision de la Fase 5: el total se calcula,
    /// no se teclea). Hay que recalcularlo en cada alta o edicion de linea.
    static func linesTotal(_ lines: [PurchaseLine]) -> Decimal {
        lines.reduce(Decimal.zero) { $0 + $1.lineTotal }
    }

    // MARK: - Historial de precios

    /// Una compra concreta de un producto, ya normalizada para comparar.
    struct PricePoint: Identifiable {
        let line: PurchaseLine
        let date: Date
        let shop: Shop?
        /// Ya en la unidad de comparacion del producto. `nil` si no es comparable.
        let unitPrice: Decimal?
        let isOffer: Bool

        var id: UUID { line.id }
    }

    /// Historial completo del producto, de mas reciente a mas antiguo.
    ///
    /// Las lineas sin transaccion no salen: sin fecha ni tienda no se pueden
    /// situar. Con `.cascade` en `Transaction.purchaseLines` no deberian
    /// existir, y este filtro es el cinturon por si alguna sobrevive.
    static func history(of product: GroceryProduct) -> [PricePoint] {
        (product.lines ?? [])
            .compactMap { line in
                guard let transaction = line.transaction else { return nil }
                return PricePoint(
                    line: line,
                    date: transaction.date,
                    shop: transaction.shop,
                    unitPrice: comparableUnitPrice(of: line, in: product),
                    isOffer: line.isOffer
                )
            }
            .sorted { $0.date > $1.date }
    }

    /// Resumen por tienda: lo ultimo que costo ahi y lo mejor que ha costado.
    struct ShopPrice: Identifiable {
        let shop: Shop?
        let latest: PricePoint
        let lowest: PricePoint
        let purchaseCount: Int

        var id: UUID { shop?.id ?? PurchaseService.unknownShopID }
    }

    /// Identidad de las compras sin tienda (la tienda se borro despues).
    static let unknownShopID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    /// Tiendas ordenadas por el ULTIMO precio, de mas barata a mas cara.
    ///
    /// `includingOffers == false` por defecto y a proposito: la pregunta es
    /// donde comprarlo habitualmente mas barato, y una oferta puntual de hace
    /// ocho meses no responde a eso — mandaria a una tienda donde ese precio
    /// ya no existe. Las compras no comparables (`unitPrice == nil`) tambien
    /// quedan fuera: no se pueden ordenar contra las demas.
    static func byShop(_ history: [PricePoint], includingOffers: Bool = false) -> [ShopPrice] {
        let usables = history.filter { point in
            point.unitPrice != nil && (includingOffers || !point.isOffer)
        }

        let porTienda = Dictionary(grouping: usables) { $0.shop?.id ?? unknownShopID }

        return porTienda.values.compactMap { puntos -> ShopPrice? in
            // `history` viene descendente por fecha, asi que el primero es el ultimo.
            guard let latest = puntos.first else { return nil }
            guard let lowest = puntos.min(by: { ($0.unitPrice ?? 0) < ($1.unitPrice ?? 0) }) else { return nil }
            return ShopPrice(
                shop: latest.shop,
                latest: latest,
                lowest: lowest,
                purchaseCount: puntos.count
            )
        }
        .sorted { ($0.latest.unitPrice ?? 0) < ($1.latest.unitPrice ?? 0) }
    }

    static func cheapest(_ product: GroceryProduct, includingOffers: Bool = false) -> ShopPrice? {
        byShop(history(of: product), includingOffers: includingOffers).first
    }

    // MARK: - Sugerencias de entrada

    /// Productos mas comprados EN ESA TIENDA, los recientes primero a igualdad
    /// de frecuencia.
    ///
    /// Mismo criterio que las categorias sugeridas de `QuickAddView` y por el
    /// mismo motivo: seguir al habito, no al historico completo. Lo que se
    /// compra en el super de al lado no es lo que se compra en el marroqui.
    static func frequentProducts(at shop: Shop, limit: Int = 12) -> [GroceryProduct] {
        let lineas = (shop.purchases ?? []).flatMap { $0.sortedLines }

        var conteo: [UUID: Int] = [:]
        var ultima: [UUID: Date] = [:]
        var productos: [UUID: GroceryProduct] = [:]

        for linea in lineas {
            guard let producto = linea.product, let fecha = linea.transaction?.date else { continue }
            conteo[producto.id, default: 0] += 1
            productos[producto.id] = producto
            if let anterior = ultima[producto.id] {
                ultima[producto.id] = max(anterior, fecha)
            } else {
                ultima[producto.id] = fecha
            }
        }

        return productos.values
            .sorted { a, b in
                let ca = conteo[a.id] ?? 0
                let cb = conteo[b.id] ?? 0
                if ca != cb { return ca > cb }
                return (ultima[a.id] ?? .distantPast) > (ultima[b.id] ?? .distantPast)
            }
            .prefix(limit)
            .map { $0 }
    }

    /// Ultima linea de ese producto en esa tienda, para precargar cantidad y
    /// unidad: casi siempre se compra el mismo formato en el mismo sitio.
    static func lastLine(of product: GroceryProduct, at shop: Shop) -> PurchaseLine? {
        (product.lines ?? [])
            .filter { $0.transaction?.shop?.id == shop.id }
            .max { a, b in
                (a.transaction?.date ?? .distantPast) < (b.transaction?.date ?? .distantPast)
            }
    }

    /// Coincidencia por nombre, insensible a mayusculas y a acentos.
    ///
    /// Es lo que decide si al teclear "pan de payes" se enlaza el producto que
    /// ya existe o se crea uno nuevo. Comparacion exacta tras normalizar: un
    /// "contiene" enlazaria "Pan" con "Pan de molde" y ensuciaria el historial
    /// con precios de cosas distintas.
    static func match(name: String, in products: [GroceryProduct]) -> GroceryProduct? {
        let buscado = normalized(name)
        guard !buscado.isEmpty else { return nil }
        return products.first { normalized($0.name) == buscado }
    }

    static func normalized(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES"))
    }
}
