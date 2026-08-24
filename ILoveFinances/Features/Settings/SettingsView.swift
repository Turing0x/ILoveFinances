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

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var type: AccountType = .checking
    @State private var openingText = "0"
    @State private var iban = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nombre", text: $name)
                Picker("Tipo", selection: $type) {
                    ForEach(AccountType.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                TextField("Saldo inicial", text: $openingText).keyboardType(.numbersAndPunctuation)
                TextField("Últimos 4 del IBAN", text: $iban).keyboardType(.numberPad)

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
                    Button("Guardar", action: save).disabled(name.isEmpty)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard let account else { return }
        name = account.name
        type = account.type
        openingText = Money.csvString(account.openingBalance)
        iban = account.iban ?? ""
    }

    private func save() {
        let opening = Decimal(
            string: openingText.replacingOccurrences(of: ",", with: "."),
            locale: Locale(identifier: "en_US_POSIX")
        ) ?? .zero

        if let account {
            account.name = name
            account.type = type
            account.openingBalance = opening
            account.iban = iban.isEmpty ? nil : iban
        } else {
            context.insert(Account(name: name, type: type, openingBalance: opening,
                                   iban: iban.isEmpty ? nil : iban))
        }
        try? context.save()
        dismiss()
    }
}
