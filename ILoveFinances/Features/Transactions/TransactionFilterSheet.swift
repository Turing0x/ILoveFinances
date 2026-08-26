import SwiftData
import SwiftUI

struct TransactionFilterSheet: View {
    @Binding var filter: TransactionFilter
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Account.name) private var accounts: [Account]
    @Query(sort: \TransactionCategory.sortOrder) private var categories: [TransactionCategory]
    @Query(sort: \FamilyTag.sortOrder) private var familyTags: [FamilyTag]

    @State private var minText = ""
    @State private var maxText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Periodo") {
                    Picker("Periodo", selection: periodSelection) {
                        Text("Todo").tag(0)
                        Text("Mes").tag(1)
                        Text("Trimestre").tag(2)
                        Text("Año").tag(3)
                    }
                    .pickerStyle(.segmented)
                }

                Section("Tipo") {
                    Picker("Tipo", selection: $filter.kind) {
                        Text("Todos").tag(TransactionKind?.none)
                        ForEach(TransactionKind.allCases, id: \.self) {
                            Text($0.label).tag(TransactionKind?.some($0))
                        }
                    }
                }

                Section("Cuenta") {
                    Picker("Cuenta", selection: $filter.accountID) {
                        Text("Todas").tag(UUID?.none)
                        ForEach(accounts) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                }

                Section("Categoría") {
                    Picker("Categoría", selection: $filter.categoryID) {
                        Text("Todas").tag(UUID?.none)
                        ForEach(categories) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                }

                if !familyTags.isEmpty {
                    Section("Miembro") {
                        Picker("Miembro", selection: $filter.familyTagID) {
                            Text("Todos").tag(UUID?.none)
                            ForEach(familyTags) { Text($0.name).tag(UUID?.some($0.id)) }
                        }
                    }
                }

                Section("Importe") {
                    // La Fase 0 confirmo que Decimal funciona en #Predicate,
                    // asi que este filtro baja a la consulta.
                    TextField("Desde", text: $minText).keyboardType(.decimalPad)
                    TextField("Hasta", text: $maxText).keyboardType(.decimalPad)
                }

                Section {
                    Button("Quitar todos los filtros", role: .destructive) {
                        filter = TransactionFilter(period: .currentMonth)
                        minText = ""
                        maxText = ""
                    }
                }
            }
            .navigationTitle("Filtros")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") {
                        filter.minAmount = Self.parse(minText)
                        filter.maxAmount = Self.parse(maxText)
                        dismiss()
                    }
                }
            }
            .onAppear {
                minText = filter.minAmount.map(Money.csvString) ?? ""
                maxText = filter.maxAmount.map(Money.csvString) ?? ""
            }
        }
    }

    private var periodSelection: Binding<Int> {
        Binding(
            get: {
                switch filter.period {
                case .none: return 0
                case .month: return 1
                case .quarter: return 2
                case .year: return 3
                case .custom: return 0
                }
            },
            set: { value in
                switch value {
                case 1: filter.period = .month(Date())
                case 2: filter.period = .quarter(Date())
                case 3: filter.period = .year(Date())
                default: filter.period = nil
                }
            }
        )
    }

    private static func parse(_ raw: String) -> Decimal? {
        Money.parseInput(raw)
    }
}
