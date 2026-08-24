import Charts
import SwiftData
import SwiftUI

struct DashboardView: View {
    let degradedReason: String?

    @State private var period: DatePeriod = .currentMonth
    @State private var showingSettings = false

    @Query(sort: \Account.name) private var accounts: [Account]
    @Query private var allTransactions: [Transaction]

    var body: some View {
        NavigationStack {
            List {
                if let degradedReason { degradedSection(degradedReason) }
                periodSection
                balanceSection
                flowSection
                if !breakdown.isEmpty { categorySection }
                if usedFamilyTags.count > 1 { familySection }
            }
            .navigationTitle("Resumen")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Ajustes", systemImage: "gearshape") { showingSettings = true }
                }
            }
            .sheet(isPresented: $showingSettings) { SettingsView() }
        }
    }

    // MARK: - Datos del periodo

    private var current: [Transaction] {
        let interval = period.interval
        return allTransactions.filter { $0.date >= interval.start && $0.date < interval.end }
    }

    private var previous: [Transaction] {
        let interval = period.previous.interval
        return allTransactions.filter { $0.date >= interval.start && $0.date < interval.end }
    }

    /// Ingresos y gastos usan `incomeExpenseAmount`: los traspasos aportan
    /// cero. Es la linea que hace cumplir "un traspaso no aparece como gasto".
    private func income(_ items: [Transaction]) -> Decimal {
        items.filter { $0.kind == .income }.reduce(Decimal.zero) { $0 + $1.amount }
    }

    private func expenses(_ items: [Transaction]) -> Decimal {
        items.filter { $0.kind == .expense }.reduce(Decimal.zero) { $0 + $1.amount }
    }

    private var totalBalance: Decimal {
        accounts.filter { !$0.isArchived }.reduce(Decimal.zero) { $0 + $1.balance }
    }

    private struct Slice: Identifiable {
        let id: UUID
        let name: String
        let colorHex: String
        let amount: Decimal
    }

    private var breakdown: [Slice] {
        let gastos = current.filter { $0.kind == .expense }
        let grouped = Dictionary(grouping: gastos) { $0.category?.id }
        return grouped.compactMap { key, items -> Slice? in
            let total = items.reduce(Decimal.zero) { $0 + $1.amount }
            guard total > 0 else { return nil }
            let category = items.first?.category
            return Slice(
                id: key ?? UUID(),
                name: category?.name ?? "Sin categoría",
                colorHex: category?.colorHex ?? "#888888",
                amount: total
            )
        }
        .sorted { $0.amount > $1.amount }
    }

    private var usedFamilyTags: [(name: String, amount: Decimal)] {
        let gastos = current.filter { $0.kind == .expense && $0.familyTag != nil }
        let grouped = Dictionary(grouping: gastos) { $0.familyTag?.name ?? "" }
        return grouped
            .map { ($0.key, $0.value.reduce(Decimal.zero) { $0 + $1.amount }) }
            .sorted { $0.1 > $1.1 }
    }

    // MARK: - Secciones

    private func degradedSection(_ reason: String) -> some View {
        Section {
            Label("Sin sincronización con iCloud", systemImage: "exclamationmark.icloud")
                .foregroundStyle(.red)
            Text(reason).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var periodSection: some View {
        Section {
            Picker("Periodo", selection: periodSelection) {
                Text("Mes").tag(0)
                Text("Trimestre").tag(1)
                Text("Año").tag(2)
            }
            .pickerStyle(.segmented)
            Text(period.title).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var periodSelection: Binding<Int> {
        Binding(
            get: {
                switch period {
                case .month: return 0
                case .quarter: return 1
                case .year: return 2
                case .custom: return 0
                }
            },
            set: {
                switch $0 {
                case 1: period = .quarter(Date())
                case 2: period = .year(Date())
                default: period = .month(Date())
                }
            }
        )
    }

    private var balanceSection: some View {
        Section("Saldo total") {
            LabeledContent("Todas las cuentas") {
                SignedAmountText(value: totalBalance, font: .title3.bold())
            }
            ForEach(accounts.filter { !$0.isArchived }) { account in
                LabeledContent {
                    SignedAmountText(value: account.balance, font: .callout)
                } label: {
                    Label(account.name, systemImage: account.type.symbolName)
                }
            }
            if accounts.isEmpty {
                Text("Añade una cuenta en Ajustes para empezar.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var flowSection: some View {
        Section("Ingresos y gastos") {
            LabeledContent("Ingresos") {
                Text(Money.formatted(income(current))).monospacedDigit().foregroundStyle(.green)
            }
            LabeledContent("Gastos") {
                Text(Money.formatted(expenses(current))).monospacedDigit()
            }
            LabeledContent("Diferencia") {
                SignedAmountText(value: income(current) - expenses(current), font: .headline)
            }
            variationRow
        }
    }

    @ViewBuilder
    private var variationRow: some View {
        let anterior = expenses(previous)
        let actual = expenses(current)
        if anterior > 0 {
            let delta = actual - anterior
            let porcentaje = (delta / anterior) * 100
            LabeledContent("Gasto vs periodo anterior") {
                Text("\(delta > 0 ? "+" : "")\(Money.rounded(porcentaje, scale: 1).description) %")
                    .monospacedDigit()
                    .foregroundStyle(delta > 0 ? .red : .green)
            }
        }
    }

    private var categorySection: some View {
        Section("Gasto por categoría") {
            Chart(breakdown) { slice in
                SectorMark(
                    // Unico sitio donde un importe se convierte a Double, y es
                    // para calcular un angulo en pantalla. El dato mostrado al
                    // lado sale de `slice.amount`, que sigue siendo Decimal.
                    angle: .value("Importe", (slice.amount as NSDecimalNumber).doubleValue),
                    innerRadius: .ratio(0.6),
                    angularInset: 1.5
                )
                .foregroundStyle(Color(hex: slice.colorHex))
            }
            .frame(height: 200)

            ForEach(breakdown) { slice in
                LabeledContent {
                    Text(Money.formatted(slice.amount)).monospacedDigit()
                } label: {
                    Label(slice.name, systemImage: "circle.fill")
                        .foregroundStyle(Color(hex: slice.colorHex))
                }
            }
        }
    }

    private var familySection: some View {
        Section("Por miembro") {
            ForEach(usedFamilyTags, id: \.name) { entry in
                LabeledContent(entry.name) {
                    Text(Money.formatted(entry.amount)).monospacedDigit()
                }
            }
        }
    }
}
