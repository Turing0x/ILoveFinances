import SwiftData
import SwiftUI

/// Que mitad de los recurrentes se esta mirando.
///
/// Se guarda en `@AppStorage` porque no es un filtro de un rato: quien vive de
/// facturas abre siempre en gastos y quien controla la nomina y las
/// suscripciones abre siempre en ingresos. Reponerlo cada vez seria trabajo
/// repetido.
enum RecurringScope: String, CaseIterable {
    case expense
    case income
    case all

    var label: String {
        switch self {
        case .expense: return "Gastos"
        case .income:  return "Ingresos"
        case .all:     return "Todo"
        }
    }

    /// `nil` en `.all`: no filtra.
    var kind: TransactionKind? {
        switch self {
        case .expense: return .expense
        case .income:  return .income
        case .all:     return nil
        }
    }

    func matches(_ bill: RecurringBill) -> Bool {
        guard let kind else { return true }
        return bill.kind == kind
    }
}

/// Pestana de Recurrentes (PLAN.md seccion 6, ampliada en la Fase 7).
///
/// Tres bloques: el resumen normalizado a mensual y anual, lo que viene en los
/// proximos 60 dias —calculado, no almacenado— y el listado completo.
///
/// Gastos e ingresos son la MISMA entidad con `kind` distinto, asi que todo
/// —ocurrencias, avisos, pagos— se comparte y lo unico que cambia es el filtro
/// de arriba y las palabras.
struct RecurringView: View {
    @Environment(\.modelContext) private var context

    @Query(sort: \RecurringBill.name) private var bills: [RecurringBill]

    @AppStorage("recurringScope") private var scopeRaw = RecurringScope.expense.rawValue
    @State private var showingNew = false
    @State private var payingOccurrence: BillPrefill?

    /// Ventana de "proximas". Coincide con la del planificador de avisos a
    /// proposito: lo que se ve es exactamente lo que se va a avisar.
    private static let windowDays = NotificationPlanner.defaultWindowDays

    private var scope: RecurringScope {
        get { RecurringScope(rawValue: scopeRaw) ?? .expense }
        nonmutating set { scopeRaw = newValue.rawValue }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Tipo", selection: Binding(get: { scope }, set: { scope = $0 })) {
                        ForEach(RecurringScope.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                if !visible.isEmpty { summarySection }
                if !upcoming.isEmpty { upcomingSection }
                if !active.isEmpty { billsSection(activeTitle, active) }
                if !inactive.isEmpty { billsSection("Desactivados", inactive) }
            }
            .navigationTitle("Recurrentes")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Nuevo", systemImage: "plus") { showingNew = true }
                }
            }
            .sheet(isPresented: $showingNew) {
                // El alta se abre ya del tipo que se esta mirando: en Ingresos,
                // lo que se va a dar de alta es un ingreso.
                BillEditorView(bill: nil, initialKind: scope.kind ?? .expense)
            }
            .sheet(item: $payingOccurrence) { prefill in
                QuickAddView(prefill: prefill)
            }
            .overlay {
                if visible.isEmpty { emptyState }
            }
        }
    }

    // MARK: - Datos

    private var visible: [RecurringBill] { bills.filter(scope.matches) }
    private var active: [RecurringBill] { visible.filter(\.isActive) }
    private var inactive: [RecurringBill] { visible.filter { !$0.isActive } }

    private var upcoming: [RecurringBillService.Upcoming] {
        RecurringBillService.upcoming(bills: active, days: Self.windowDays)
    }

    /// El resumen mira SIEMPRE el conjunto visible, no solo las activas: las
    /// inactivas ya quedan fuera dentro de `summary`.
    private var summary: RecurringBillService.Summary {
        RecurringBillService.summary(bills: visible)
    }

    private var activeTitle: String {
        switch scope {
        case .expense: return "Gastos activos"
        case .income:  return "Ingresos activos"
        case .all:     return "Activos"
        }
    }

    // MARK: - Secciones

    /// Mensual y anual EQUIVALENTES, no lo que cae este mes: un seguro anual
    /// pesa todos los meses aunque solo se cobre en junio.
    private var summarySection: some View {
        Section {
            if scope != .income {
                SummaryRow(title: "Gasto fijo", monthly: summary.monthlyExpense, annual: summary.annualExpense, kind: .expense)
            }
            if scope != .expense {
                SummaryRow(title: "Ingreso fijo", monthly: summary.monthlyIncome, annual: summary.annualIncome, kind: .income)
            }
            if scope == .all {
                SummaryRow(title: "Neto", monthly: summary.monthlyNet, annual: summary.annualNet, kind: nil)
            }
        } header: {
            Text("Resumen")
        } footer: {
            Text("Cada importe se reparte por su periodicidad: un anual de 600 € cuenta 50 € al mes.")
        }
    }

    private var upcomingSection: some View {
        Section("Próximas") {
            ForEach(upcoming) { item in
                UpcomingRow(item: item)
                    .swipeActions(edge: .trailing) {
                        if !item.isPaid {
                            Button(item.bill.isIncome ? "Cobrada" : "Pagada", systemImage: "checkmark") {
                                payingOccurrence = BillPrefill(bill: item.bill, occurrenceDate: item.date)
                            }
                            .tint(.green)
                        }
                    }
            }
        }
    }

    private func billsSection(_ title: String, _ items: [RecurringBill]) -> some View {
        Section(title) {
            ForEach(items) { bill in
                NavigationLink {
                    BillDetailView(bill: bill)
                } label: {
                    BillRow(bill: bill)
                }
            }
            .onDelete { offsets in delete(offsets, in: items) }
        }
    }

    private var emptyState: some View {
        switch scope {
        case .expense:
            return ContentUnavailableView(
                "Sin gastos recurrentes",
                systemImage: "calendar.badge.clock",
                description: Text("Da de alta la hipoteca, la luz o el seguro y la app calculará cuándo tocan y te avisará antes.")
            )
        case .income:
            return ContentUnavailableView(
                "Sin ingresos recurrentes",
                systemImage: "arrow.down.circle",
                description: Text("Da de alta la nómina, lo que facturas como autónomo o lo que cobras por suscripciones y sabrás con cuánto cuentas cada mes.")
            )
        case .all:
            return ContentUnavailableView(
                "Sin recurrentes",
                systemImage: "calendar.badge.clock",
                description: Text("Da de alta lo que pagas y lo que cobras todos los meses y la app calculará cuándo toca cada cosa.")
            )
        }
    }

    private func delete(_ offsets: IndexSet, in items: [RecurringBill]) {
        for index in offsets {
            let bill = items[index]
            let id = bill.id
            context.delete(bill)
            // Retirar los avisos ANTES de que el objeto desaparezca: despues no
            // hay de donde sacar el identificador.
            Task { await NotificationService.shared.cancelAll(for: id) }
        }
        try? context.save()
        NotificationService.shared.reschedule(context: context)
    }
}

/// Una linea del resumen: el mismo importe visto por mes y por ano.
///
/// `kind` a `nil` es el neto, que no es ni gasto ni ingreso y se colorea por su
/// signo: en rojo significa que los fijos se comen mas de lo que entra.
struct SummaryRow: View {
    let title: String
    let monthly: Decimal
    let annual: Decimal
    let kind: TransactionKind?

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let kind {
                    AmountText(amount: monthly, kind: kind)
                } else {
                    SignedAmountText(value: monthly)
                }
                Text("\(Money.formatted(annual)) al año")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}

/// Una ocurrencia calculada: no existe en base de datos hasta que se paga.
struct UpcomingRow: View {
    let item: RecurringBillService.Upcoming

    var body: some View {
        HStack {
            Image(systemName: item.bill.category?.symbolName ?? defaultSymbol)
                .foregroundStyle(Color(hex: item.bill.category?.colorHex))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.bill.name).lineLimit(1)
                HStack(spacing: 6) {
                    Text(item.date.formatted(.dateTime.day().month(.wide)))
                    Text("·")
                    Text(relativo)
                    if let cuenta = item.bill.account { Text("· \(cuenta.name)") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                AmountText(
                    amount: item.payment?.amount ?? item.bill.estimatedAmount,
                    kind: item.bill.kind
                )
                .opacity(item.isPaid ? 0.6 : 1)

                if item.isPaid {
                    Label(item.bill.isIncome ? "Cobrado" : "Pagada", systemImage: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                } else if item.bill.isVariableAmount {
                    Text("estimado").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var defaultSymbol: String {
        item.bill.isIncome ? "arrow.down.circle" : "calendar"
    }

    private var relativo: String {
        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: Date()),
            to: Calendar.current.startOfDay(for: item.date)
        ).day ?? 0

        switch days {
        case 0:           return "hoy"
        case 1:           return "mañana"
        case ..<0:        return "hace \(-days) d"
        default:          return "en \(days) d"
        }
    }
}

struct BillRow: View {
    let bill: RecurringBill

    var body: some View {
        HStack {
            Image(systemName: bill.category?.symbolName ?? (bill.isIncome ? "arrow.down.circle" : "calendar"))
                .foregroundStyle(Color(hex: bill.category?.colorHex))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(bill.name).lineLimit(1)
                Text(bill.recurrence.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
            AmountText(amount: bill.estimatedAmount, kind: bill.kind)
                .opacity(bill.isActive ? 1 : 0.5)
        }
    }
}

/// `sheet(item:)` necesita `Identifiable`. La identidad de una ocurrencia es
/// factura + fecha, la misma clave que usan los avisos.
extension BillPrefill: Identifiable {
    var id: String { RecurringBillService.key(bill: bill, occurrence: occurrenceDate) }
}
