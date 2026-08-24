import SwiftData
import SwiftUI

/// Lectura de un ticket con su detalle de lineas (Fase 5).
struct TicketDetailView: View {
    let ticket: Transaction

    @State private var editing = false

    var body: some View {
        List {
            Section {
                LabeledContent("Tienda", value: ticket.shop?.name ?? "Sin tienda")
                LabeledContent("Fecha", value: ticket.date.formatted(date: .abbreviated, time: .omitted))
                LabeledContent("Cuenta", value: ticket.account?.name ?? "Sin cuenta")
                if let category = ticket.category {
                    LabeledContent("Categoría") { CategoryChip(category: category) }
                }
                if let tag = ticket.familyTag {
                    LabeledContent("Miembro", value: tag.name)
                }
                LabeledContent("Total") {
                    Text(Money.formatted(ticket.amount))
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
            }

            Section("Líneas") {
                ForEach(ticket.sortedLines) { line in
                    lineRow(line)
                }
            }
        }
        .navigationTitle(ticket.shop?.name ?? "Ticket")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Editar") { editing = true }
            }
        }
        .sheet(isPresented: $editing) {
            TicketEditorView(ticket: ticket)
        }
    }

    private func lineRow(_ line: PurchaseLine) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(line.rawName)
                if line.isOffer {
                    Image(systemName: "tag.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                Spacer()
                Text(Money.formatted(line.lineTotal))
                    .monospacedDigit()
            }
            HStack(spacing: 6) {
                Text("\(Money.csvString(line.quantity)) \(line.unit.shortLabel)")
                if let rate = PurchaseService.unitPrice(of: line) {
                    Text("·")
                    Text(Money.formattedRate(rate, unit: line.unit.dimension.rateLabel))
                }
                if let product = line.product, product.name != line.rawName {
                    Text("·")
                    Text(product.name)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
    }
}
