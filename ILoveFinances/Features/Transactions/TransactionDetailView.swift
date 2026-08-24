import SwiftData
import SwiftUI

struct TransactionDetailView: View {
    @Bindable var transaction: Transaction

    @Environment(\.modelContext) private var context
    @Query(sort: \Account.name) private var accounts: [Account]
    @Query(sort: \TransactionCategory.sortOrder) private var categories: [TransactionCategory]
    @Query(sort: \FamilyTag.sortOrder) private var familyTags: [FamilyTag]

    @State private var amountText = ""

    var body: some View {
        Form {
            Section {
                TextField("Importe", text: $amountText)
                    .keyboardType(.decimalPad)
                    .onChange(of: amountText) { _, new in
                        if let value = Self.parse(new), value > 0 { transaction.amount = value }
                    }

                Picker("Tipo", selection: Binding(
                    get: { transaction.kind },
                    set: { transaction.kind = $0 }
                )) {
                    ForEach(TransactionKind.allCases, id: \.self) { Text($0.label).tag($0) }
                }

                DatePicker("Fecha", selection: $transaction.date, displayedComponents: .date)
                TextField("Concepto", text: $transaction.note)
                TextField("Comercio", text: Binding(
                    get: { transaction.merchant ?? "" },
                    set: { transaction.merchant = $0.isEmpty ? nil : $0 }
                ))
            }

            Section {
                Picker(transaction.kind == .transfer ? "Desde" : "Cuenta", selection: $transaction.account) {
                    Text("Ninguna").tag(Account?.none)
                    ForEach(accounts) { Text($0.name).tag(Account?.some($0)) }
                }

                if transaction.kind == .transfer {
                    Picker("Hasta", selection: $transaction.counterpartAccount) {
                        Text("Ninguna").tag(Account?.none)
                        ForEach(accounts.filter { $0.id != transaction.account?.id }) {
                            Text($0.name).tag(Account?.some($0))
                        }
                    }
                } else {
                    Picker("Categoría", selection: $transaction.category) {
                        Text("Sin categoría").tag(TransactionCategory?.none)
                        ForEach(categories.filter { $0.kind == transaction.kind }) {
                            Text($0.name).tag(TransactionCategory?.some($0))
                        }
                    }
                }

                Picker("Miembro", selection: $transaction.familyTag) {
                    Text("Ninguno").tag(FamilyTag?.none)
                    ForEach(familyTags) { Text($0.name).tag(FamilyTag?.some($0)) }
                }
            }

            if transaction.isPurchaseTicket {
                Section {
                    NavigationLink {
                        TicketDetailView(ticket: transaction)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(transaction.shop?.name ?? "Sin tienda")
                            Text("^[\(transaction.sortedLines.count) línea](inflect: true) con su precio por unidad")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Compra")
                } footer: {
                    Text("El importe de este gasto es la suma de las líneas del ticket. Para cambiarlo, edita las líneas.")
                }
            }

            if transaction.kind == .transfer {
                Section {
                    Text("Un traspaso entre cuentas propias no cuenta como gasto ni como ingreso: mueve el saldo de las dos cuentas y aporta cero al resumen del periodo.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Movimiento")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { amountText = Money.csvString(transaction.amount) }
        .onDisappear { try? context.save() }
    }

    private static func parse(_ raw: String) -> Decimal? {
        Decimal(
            string: raw.replacingOccurrences(of: ",", with: "."),
            locale: Locale(identifier: "en_US_POSIX")
        )
    }
}
