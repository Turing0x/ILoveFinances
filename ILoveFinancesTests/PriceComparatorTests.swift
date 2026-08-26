import Foundation
import SwiftData
import Testing
@testable import ILoveFinances

/// El criterio de cierre de la Fase 5: buscar un producto y saber donde sale
/// mas barato de verdad, no donde el importe de la linea fue menor.
@Suite("Comparador de precios")
@MainActor
struct PriceComparatorTests {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(SchemaV2.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func fecha(_ dia: Int) -> Date {
        var componentes = DateComponents()
        componentes.year = 2026
        componentes.month = 3
        componentes.day = dia
        return Calendar(identifier: .gregorian).date(from: componentes)!
    }

    /// Un ticket con una sola linea, que es todo lo que hace falta aqui.
    @discardableResult
    private func comprar(
        _ producto: GroceryProduct,
        en tienda: Shop,
        cantidad: String,
        unidad: UnitOfMeasure,
        importe: String,
        dia: Int,
        oferta: Bool = false,
        in context: ModelContext
    ) throws -> Transaction {
        let linea = PurchaseLine(
            rawName: producto.name.uppercased(),
            quantity: Decimal(string: cantidad)!,
            unit: unidad,
            lineTotal: Decimal(string: importe)!,
            isOffer: oferta,
            product: producto
        )
        let ticket = Transaction(
            date: fecha(dia),
            amount: Decimal(string: importe)!,
            kind: .expense,
            note: tienda.name
        )
        ticket.isPurchaseTicket = true
        ticket.shop = tienda
        context.insert(ticket)
        context.insert(linea)
        linea.transaction = ticket
        try context.save()
        return ticket
    }

    /// El mismo producto en tres tiendas y tres formatos distintos. Gana el
    /// que sale mas barato por litro, que NO es el del importe menor.
    @Test("La tienda mas barata se decide por precio unitario, no por importe")
    func laMasBarata() throws {
        let context = try makeContext()
        let leche = GroceryProduct(name: "Leche entera Hacendado", comparisonUnit: .l)
        let casa = Shop(name: "Mercadona de casa")
        let madre = Shop(name: "Mercadona de mi madre")
        let esquina = Shop(name: "El marroqui de la esquina")
        [casa, madre, esquina].forEach { context.insert($0) }
        context.insert(leche)

        // 1 l a 1,05 -> 1,05 EUR/l
        try comprar(leche, en: casa, cantidad: "1", unidad: .l, importe: "1.05", dia: 10, in: context)
        // 750 ml a 0,80 -> 1,0667 EUR/l  (importe menor, mas caro por litro)
        try comprar(leche, en: esquina, cantidad: "750", unidad: .ml, importe: "0.80", dia: 11, in: context)
        // 1,5 l a 1,50 -> 1,00 EUR/l
        try comprar(leche, en: madre, cantidad: "1.5", unidad: .l, importe: "1.50", dia: 12, in: context)

        let ranking = PurchaseService.byShop(PurchaseService.history(of: leche))
        #expect(ranking.count == 3)
        #expect(ranking.first?.shop?.name == "Mercadona de mi madre")
        #expect(ranking.last?.shop?.name == "El marroqui de la esquina")

        let masBarata = try #require(PurchaseService.cheapest(leche))
        #expect(masBarata.shop?.name == "Mercadona de mi madre")
    }

    /// Una oferta puntual no puede mandarte a una tienda donde ese precio ya
    /// no existe. Solo cuenta si se pide explicitamente.
    @Test("Las ofertas quedan fuera del ranking salvo que se pidan")
    func ofertas() throws {
        let context = try makeContext()
        let pan = GroceryProduct(name: "Pan de barra", comparisonUnit: .unit)
        let casa = Shop(name: "Mercadona de casa")
        let esquina = Shop(name: "El marroqui de la esquina")
        [casa, esquina].forEach { context.insert($0) }
        context.insert(pan)

        try comprar(pan, en: casa, cantidad: "1", unidad: .unit, importe: "1.20", dia: 10, in: context)
        try comprar(pan, en: esquina, cantidad: "1", unidad: .unit, importe: "0.60", dia: 11, oferta: true, in: context)

        let historial = PurchaseService.history(of: pan)

        let sinOfertas = PurchaseService.byShop(historial)
        #expect(sinOfertas.count == 1)
        #expect(sinOfertas.first?.shop?.name == "Mercadona de casa")

        let conOfertas = PurchaseService.byShop(historial, includingOffers: true)
        #expect(conOfertas.count == 2)
        #expect(conOfertas.first?.shop?.name == "El marroqui de la esquina")
    }

    @Test("El historial viene de mas reciente a mas antiguo")
    func historialOrdenado() throws {
        let context = try makeContext()
        let pan = GroceryProduct(name: "Pan de barra", comparisonUnit: .unit)
        let casa = Shop(name: "Mercadona de casa")
        context.insert(casa)
        context.insert(pan)

        try comprar(pan, en: casa, cantidad: "1", unidad: .unit, importe: "1.10", dia: 5, in: context)
        try comprar(pan, en: casa, cantidad: "1", unidad: .unit, importe: "1.20", dia: 20, in: context)
        try comprar(pan, en: casa, cantidad: "1", unidad: .unit, importe: "1.15", dia: 12, in: context)

        let historial = PurchaseService.history(of: pan)
        #expect(historial.map(\.date) == [fecha(20), fecha(12), fecha(5)])

        // Una sola tienda: el ultimo precio es el del dia 20, el mejor el del dia 5.
        let porTienda = try #require(PurchaseService.byShop(historial).first)
        #expect(porTienda.purchaseCount == 3)
        #expect(porTienda.latest.line.lineTotal == Decimal(string: "1.20")!)
        #expect(porTienda.lowest.line.lineTotal == Decimal(string: "1.10")!)
    }

    /// `.nullify` en `GroceryProduct.lines`: el historial de lo que se gasto
    /// sigue siendo verdad aunque el producto ya no interese.
    @Test("Borrar un producto no borra las lineas ni el gasto")
    func borrarProducto() throws {
        let context = try makeContext()
        let pan = GroceryProduct(name: "Pan de barra", comparisonUnit: .unit)
        let casa = Shop(name: "Mercadona de casa")
        context.insert(casa)
        context.insert(pan)
        try comprar(pan, en: casa, cantidad: "1", unidad: .unit, importe: "1.20", dia: 10, in: context)

        context.delete(pan)
        try context.save()

        let lineas = try context.fetch(FetchDescriptor<PurchaseLine>())
        #expect(lineas.count == 1)
        #expect(lineas.first?.rawName == "PAN DE BARRA")
        #expect(lineas.first?.product == nil)
        #expect(try context.fetchCount(FetchDescriptor<Transaction>()) == 1)
    }

    /// `.cascade` en `Transaction.purchaseLines`: sin ticket, la linea pierde
    /// fecha y tienda y se queda como basura consultable.
    @Test("Borrar el ticket borra sus lineas")
    func borrarTicket() throws {
        let context = try makeContext()
        let pan = GroceryProduct(name: "Pan de barra", comparisonUnit: .unit)
        let casa = Shop(name: "Mercadona de casa")
        context.insert(casa)
        context.insert(pan)
        let ticket = try comprar(pan, en: casa, cantidad: "1", unidad: .unit, importe: "1.20", dia: 10, in: context)

        context.delete(ticket)
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<PurchaseLine>()) == 0)
        #expect(PurchaseService.history(of: pan).isEmpty)
    }

    @Test("Las sugerencias de una tienda son lo mas comprado en ella")
    func sugerencias() throws {
        let context = try makeContext()
        let pan = GroceryProduct(name: "Pan de barra", comparisonUnit: .unit)
        let leche = GroceryProduct(name: "Leche entera", comparisonUnit: .l)
        let cafe = GroceryProduct(name: "Cafe molido", comparisonUnit: .kg)
        let casa = Shop(name: "Mercadona de casa")
        let esquina = Shop(name: "El marroqui de la esquina")
        [casa, esquina].forEach { context.insert($0) }
        [pan, leche, cafe].forEach { context.insert($0) }

        try comprar(pan, en: casa, cantidad: "1", unidad: .unit, importe: "1.20", dia: 5, in: context)
        try comprar(pan, en: casa, cantidad: "1", unidad: .unit, importe: "1.20", dia: 12, in: context)
        try comprar(leche, en: casa, cantidad: "1", unidad: .l, importe: "1.05", dia: 12, in: context)
        try comprar(cafe, en: esquina, cantidad: "250", unidad: .g, importe: "3.50", dia: 12, in: context)

        let sugeridos = PurchaseService.frequentProducts(at: casa)
        #expect(sugeridos.map(\.name) == ["Pan de barra", "Leche entera"])
        #expect(PurchaseService.frequentProducts(at: esquina).map(\.name) == ["Cafe molido"])

        // La ultima compra de pan en casa precarga cantidad y unidad.
        let ultima = try #require(PurchaseService.lastLine(of: pan, at: casa))
        #expect(ultima.transaction?.date == fecha(12))
    }

    @Test("El nombre casa sin distinguir mayusculas ni acentos")
    func coincidenciaDeNombre() throws {
        let context = try makeContext()
        let payes = GroceryProduct(name: "Pan de payés", comparisonUnit: .unit)
        let molde = GroceryProduct(name: "Pan de molde", comparisonUnit: .unit)
        [payes, molde].forEach { context.insert($0) }
        try context.save()

        let productos = [payes, molde]
        #expect(PurchaseService.match(name: "PAN DE PAYES", in: productos)?.id == payes.id)
        #expect(PurchaseService.match(name: "  pan de payés  ", in: productos)?.id == payes.id)
        // Exacta, no "contiene": "Pan" no puede enlazar con "Pan de molde".
        #expect(PurchaseService.match(name: "Pan", in: productos) == nil)
        #expect(PurchaseService.match(name: "", in: productos) == nil)
    }
}
