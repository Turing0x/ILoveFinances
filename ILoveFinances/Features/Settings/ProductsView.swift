import SwiftData
import SwiftUI

/// Gestion del catalogo de productos (Fase 5).
///
/// Aqui es donde se limpian los duplicados que deja la entrada rapida de
/// tickets: al teclear se crea el producto al vuelo para no romper el ritmo,
/// asi que "Pan de payes" y "Pan payes" pueden acabar conviviendo.
struct ProductsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \GroceryProduct.name) private var products: [GroceryProduct]
    @State private var editing: GroceryProduct?
    @State private var creating = false
    @State private var search = ""

    var body: some View {
        List {
            ForEach(visibles) { product in
                Button { editing = product } label: {
                    productRow(product)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing) {
                    Button("Archivar", systemImage: "archivebox") {
                        product.isArchived.toggle()
                        try? context.save()
                    }
                    .tint(.orange)
                }
            }
        }
        .navigationTitle("Productos")
        .searchable(text: $search, prompt: "Nombre del producto")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Nuevo", systemImage: "plus") { creating = true }
            }
        }
        .sheet(item: $editing) { product in
            ProductEditor(product: product)
        }
        .sheet(isPresented: $creating) {
            ProductEditor(product: nil)
        }
        .overlay {
            if products.isEmpty {
                ContentUnavailableView(
                    "Sin productos",
                    systemImage: "cart",
                    description: Text("Se van creando solos al apuntar las líneas de un ticket. Aquí se corrigen y se juntan los duplicados.")
                )
            }
        }
    }

    private var visibles: [GroceryProduct] {
        guard !search.isEmpty else { return products }
        return products.filter { $0.name.localizedStandardContains(search) }
    }

    private func productRow(_ product: GroceryProduct) -> some View {
        HStack {
            Label(product.name, systemImage: product.symbolName)
                .foregroundStyle(product.isArchived ? .secondary : .primary)
            Spacer()
            Text(product.comparisonUnit.dimension.rateLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

struct ProductEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let product: GroceryProduct?

    @State private var name = ""
    @State private var comparisonUnit: UnitOfMeasure = .unit
    @State private var symbolName = "cart"
    @State private var note = ""
    @State private var isArchived = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nombre", text: $name)
                } footer: {
                    Text("La marca va dentro del nombre: «Leche entera Hacendado» y «Leche entera Pascual» son productos distintos porque no cuestan lo mismo.")
                }

                Section {
                    Picker("Comparar por", selection: $comparisonUnit) {
                        ForEach(UnitOfMeasure.allCases, id: \.self) { unit in
                            Text(unit.label).tag(unit)
                        }
                    }
                } footer: {
                    Text("Unidad en la que se compara el precio. Las compras en otra unidad de la misma magnitud se convierten solas; las de otra magnitud se quedan fuera de la comparación.")
                }

                Section {
                    TextField("Símbolo (SF Symbol)", text: $symbolName)
                    TextField("Nota", text: $note, axis: .vertical)
                    Toggle("Archivado", isOn: $isArchived)
                }
            }
            .navigationTitle(product == nil ? "Nuevo producto" : "Producto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar", action: save).disabled(name.isEmpty)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard let product else { return }
        name = product.name
        comparisonUnit = product.comparisonUnit
        symbolName = product.symbolName
        note = product.note
        isArchived = product.isArchived
    }

    private func save() {
        let target = product ?? GroceryProduct()
        target.name = name
        target.comparisonUnit = comparisonUnit
        target.symbolName = symbolName.isEmpty ? "cart" : symbolName
        target.note = note
        target.isArchived = isArchived
        if product == nil { context.insert(target) }
        try? context.save()
        dismiss()
    }
}
