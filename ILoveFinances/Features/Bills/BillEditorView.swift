import SwiftData
import SwiftUI

/// Alta y edicion de una factura recurrente.
///
/// Debajo del formulario van las **proximas 6 ocurrencias**, recalculadas en
/// vivo. Es el criterio de cierre de la fase puesto donde se configura: si el
/// dia o la periodicidad estan mal, se ve antes de guardar y no dos meses
/// despues.
struct BillEditorView: View {
    let bill: RecurringBill?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Account.name) private var accounts: [Account]
    @Query(sort: \TransactionCategory.sortOrder) private var categories: [TransactionCategory]
    @Query(sort: \FamilyTag.sortOrder) private var familyTags: [FamilyTag]

    @State private var name = ""
    @State private var amountText = "0"
    @State private var isVariableAmount = false
    @State private var recurrence: Recurrence = .monthly
    @State private var dayOfMonth = 1
    @State private var startDate = Date()
    @State private var hasEndDate = false
    @State private var endDate = Date()
    @State private var isActive = true
    @State private var reminderDaysBefore = 3
    @State private var selectedAccount: Account?
    @State private var selectedCategory: TransactionCategory?
    @State private var selectedFamilyTag: FamilyTag?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nombre", text: $name)
                    TextField("Importe estimado", text: $amountText)
                        .keyboardType(.decimalPad)
                    Toggle("Importe variable", isOn: $isVariableAmount)
                } footer: {
                    Text("Marca importe variable en la luz o el agua: el estimado solo sirve de referencia y el importe real se introduce al pagarla.")
                }

                Section("Cuándo") {
                    Picker("Periodicidad", selection: $recurrence) {
                        ForEach(Recurrence.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    // Semanal y quincenal heredan el dia de la semana de la
                    // fecha de inicio, asi que el dia del mes no pinta nada.
                    if recurrence.monthStep != nil {
                        Picker("Día del mes", selection: $dayOfMonth) {
                            ForEach(1...31, id: \.self) { Text("\($0)").tag($0) }
                        }
                    }
                    DatePicker("Desde", selection: $startDate, displayedComponents: .date)
                    Toggle("Tiene fecha de fin", isOn: $hasEndDate)
                    if hasEndDate {
                        DatePicker("Hasta", selection: $endDate, displayedComponents: .date)
                    }
                }

                Section("Aviso") {
                    Stepper(
                        reminderDaysBefore == 0 ? "El mismo día" : "\(reminderDaysBefore) días antes",
                        value: $reminderDaysBefore, in: 0...30
                    )
                    Toggle("Activa", isOn: $isActive)
                }

                Section("Dónde se carga") {
                    Picker("Cuenta", selection: $selectedAccount) {
                        Text("Ninguna").tag(Account?.none)
                        ForEach(accounts.filter { !$0.isArchived }) { Text($0.name).tag(Account?.some($0)) }
                    }
                    Picker("Categoría", selection: $selectedCategory) {
                        Text("Sin categoría").tag(TransactionCategory?.none)
                        ForEach(categories.filter { $0.kind == .expense }) {
                            Text($0.name).tag(TransactionCategory?.some($0))
                        }
                    }
                    if !familyTags.isEmpty {
                        Picker("Miembro", selection: $selectedFamilyTag) {
                            Text("Ninguno").tag(FamilyTag?.none)
                            ForEach(familyTags) { Text($0.name).tag(FamilyTag?.some($0)) }
                        }
                    }
                }

                Section("Próximas 6") {
                    if preview.isEmpty {
                        Text("Ninguna: revisa la periodicidad y las fechas.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        ForEach(preview, id: \.self) { date in
                            Text(date.formatted(.dateTime.weekday(.wide).day().month(.wide).year()))
                                .font(.callout)
                        }
                    }
                }
            }
            .navigationTitle(bill == nil ? "Nueva factura" : "Factura")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar", action: save).disabled(name.isEmpty)
                }
            }
            .onAppear(perform: load)
        }
    }

    // MARK: - Previsualizacion

    /// Se calcula sobre una factura EN MEMORIA construida con lo que hay en el
    /// formulario, sin insertarla en el contexto: cambiar la periodicidad no
    /// debe tocar la base de datos hasta que se pulsa Guardar.
    private var preview: [Date] {
        let draft = RecurringBill(
            name: name,
            recurrence: recurrence,
            dayOfMonth: dayOfMonth,
            startDate: startDate,
            endDate: hasEndDate ? endDate : nil,
            isActive: isActive
        )
        return RecurringBillService.next(6, of: draft)
    }

    // MARK: - Cargar y guardar

    private func load() {
        guard let bill else { return }
        name = bill.name
        amountText = Money.csvString(bill.estimatedAmount)
        isVariableAmount = bill.isVariableAmount
        recurrence = bill.recurrence
        dayOfMonth = min(max(bill.dayOfMonth, 1), 31)
        startDate = bill.startDate
        hasEndDate = bill.endDate != nil
        endDate = bill.endDate ?? Date()
        isActive = bill.isActive
        reminderDaysBefore = bill.reminderDaysBefore
        selectedAccount = bill.account
        selectedCategory = bill.category
        selectedFamilyTag = bill.familyTag
    }

    private func save() {
        let amount = Decimal(
            string: amountText.replacingOccurrences(of: ",", with: "."),
            locale: Locale(identifier: "en_US_POSIX")
        ) ?? .zero

        if let bill {
            bill.name = name
            bill.estimatedAmount = amount
            bill.isVariableAmount = isVariableAmount
            bill.recurrence = recurrence
            bill.dayOfMonth = dayOfMonth
            bill.startDate = startDate
            bill.endDate = hasEndDate ? endDate : nil
            bill.isActive = isActive
            bill.reminderDaysBefore = reminderDaysBefore
            bill.account = selectedAccount
            bill.category = selectedCategory
            bill.familyTag = selectedFamilyTag
        } else {
            context.insert(
                RecurringBill(
                    name: name,
                    estimatedAmount: amount,
                    isVariableAmount: isVariableAmount,
                    recurrence: recurrence,
                    dayOfMonth: dayOfMonth,
                    startDate: startDate,
                    endDate: hasEndDate ? endDate : nil,
                    isActive: isActive,
                    reminderDaysBefore: reminderDaysBefore,
                    account: selectedAccount,
                    category: selectedCategory,
                    familyTag: selectedFamilyTag
                )
            )
        }
        try? context.save()

        // Cambiar la periodicidad, desactivar o mover el dia invalida los
        // avisos programados. `reschedule` recalcula el plan entero y retira lo
        // que ya no aplica: no quedan huerfanos.
        NotificationService.shared.reschedule(context: context)
        dismiss()
    }
}
