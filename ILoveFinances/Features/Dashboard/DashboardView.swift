import Charts
import SwiftData
import SwiftUI

struct DashboardView: View {
    let degradedReason: String?

    @State private var period: DatePeriod = .currentMonth
    @State private var showingSettings = false

    @Query(sort: \Account.name) private var accounts: [Account]
    @Query private var allTransactions: [Transaction]
    @Query(sort: \RecurringBill.name) private var bills: [RecurringBill]

    var body: some View {
        NavigationStack {
            List {
                if let degradedReason { degradedSection(degradedReason) }
                periodSection
                balanceSection
                flowSection
                if hasRecurring { recurringSummarySection }
                if !upcomingBills.isEmpty { upcomingBillsSection }
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

    /// El saldo total es "dinero disponible": una tarjeta de transporte se va
    /// gastando viaje a viaje y no representa eso, asi que queda fuera tanto
    /// del total como del desglose de abajo. Su saldo sigue viendose donde
    /// vive de forma natural: la pestana Bus.
    private var accountsForBalance: [Account] {
        accounts.filter { !$0.isArchived && $0.type != .transport }
    }

    private var totalBalance: Decimal {
        accountsForBalance.reduce(Decimal.zero) { $0 + $1.balance }
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

    private var recurringSummary: RecurringBillService.Summary {
        RecurringBillService.summary(bills: bills)
    }

    /// Hay algo vigente que resumir. Sin esto, la tarjeta saldria a ceros en una
    /// app recien instalada.
    private var hasRecurring: Bool {
        let resumen = recurringSummary
        return resumen.monthlyExpense > 0 || resumen.monthlyIncome > 0
    }

    /// Proximas ocurrencias a 30 dias, gastos e ingresos. La ventana es mas
    /// corta que la de la pestana de Recurrentes (60) a proposito: el resumen es
    /// un vistazo, no el listado completo.
    private var upcomingBills: [RecurringBillService.Upcoming] {
        RecurringBillService.upcoming(
            bills: bills.filter(\.isActive),
            days: 30,
            includingPaid: false
        )
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
            ForEach(accountsForBalance) { account in
                LabeledContent {
                    SignedAmountText(value: account.balance, font: .callout)
                } label: {
                    Label(account.name, systemImage: account.type.symbolName)
                }
            }
            if accountsForBalance.isEmpty {
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

    /// Compromisos fijos, normalizados a mes y ano.
    ///
    /// No es lo que cae en los proximos 30 dias —eso es la seccion de abajo—
    /// sino con cuanto se cuenta de forma estable: un anual reparte su peso
    /// entre los doce meses.
    private var recurringSummarySection: some View {
        Section("Recurrentes") {
            let resumen = recurringSummary
            SummaryRow(title: "Gasto fijo", monthly: resumen.monthlyExpense, annual: resumen.annualExpense, kind: .expense)
            SummaryRow(title: "Ingreso fijo", monthly: resumen.monthlyIncome, annual: resumen.annualIncome, kind: .income)
            SummaryRow(title: "Neto", monthly: resumen.monthlyNet, annual: resumen.annualNet, kind: nil)
        }
    }

    private var upcomingBillsSection: some View {
        Section("Próximos 30 días") {
            ForEach(upcomingBills) { item in
                UpcomingRow(item: item)
            }
            // Los dos totales van SEPARADOS: sumarlos en una sola cifra
            // restaria los ingresos de las facturas y daria un numero que no
            // significa nada — ni lo que hay que pagar, ni lo que va a entrar.
            if upcomingExpense > 0 {
                LabeledContent("A pagar") {
                    Text(Money.formatted(upcomingExpense)).monospacedDigit()
                }
            }
            if upcomingIncome > 0 {
                LabeledContent("A cobrar") {
                    Text(Money.formatted(upcomingIncome)).monospacedDigit()
                }
            }
        }
    }

    private var upcomingExpense: Decimal {
        upcomingBills.filter { !$0.bill.isIncome }.reduce(Decimal.zero) { $0 + $1.bill.estimatedAmount }
    }

    private var upcomingIncome: Decimal {
        upcomingBills.filter(\.bill.isIncome).reduce(Decimal.zero) { $0 + $1.bill.estimatedAmount }
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
