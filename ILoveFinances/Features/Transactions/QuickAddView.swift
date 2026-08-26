import SwiftData
import SwiftUI

/// Alta rapida. Es la pantalla mas usada de la app y el criterio de cierre la
/// cronometra: registrar un gasto en menos de 10 segundos desde abrir la app.
///
/// De ahi las decisiones de aqui: importe primero y con el teclado ya enfocado,
/// las 6 categorias mas usadas recientemente a un toque, y fecha por defecto
/// hoy. Guardar y cerrar en tres toques.
/// Datos con los que se abre el alta al marcar una factura como pagada.
///
/// La factura no se paga sola: se abre esta misma pantalla con todo relleno y
/// el importe enfocado, porque en las variables —la luz— el importe real casi
/// nunca es el estimado, y confirmarlo es el momento en que se corrige.
struct BillPrefill {
    let bill: RecurringBill
    let occurrenceDate: Date
}

/// Datos con los que se abre el alta al recargar una tarjeta de transporte
/// (Fase 6).
///
/// La recarga es un TRASPASO, no un gasto: el dinero cambia de sitio, y el
/// gasto se reconoce despues, viaje a viaje. Lo unico que se prellena es el
/// destino y el tipo; el importe lo teclea quien recarga, porque cambia cada
/// vez.
struct TransportRechargePrefill: Identifiable {
    let card: Account

    var id: UUID { card.id }
}

struct QuickAddView: View {
    /// `nil` en el alta normal, que se comporta exactamente igual que antes:
    /// esta pantalla no puede perder sus tres toques.
    var prefill: BillPrefill?
    /// Recarga de una tarjeta de transporte. Excluyente con `prefill`.
    var recharge: TransportRechargePrefill?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Account.name) private var accounts: [Account]
    @Query(sort: \TransactionCategory.sortOrder) private var categories: [TransactionCategory]
    @Query(sort: \FamilyTag.sortOrder) private var familyTags: [FamilyTag]
    @Query(sort: \Transaction.date, order: .reverse) private var recent: [Transaction]

    @State private var amountText = ""
    @State private var kind: TransactionKind = .expense
    @State private var date = Date()
    @State private var note = ""
    @State private var selectedAccount: Account?
    @State private var counterpartAccount: Account?
    @State private var selectedCategory: TransactionCategory?
    @State private var selectedFamilyTag: FamilyTag?

    @FocusState private var amountFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("0,00", text: $amountText)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .focused($amountFocused)

                    Picker("Tipo", selection: $kind) {
                        ForEach(TransactionKind.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                if kind != .transfer {
                    Section("Categoría") {
                        if !suggestedCategories.isEmpty {
                            categoryShortcuts
                        }
                        Picker("Todas", selection: $selectedCategory) {
                            Text("Sin categoría").tag(TransactionCategory?.none)
                            ForEach(categoriesForKind) { category in
                                Text(category.name).tag(TransactionCategory?.some(category))
                            }
                        }
                    }
                }

                Section {
                    Picker(kind == .transfer ? "Desde" : "Cuenta", selection: $selectedAccount) {
                        Text("Ninguna").tag(Account?.none)
                        ForEach(activeAccounts) { Text($0.name).tag(Account?.some($0)) }
                    }

                    if kind == .transfer {
                        // El destino excluye la cuenta de origen: un traspaso a
                        // la misma cuenta no significa nada y ademas
                        // descuadraria el saldo, que suma las dos orillas.
                        Picker("Hasta", selection: $counterpartAccount) {
                            Text("Ninguna").tag(Account?.none)
                            ForEach(activeAccounts.filter { $0.id != selectedAccount?.id }) {
                                Text($0.name).tag(Account?.some($0))
                            }
                        }
                    }

                    DatePicker("Fecha", selection: $date, displayedComponents: .date)
                    TextField("Concepto", text: $note)

                    if !familyTags.isEmpty {
                        Picker("Miembro", selection: $selectedFamilyTag) {
                            Text("Ninguno").tag(FamilyTag?.none)
                            ForEach(familyTags) { Text($0.name).tag(FamilyTag?.some($0)) }
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar", action: save).disabled(!canSave)
                }
            }
            .onAppear(perform: load)
        }
    }

    private var title: String {
        if prefill != nil { return "Pagar factura" }
        if recharge != nil { return "Recargar tarjeta" }
        return "Nuevo movimiento"
    }

    /// Con factura, el formulario llega relleno y el foco sigue en el importe:
    /// lo unico que suele cambiar. Con recarga, igual: el destino y el tipo
    /// vienen puestos y solo falta cuanto se ha recargado.
    private func load() {
        amountFocused = true

        if let recharge {
            kind = .transfer
            counterpartAccount = recharge.card
            // Origen: la primera cuenta que NO sea la tarjeta. Recargar una
            // tarjeta desde si misma no significa nada.
            selectedAccount = activeAccounts.first { $0.id != recharge.card.id }
            note = "Recarga \(recharge.card.name)"
            return
        }

        guard let prefill else {
            if selectedAccount == nil { selectedAccount = activeAccounts.first }
            return
        }
        let bill = prefill.bill
        kind = .expense
        amountText = Money.csvString(bill.estimatedAmount)
        date = prefill.occurrenceDate
        note = bill.name
        selectedAccount = bill.account ?? activeAccounts.first
        selectedCategory = bill.category
        selectedFamilyTag = bill.familyTag
    }

    // MARK: - Atajos de categoria

    private var activeAccounts: [Account] { accounts.filter { !$0.isArchived } }

    private var categoriesForKind: [TransactionCategory] {
        categories.filter { $0.kind == kind }
    }

    /// Las 6 mas usadas en los ultimos 200 movimientos del mismo tipo. Mirar
    /// solo lo reciente hace que la lista siga a los habitos en vez de quedarse
    /// anclada al historico.
    private var suggestedCategories: [TransactionCategory] {
        let recientes = recent.prefix(200).filter { $0.kind == kind }
        var frecuencia: [UUID: Int] = [:]
        for transaction in recientes {
            guard let id = transaction.category?.id else { continue }
            frecuencia[id, default: 0] += 1
        }
        return frecuencia
            .sorted { $0.value > $1.value }
            .prefix(6)
            .compactMap { pair in categories.first { $0.id == pair.key } }
    }

    private var categoryShortcuts: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(suggestedCategories) { category in
                    Button {
                        selectedCategory = category
                    } label: {
                        Label(category.name, systemImage: category.symbolName)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Color(hex: category.colorHex)
                                    .opacity(selectedCategory?.id == category.id ? 0.35 : 0.15),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Guardar

    /// Un alta exige importe positivo: `Money.parseInput` acepta cualquier
    /// decimal, el filtro de aqui es lo que impide guardar un gasto de cero.
    private var parsedAmount: Decimal? {
        guard let value = Money.parseInput(amountText), value > 0 else { return nil }
        return value
    }

    private var canSave: Bool {
        guard parsedAmount != nil, selectedAccount != nil else { return false }
        if kind == .transfer { return counterpartAccount != nil }
        return true
    }

    private func save() {
        guard let amount = parsedAmount else { return }
        let transaction = Transaction(
            date: date,
            amount: amount,
            kind: kind,
            note: note,
            account: selectedAccount,
            counterpartAccount: kind == .transfer ? counterpartAccount : nil,
            category: kind == .transfer ? nil : selectedCategory,
            familyTag: selectedFamilyTag
        )
        if let prefill {
            transaction.recurringBill = prefill.bill
            transaction.occurrenceDate = prefill.occurrenceDate
            transaction.isRecurringInstance = true
        }
        context.insert(transaction)
        try? context.save()

        // La ocurrencia pagada deja de necesitar aviso.
        if prefill != nil { NotificationService.shared.reschedule(context: context) }
        dismiss()
    }
}
