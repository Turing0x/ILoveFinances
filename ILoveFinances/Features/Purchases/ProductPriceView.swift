import SwiftData
import SwiftUI

/// El comparador: donde comprar este producto mas barato (Fase 5).
///
/// Todo se DERIVA en cada aparicion, nada esta guardado: por eso cambiar la
/// unidad de comparacion aqui mismo recalcula el ranking entero al momento.
struct ProductPriceView: View {
    @Bindable var product: GroceryProduct

    @State private var includingOffers = false

    var body: some View {
        List {
            Section {
                Picker("Comparar por", selection: $product.comparisonUnit) {
                    ForEach(UnitOfMeasure.allCases, id: \.self) { unit in
                        Text(unit.label).tag(unit)
                    }
                }
                Toggle("Incluir ofertas", isOn: $includingOffers)
            } footer: {
                Text("Las ofertas quedan fuera por defecto: una oferta puntual de hace meses te mandaría a una tienda donde ese precio ya no existe.")
            }

            if !ranking.isEmpty {
                Section("Dónde comprarlo más barato") {
                    ForEach(Array(ranking.enumerated()), id: \.element.id) { index, item in
                        shopRow(item, isCheapest: index == 0)
                    }
                }
            }

            if noComparables > 0 {
                Section {
                    Label(
                        "^[\(noComparables) compra](inflect: true) no se comparan: están en otra unidad.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Section("Histórico") {
                ForEach(history) { point in
                    historyRow(point)
                }
            }
        }
        .navigationTitle(product.name)
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if history.isEmpty {
                ContentUnavailableView(
                    "Sin compras",
                    systemImage: "cart",
                    description: Text("Este producto todavía no aparece en ningún ticket.")
                )
            }
        }
    }

    // MARK: - Datos derivados

    private var history: [PurchaseService.PricePoint] {
        PurchaseService.history(of: product)
    }

    private var ranking: [PurchaseService.ShopPrice] {
        PurchaseService.byShop(history, includingOffers: includingOffers)
    }

    private var noComparables: Int {
        history.filter { $0.unitPrice == nil }.count
    }

    // MARK: - Filas

    private func shopRow(_ item: PurchaseService.ShopPrice, isCheapest: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.shop?.name ?? "Sin tienda")
                        .fontWeight(isCheapest ? .semibold : .regular)
                    if isCheapest {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
                HStack(spacing: 6) {
                    Text(Money.formatted(item.latest.line.lineTotal))
                    Text("·")
                    Text("\(Money.csvString(item.latest.line.quantity)) \(item.latest.line.unit.shortLabel)")
                    Text("·")
                    Text(item.latest.date.formatted(.dateTime.day().month(.abbreviated)))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let precio = item.latest.unitPrice {
                    Text(Money.formattedRate(precio, unit: product.dimension.rateLabel))
                        .fontWeight(.medium)
                        .monospacedDigit()
                }
                Text("^[\(item.purchaseCount) compra](inflect: true)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func historyRow(_ point: PurchaseService.PricePoint) -> some View {
        NavigationLink {
            if let ticket = point.line.transaction {
                TicketDetailView(ticket: ticket)
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(point.date.formatted(.dateTime.day().month(.abbreviated).year()))
                        if point.isOffer {
                            Image(systemName: "tag.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                    Text(point.shop?.name ?? "Sin tienda")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    if let precio = point.unitPrice {
                        Text(Money.formattedRate(precio, unit: product.dimension.rateLabel))
                            .monospacedDigit()
                    } else {
                        Text("otra unidad")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("\(Money.formatted(point.line.lineTotal)) · \(Money.csvString(point.line.quantity)) \(point.line.unit.shortLabel)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }
}
