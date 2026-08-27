import Charts
import SwiftData
import SwiftUI

/// Detalle de un recurrente: configuracion, lo que viene, y el historial de lo
/// que se ha pagado —o cobrado, si es un ingreso.
///
/// El historial es la razon de ser de la pantalla en las facturas variables:
/// ver que la luz de enero fue un 30 % mas cara que la de diciembre es
/// exactamente el tipo de dato por el que se lleva un control de gastos.
struct BillDetailView: View {
    @Bindable var bill: RecurringBill

    @Environment(\.modelContext) private var context

    @State private var showingEditor = false
    @State private var payingOccurrence: BillPrefill?

    var body: some View {
        List {
            configurationSection
            upcomingSection
            if !payments.isEmpty {
                if payments.count >= 2 { chartSection }
                historySection
            }
        }
        .navigationTitle(bill.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Editar") { showingEditor = true }
            }
        }
        .sheet(isPresented: $showingEditor) { BillEditorView(bill: bill) }
        .sheet(item: $payingOccurrence) { prefill in QuickAddView(prefill: prefill) }
    }

    // MARK: - Datos

    private var payments: [Transaction] { bill.sortedPayments }

    private var upcoming: [RecurringBillService.Upcoming] {
        RecurringBillService.upcoming(bills: [bill], days: 180).prefix(6).map { $0 }
    }

    private var averagePaid: Decimal? {
        guard !payments.isEmpty else { return nil }
        let total = payments.reduce(Decimal.zero) { $0 + $1.amount }
        return Money.rounded(total / Decimal(payments.count))
    }

    // MARK: - Secciones

    private var configurationSection: some View {
        Section {
            LabeledContent("Periodicidad", value: bill.recurrence.label)
            if bill.recurrence.monthStep != nil {
                LabeledContent("Día de cargo", value: "\(bill.dayOfMonth)")
            }
            LabeledContent("Importe estimado") {
                Text(Money.formatted(bill.estimatedAmount)).monospacedDigit()
            }
            if let media = averagePaid {
                LabeledContent(bill.isIncome ? "Media cobrada" : "Media pagada") {
                    Text(Money.formatted(media)).monospacedDigit()
                }
            }
            if let cuenta = bill.account {
                LabeledContent("Cuenta", value: cuenta.name)
            }
            LabeledContent(
                "Aviso",
                value: bill.reminderDaysBefore == 0 ? "El mismo día" : "\(bill.reminderDaysBefore) días antes"
            )
            Toggle(bill.isIncome ? "Activo" : "Activa", isOn: $bill.isActive)
                .onChange(of: bill.isActive) { _, _ in
                    try? context.save()
                    // Desactivar cancela los avisos pendientes de esta factura:
                    // el plan nuevo ya no la incluye y `sync` retira los suyos.
                    NotificationService.shared.reschedule(context: context)
                }
        }
    }

    @ViewBuilder
    private var upcomingSection: some View {
        if bill.isActive {
            Section("Próximas") {
                if upcoming.isEmpty {
                    Text(bill.isIncome ? "Ninguna: el ingreso ya ha terminado." : "Ninguna: la factura ya ha terminado.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(upcoming) { item in
                    UpcomingRow(item: item)
                        .swipeActions(edge: .trailing) {
                            if !item.isPaid {
                                Button(bill.isIncome ? "Cobrada" : "Pagada", systemImage: "checkmark") {
                                    payingOccurrence = BillPrefill(bill: bill, occurrenceDate: item.date)
                                }
                                .tint(.green)
                            }
                        }
                }
            }
        }
    }

    private var chartSection: some View {
        Section("Variación") {
            Chart(payments.reversed()) { payment in
                BarMark(
                    x: .value("Fecha", payment.date, unit: .month),
                    // Unica conversion a Double, y solo para dibujar la altura
                    // de la barra. El importe que se lee sale del Decimal.
                    y: .value("Importe", (payment.amount as NSDecimalNumber).doubleValue)
                )
                .foregroundStyle(Color(hex: bill.category?.colorHex))
            }
            .frame(height: 160)
        }
    }

    private var historySection: some View {
        Section(bill.isIncome ? "Historial de cobros" : "Historial de pagos") {
            ForEach(payments) { payment in
                NavigationLink {
                    TransactionDetailView(transaction: payment)
                } label: {
                    LabeledContent {
                        VStack(alignment: .trailing, spacing: 2) {
                            AmountText(transaction: payment)
                            deviation(payment)
                        }
                    } label: {
                        Text((payment.occurrenceDate ?? payment.date)
                            .formatted(.dateTime.month(.wide).year()))
                    }
                }
            }
        }
    }

    /// Desviacion respecto al estimado. Solo tiene sentido si hay estimado.
    ///
    /// El color se lee al reves en un ingreso: cobrar mas de lo previsto es
    /// buena noticia, pagar mas no.
    @ViewBuilder
    private func deviation(_ payment: Transaction) -> some View {
        if bill.estimatedAmount > 0 {
            let delta = payment.amount - bill.estimatedAmount
            let percent = Money.rounded((delta / bill.estimatedAmount) * 100, scale: 0)
            if delta != 0 {
                let favorable = bill.isIncome ? delta > 0 : delta < 0
                Text("\(delta > 0 ? "+" : "")\(percent.description) %")
                    .font(.caption2)
                    .foregroundStyle(favorable ? .green : .red)
            }
        }
    }
}
