import SwiftData
import SwiftUI

/// Pestana de Facturas (PLAN.md seccion 6).
///
/// Dos secciones: lo que viene en los proximos 60 dias —calculado, no
/// almacenado— y el listado completo de facturas dadas de alta.
struct BillsView: View {
    @Environment(\.modelContext) private var context

    @Query(sort: \RecurringBill.name) private var bills: [RecurringBill]

    @State private var showingNew = false
    @State private var payingOccurrence: BillPrefill?

    /// Ventana de "proximas". Coincide con la del planificador de avisos a
    /// proposito: lo que se ve es exactamente lo que se va a avisar.
    private static let windowDays = NotificationPlanner.defaultWindowDays

    var body: some View {
        NavigationStack {
            List {
                if !upcoming.isEmpty { upcomingSection }
                if !active.isEmpty { billsSection("Activas", active) }
                if !inactive.isEmpty { billsSection("Desactivadas", inactive) }
            }
            .navigationTitle("Facturas")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Nueva", systemImage: "plus") { showingNew = true }
                }
            }
            .sheet(isPresented: $showingNew) { BillEditorView(bill: nil) }
            .sheet(item: $payingOccurrence) { prefill in
                QuickAddView(prefill: prefill)
            }
            .overlay {
                if bills.isEmpty {
                    ContentUnavailableView(
                        "Sin facturas",
                        systemImage: "calendar.badge.clock",
                        description: Text("Da de alta la hipoteca, la luz o el seguro y la app calculará cuándo tocan y te avisará antes.")
                    )
                }
            }
        }
    }

    // MARK: - Datos

    private var active: [RecurringBill] { bills.filter(\.isActive) }
    private var inactive: [RecurringBill] { bills.filter { !$0.isActive } }

    private var upcoming: [RecurringBillService.Upcoming] {
        RecurringBillService.upcoming(bills: active, days: Self.windowDays)
    }

    // MARK: - Secciones

    private var upcomingSection: some View {
        Section("Próximas") {
            ForEach(upcoming) { item in
                UpcomingRow(item: item)
                    .swipeActions(edge: .trailing) {
                        if !item.isPaid {
                            Button("Pagada", systemImage: "checkmark") {
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

/// Una ocurrencia calculada: no existe en base de datos hasta que se paga.
struct UpcomingRow: View {
    let item: RecurringBillService.Upcoming

    var body: some View {
        HStack {
            Image(systemName: item.bill.category?.symbolName ?? "calendar")
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
                Text(Money.formatted(item.payment?.amount ?? item.bill.estimatedAmount))
                    .monospacedDigit()
                    .foregroundStyle(item.isPaid ? .secondary : .primary)
                if item.isPaid {
                    Label("Pagada", systemImage: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                } else if item.bill.isVariableAmount {
                    Text("estimado").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
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
            Image(systemName: bill.category?.symbolName ?? "calendar")
                .foregroundStyle(Color(hex: bill.category?.colorHex))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(bill.name).lineLimit(1)
                Text(bill.recurrence.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
            Text(Money.formatted(bill.estimatedAmount))
                .monospacedDigit()
                .foregroundStyle(bill.isActive ? .primary : .secondary)
        }
    }
}

/// `sheet(item:)` necesita `Identifiable`. La identidad de una ocurrencia es
/// factura + fecha, la misma clave que usan los avisos.
extension BillPrefill: Identifiable {
    var id: String { RecurringBillService.key(bill: bill, occurrence: occurrenceDate) }
}
