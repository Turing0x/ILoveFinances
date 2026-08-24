import SwiftData
import SwiftUI

/// Raiz de la pestana Compras (Fase 5).
///
/// Una sola pantalla con dos modos, y es la busqueda la que decide cual: sin
/// texto, los tickets; con texto, los productos y donde salen mas baratos. Un
/// selector segmentado obligaria a elegir modo antes de saber que se busca.
struct PurchasesView: View {
    @Query(
        filter: #Predicate<Transaction> { $0.isPurchaseTicket },
        sort: \Transaction.date,
        order: .reverse
    )
    private var tickets: [Transaction]

    @Query(sort: \GroceryProduct.name) private var products: [GroceryProduct]

    @State private var query = ""
    @State private var creating = false

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty {
                    ticketSections
                } else {
                    productResults
                }
            }
            .navigationTitle("Compras")
            .searchable(text: $query, prompt: "Producto: pan, leche…")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Nuevo ticket", systemImage: "plus") { creating = true }
                }
            }
            .sheet(isPresented: $creating) {
                TicketEditorView(ticket: nil)
            }
            .overlay { emptyState }
        }
    }

    // MARK: - Tickets

    /// Agrupados por mes, como `FilteredTransactionList` agrupa por dia.
    private var ticketSections: some View {
        ForEach(months, id: \.self) { month in
            Section(monthTitle(month)) {
                ForEach(ticketsByMonth[month] ?? []) { ticket in
                    NavigationLink {
                        TicketDetailView(ticket: ticket)
                    } label: {
                        ticketRow(ticket)
                    }
                }
            }
        }
    }

    private var ticketsByMonth: [Date: [Transaction]] {
        Dictionary(grouping: tickets) { ticket in
            let componentes = Calendar.current.dateComponents([.year, .month], from: ticket.date)
            return Calendar.current.date(from: componentes) ?? ticket.date
        }
    }

    private var months: [Date] { ticketsByMonth.keys.sorted(by: >) }

    private func monthTitle(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year())
    }

    private func ticketRow(_ ticket: Transaction) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(ticket.shop?.name ?? "Sin tienda")
                    .fontWeight(.medium)
                HStack(spacing: 6) {
                    Text(ticket.date.formatted(.dateTime.day().month(.abbreviated)))
                    Text("·")
                    Text("^[\(ticket.sortedLines.count) línea](inflect: true)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            AmountText(transaction: ticket)
        }
    }

    // MARK: - Busqueda de productos

    /// Filtrado EN MEMORIA, regla de la casa para el texto: los predicados de
    /// SwiftData sobre texto y relaciones son la parte fragil.
    private var matchingProducts: [GroceryProduct] {
        let buscado = PurchaseService.normalized(query)
        guard !buscado.isEmpty else { return [] }
        return products.filter { PurchaseService.normalized($0.name).contains(buscado) }
    }

    private var productResults: some View {
        Section("Productos") {
            if matchingProducts.isEmpty {
                Text("Ningún producto se llama así.")
                    .foregroundStyle(.secondary)
            }
            ForEach(matchingProducts) { product in
                NavigationLink {
                    ProductPriceView(product: product)
                } label: {
                    productRow(product)
                }
            }
        }
    }

    private func productRow(_ product: GroceryProduct) -> some View {
        let mejor = PurchaseService.cheapest(product)
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Label(product.name, systemImage: product.symbolName)
                Spacer()
                if let precio = mejor?.latest.unitPrice {
                    Text(Money.formattedRate(precio, unit: product.dimension.rateLabel))
                        .monospacedDigit()
                        .fontWeight(.medium)
                }
            }
            HStack(spacing: 6) {
                if let tienda = mejor?.shop?.name {
                    Text("Más barato en \(tienda)")
                } else {
                    Text("Sin compras comparables")
                }
                Text("·")
                Text("^[\((product.lines ?? []).count) compra](inflect: true)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Vacio

    @ViewBuilder
    private var emptyState: some View {
        if query.isEmpty && tickets.isEmpty {
            ContentUnavailableView(
                "Sin compras",
                systemImage: "cart",
                description: Text("Apunta un ticket con sus líneas y podrás buscar cualquier producto para ver dónde te sale más barato.")
            )
        }
    }
}
