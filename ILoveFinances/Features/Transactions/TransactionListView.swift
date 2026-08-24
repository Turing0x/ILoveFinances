import SwiftData
import SwiftUI

struct TransactionListView: View {
    @State private var filter = TransactionFilter(period: .currentMonth)
    @State private var showingQuickAdd = false
    @State private var showingFilters = false

    @Query(sort: \Account.name) private var accounts: [Account]
    @Query(sort: \TransactionCategory.sortOrder) private var categories: [TransactionCategory]
    @Query(sort: \FamilyTag.sortOrder) private var familyTags: [FamilyTag]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !chips.isEmpty { chipBar }
                FilteredTransactionList(filter: filter)
            }
            .navigationTitle("Movimientos")
            .searchable(text: $filter.searchText, prompt: "Concepto o comercio")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Filtros", systemImage: "line.3.horizontal.decrease.circle") {
                        showingFilters = true
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Añadir", systemImage: "plus") { showingQuickAdd = true }
                }
            }
            .sheet(isPresented: $showingQuickAdd) { QuickAddView() }
            .sheet(isPresented: $showingFilters) {
                TransactionFilterSheet(filter: $filter)
            }
        }
    }

    private var chips: [TransactionFilter.Chip] {
        filter.chips(
            accountName: { id in accounts.first { $0.id == id }?.name },
            categoryName: { id in categories.first { $0.id == id }?.name },
            familyTagName: { id in familyTags.first { $0.id == id }?.name }
        )
    }

    private var chipBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chips) { chip in
                    FilterChip(label: chip.label) { chip.clear(&filter) }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
}

/// Subvista que construye su propia `@Query` en el `init`.
///
/// `@Query` toma un descriptor estatico, asi que no se puede cambiar el filtro
/// sobre la marcha. El patron es este: la vista padre reconstruye la hija al
/// cambiar el filtro, y la consulta se rehace con el nuevo predicado.
struct FilteredTransactionList: View {
    @Environment(\.modelContext) private var context
    @Query private var fetched: [Transaction]

    private let filter: TransactionFilter

    init(filter: TransactionFilter) {
        self.filter = filter
        _fetched = Query(filter: filter.predicate, sort: \Transaction.date, order: .reverse)
    }

    /// Los filtros por relacion y la busqueda se aplican aqui, sobre lo que ya
    /// recorto la consulta por fecha. Ver TransactionFilter.
    private var transactions: [Transaction] {
        fetched.filter(filter.matches)
    }

    private var days: [(date: Date, items: [Transaction])] {
        let grouped = Dictionary(grouping: transactions) {
            Calendar.current.startOfDay(for: $0.date)
        }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0] ?? []) }
    }

    /// Total con `incomeExpenseAmount`: los traspasos aportan cero, porque no
    /// mueven patrimonio.
    private var total: Decimal {
        transactions.reduce(Decimal.zero) { $0 + $1.incomeExpenseAmount }
    }

    var body: some View {
        Group {
            if transactions.isEmpty {
                ContentUnavailableView(
                    "Sin movimientos",
                    systemImage: "tray",
                    description: Text("No hay nada que coincida con el filtro.")
                )
            } else {
                List {
                    Section {
                        LabeledContent("Total del filtro") {
                            SignedAmountText(value: total, font: .headline)
                        }
                        LabeledContent("Movimientos", value: "\(transactions.count)")
                    }

                    ForEach(days, id: \.date) { day in
                        Section {
                            ForEach(day.items) { transaction in
                                NavigationLink {
                                    TransactionDetailView(transaction: transaction)
                                } label: {
                                    TransactionRow(transaction: transaction)
                                }
                            }
                            .onDelete { offsets in delete(offsets, in: day.items) }
                        } header: {
                            HStack {
                                Text(day.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                                Spacer()
                                SignedAmountText(
                                    value: day.items.reduce(Decimal.zero) { $0 + $1.incomeExpenseAmount },
                                    font: .caption
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    private func delete(_ offsets: IndexSet, in items: [Transaction]) {
        for index in offsets { context.delete(items[index]) }
        try? context.save()
    }
}

struct TransactionRow: View {
    let transaction: Transaction

    var body: some View {
        HStack {
            Image(systemName: transaction.category?.symbolName ?? transaction.kind.symbolName)
                .foregroundStyle(Color(hex: transaction.category?.colorHex))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.note.isEmpty ? (transaction.category?.name ?? "Sin concepto") : transaction.note)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let account = transaction.account {
                        Text(account.name)
                    }
                    if transaction.kind == .transfer, let destino = transaction.counterpartAccount {
                        Text("→ \(destino.name)")
                    }
                    if let tag = transaction.familyTag {
                        Text("· \(tag.name)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer()
            AmountText(transaction: transaction)
        }
    }
}
