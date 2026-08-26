import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink("Cuentas") { AccountsView() }
                    NavigationLink("Categorías") { CategoriesView() }
                    NavigationLink("Miembros") { FamilyTagsView() }
                    NavigationLink("Tiendas") { ShopsView() }
                    NavigationLink("Productos") { ProductsView() }
                }
                Section {
                    NavigationLink("Copia de seguridad") { BackupView() }
                }
            }
            .navigationTitle("Ajustes")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                }
            }
        }
    }
}

struct AccountsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.createdAt) private var accounts: [Account]
    @State private var showingNew = false

    var body: some View {
        List {
            ForEach(accounts) { account in
                NavigationLink {
                    AccountEditor(account: account)
                } label: {
                    HStack {
                        Label(account.name, systemImage: account.type.symbolName)
                        Spacer()
                        SignedAmountText(value: account.balance, font: .callout)
                    }
                }
            }
            .onDelete(perform: delete)
        }
        .navigationTitle("Cuentas")
        .toolbar {
            Button("Nueva", systemImage: "plus") { showingNew = true }
        }
        .sheet(isPresented: $showingNew) { AccountEditor(account: nil) }
        .overlay {
            if accounts.isEmpty {
                ContentUnavailableView(
                    "Sin cuentas",
                    systemImage: "building.columns",
                    description: Text("Crea la cuenta corriente para empezar. Las tarjetas van como cuenta de tipo Tarjeta, y el efectivo como cuenta Efectivo.")
                )
            }
        }
    }

    private func delete(_ offsets: IndexSet) {
        for index in offsets { context.delete(accounts[index]) }
        try? context.save()
    }
}

struct AccountEditor: View {
    let account: Account?
    /// Tipo con el que se abre un alta nueva. Sirve para que la pestana Bus
    /// pueda llevar directamente a "crear tarjeta de transporte" sin obligar a
    /// buscar el tipo en el selector.
    var initialType: AccountType = .checking

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var type: AccountType = .checking
    @State private var openingText = "0"
    @State private var iban = ""
    @State private var cardNumber = ""
    @State private var fareText = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nombre", text: $name)
                Picker("Tipo", selection: $type) {
                    ForEach(AccountType.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                TextField("Saldo inicial", text: $openingText).keyboardType(.numbersAndPunctuation)

                // Una tarjeta de transporte no tiene IBAN ni aparece en ningun
                // CSV de banco, asi que el campo solo estorbaria.
                if type != .transport {
                    TextField("Últimos 4 del IBAN", text: $iban).keyboardType(.numberPad)
                }

                if type == .transport {
                    Section {
                        TextField("Número de la tarjeta", text: $cardNumber)
                            .keyboardType(.numbersAndPunctuation)
                        TextField("Precio por viaje", text: $fareText)
                            .keyboardType(.decimalPad)
                    } header: {
                        Text("Tarjeta de transporte")
                    } footer: {
                        Text("El saldo sube con cada recarga (un traspaso desde la cuenta que paga) y baja el precio por viaje cada vez que la usas en el bus.")
                    }
                }

                Section {
                    Text("El saldo actual no se guarda: se calcula sumando los movimientos al saldo inicial. Así no puede desincronizarse.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(account == nil ? "Nueva cuenta" : "Cuenta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar", action: save).disabled(!canSave)
                }
            }
            .onAppear(perform: load)
        }
    }

    /// Sin precio por viaje una tarjeta de transporte no sirve para nada: el
    /// boton de la pestana Bus no sabria cuanto descontar. Es el unico campo
    /// que se exige ademas del nombre; el numero de la tarjeta es opcional
    /// porque hay tarjetas anonimas sin numero visible.
    private var canSave: Bool {
        guard !name.isEmpty else { return false }
        guard type == .transport else { return true }
        guard let fare = Money.parseInput(fareText) else { return false }
        return fare > 0
    }

    private func load() {
        guard let account else {
            type = initialType
            return
        }
        name = account.name
        type = account.type
        openingText = Money.csvString(account.openingBalance)
        iban = account.iban ?? ""
        cardNumber = account.transportCardNumber ?? ""
        fareText = account.farePerTrip > 0 ? Money.csvString(account.farePerTrip) : ""
    }

    private func save() {
        let opening = Money.parseInput(openingText) ?? .zero

        // Fuera del tipo transporte los dos campos se limpian: dejarlos puestos
        // en una cuenta corriente seria un dato fantasma que la interfaz ya no
        // muestra y que nadie volveria a corregir.
        let esTransporte = type == .transport
        let numero = esTransporte && !cardNumber.isEmpty ? cardNumber : nil
        let tarifa = esTransporte ? (Money.parseInput(fareText) ?? .zero) : .zero

        if let account {
            account.name = name
            account.type = type
            account.openingBalance = opening
            account.iban = esTransporte || iban.isEmpty ? nil : iban
            account.transportCardNumber = numero
            account.farePerTrip = tarifa
        } else {
            context.insert(Account(name: name, type: type, openingBalance: opening,
                                   iban: esTransporte || iban.isEmpty ? nil : iban,
                                   transportCardNumber: numero,
                                   farePerTrip: tarifa))
        }
        try? context.save()
        dismiss()
    }
}
