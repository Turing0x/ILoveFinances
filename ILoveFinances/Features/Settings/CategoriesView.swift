import SwiftData
import SwiftUI

struct CategoriesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\TransactionCategory.kindRaw), SortDescriptor(\TransactionCategory.sortOrder)])
    private var categories: [TransactionCategory]

    @State private var showingNew = false

    var body: some View {
        List {
            section(for: .expense, title: "Gastos")
            section(for: .income, title: "Ingresos")
        }
        .navigationTitle("Categorías")
        .toolbar { Button("Nueva", systemImage: "plus") { showingNew = true } }
        .sheet(isPresented: $showingNew) { CategoryEditor() }
    }

    private func section(for kind: TransactionKind, title: String) -> some View {
        let roots = categories.filter { $0.kind == kind && $0.parentID == nil }
        return Section(title) {
            ForEach(roots) { parent in
                row(parent)
                ForEach(children(of: parent)) { child in
                    row(child).padding(.leading, 20)
                }
            }
        }
    }

    private func children(of parent: TransactionCategory) -> [TransactionCategory] {
        categories.filter { $0.parentID == parent.id }
    }

    private func row(_ category: TransactionCategory) -> some View {
        HStack {
            Label(category.name, systemImage: category.symbolName)
                .foregroundStyle(Color(hex: category.colorHex))
            Spacer()
            if category.isSystem {
                Image(systemName: "lock").font(.caption).foregroundStyle(.secondary)
            }
        }
        .swipeActions {
            // Las sembradas no se borran: son las que usan las reglas de
            // autocategorizacion y el resto de la app da por hechas.
            if !category.isSystem {
                Button("Borrar", role: .destructive) { delete(category) }
            }
        }
    }

    /// Al borrar una categoria padre hay que subir sus hijas a primer nivel a
    /// mano: la jerarquia va por `parentID: UUID?` y no hay `deleteRule` que lo
    /// haga. Es el precio de no usar una relacion auto-referencial, que bajo
    /// CloudKit es fragil. Las transacciones las desengancha el `.nullify`.
    private func delete(_ category: TransactionCategory) {
        for child in children(of: category) { child.parentID = nil }
        context.delete(category)
        try? context.save()
    }
}

struct CategoryEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TransactionCategory.sortOrder) private var categories: [TransactionCategory]

    @State private var name = ""
    @State private var kind: TransactionKind = .expense
    @State private var symbolName = "tag"
    @State private var parent: TransactionCategory?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nombre", text: $name)
                Picker("Tipo", selection: $kind) {
                    Text("Gasto").tag(TransactionKind.expense)
                    Text("Ingreso").tag(TransactionKind.income)
                }
                TextField("SF Symbol", text: $symbolName)

                Picker("Dentro de", selection: $parent) {
                    Text("Primer nivel").tag(TransactionCategory?.none)
                    // Solo categorias raiz: la jerarquia es de dos niveles como
                    // maximo, y mas niveles complican el desglose del dashboard
                    // sin aportar nada en uso domestico.
                    ForEach(categories.filter { $0.kind == kind && $0.parentID == nil }) {
                        Text($0.name).tag(TransactionCategory?.some($0))
                    }
                }
            }
            .navigationTitle("Nueva categoría")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        context.insert(
                            TransactionCategory(name: name, symbolName: symbolName, kind: kind,
                                     sortOrder: categories.count, parentID: parent?.id)
                        )
                        try? context.save()
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }
}

struct FamilyTagsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \FamilyTag.sortOrder) private var tags: [FamilyTag]
    @State private var newName = ""

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("Nombre", text: $newName)
                    Button("Añadir") {
                        context.insert(FamilyTag(name: newName, sortOrder: tags.count))
                        try? context.save()
                        newName = ""
                    }
                    .disabled(newName.isEmpty)
                }
            }
            ForEach(tags) { tag in
                Label(tag.name, systemImage: "person.circle")
                    .foregroundStyle(Color(hex: tag.colorHex))
            }
            .onDelete { offsets in
                for index in offsets { context.delete(tags[index]) }
                try? context.save()
            }
        }
        .navigationTitle("Miembros")
        .overlay {
            if tags.isEmpty {
                ContentUnavailableView(
                    "Sin miembros",
                    systemImage: "person.2",
                    description: Text("Es solo una etiqueta para saber quién gasta qué. Sin usuarios ni permisos.")
                )
            }
        }
    }
}
