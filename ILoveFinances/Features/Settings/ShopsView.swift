import SwiftData
import SwiftUI

/// Gestion de tiendas (Fase 5).
///
/// Misma forma que `FamilyTagsView`, con archivado: una tienda a la que se
/// deja de ir no se borra —eso dejaria sus tickets sin tienda y hundiria el
/// historial de precios—, se archiva y desaparece de los selectores.
struct ShopsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Shop.sortOrder) private var shops: [Shop]
    @State private var newName = ""

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("Nombre", text: $newName)
                    Button("Añadir") {
                        context.insert(Shop(name: newName, sortOrder: shops.count))
                        try? context.save()
                        newName = ""
                    }
                    .disabled(newName.isEmpty)
                }
            } footer: {
                Text("Un local concreto, como lo tengas tú en la cabeza: «Mercadona de casa», «el marroquí de la esquina». No la cadena.")
            }

            ForEach(activas) { shop in
                shopRow(shop)
                    .swipeActions(edge: .trailing) {
                        Button("Archivar", systemImage: "archivebox") { archive(shop) }
                            .tint(.orange)
                    }
            }

            if !archivadas.isEmpty {
                Section("Archivadas") {
                    ForEach(archivadas) { shop in
                        shopRow(shop)
                            .foregroundStyle(.secondary)
                            .swipeActions(edge: .trailing) {
                                Button("Recuperar", systemImage: "tray.and.arrow.up") { unarchive(shop) }
                                    .tint(.blue)
                            }
                    }
                }
            }
        }
        .navigationTitle("Tiendas")
        .overlay {
            if shops.isEmpty {
                ContentUnavailableView(
                    "Sin tiendas",
                    systemImage: "storefront",
                    description: Text("Añade los sitios donde compras. Comparar precios entre ellos es para lo que sirven.")
                )
            }
        }
    }

    private var activas: [Shop] { shops.filter { !$0.isArchived } }
    private var archivadas: [Shop] { shops.filter(\.isArchived) }

    private func shopRow(_ shop: Shop) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(shop.name, systemImage: "storefront")
                .foregroundStyle(Color(hex: shop.colorHex))
            let compras = (shop.purchases ?? []).count
            if compras > 0 {
                Text("^[\(compras) ticket](inflect: true)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func archive(_ shop: Shop) {
        shop.isArchived = true
        try? context.save()
    }

    private func unarchive(_ shop: Shop) {
        shop.isArchived = false
        try? context.save()
    }
}
