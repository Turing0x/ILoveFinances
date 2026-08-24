import SwiftData
import SwiftUI

/// Alta y edicion de un ticket de compra (Fase 5).
///
/// La pantalla que decide si esta funcion se usa o se abandona: un ticket de
/// super son 25 lineas, y cualquier friccion por linea se multiplica por 25.
/// De ahi las tres decisiones de diseno:
///
/// 1. El foco vuelve SOLO al campo de producto tras confirmar cada linea.
/// 2. Un producto que no existe se crea al vuelo, sin preguntar. Los
///    duplicados se limpian luego en Ajustes, con calma; interrumpir el
///    tecleo no se recupera.
/// 3. El total NO se teclea: es la suma de las lineas (decision de la Fase 5).
///
/// Escribe con `@Environment(\.modelContext)` directo, sin servicio, igual que
/// `QuickAddView`.
struct TicketEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// Ticket existente a editar, o nil para uno nuevo.
    let ticket: Transaction?

    @Query(sort: \Shop.sortOrder) private var shops: [Shop]
    @Query(sort: \Account.name) private var accounts: [Account]
    @Query(sort: \TransactionCategory.sortOrder) private var categories: [TransactionCategory]
    @Query(sort: \FamilyTag.sortOrder) private var familyTags: [FamilyTag]
    @Query(sort: \GroceryProduct.name) private var products: [GroceryProduct]
    @Query(sort: \Transaction.date, order: .reverse) private var recent: [Transaction]

    // Cabecera
    @State private var selectedShop: Shop?
    @State private var date = Date()
    @State private var selectedAccount: Account?
    @State private var selectedCategory: TransactionCategory?
    @State private var selectedFamilyTag: FamilyTag?

    // Lineas ya confirmadas, en memoria hasta guardar.
    @State private var draftLines: [DraftLine] = []

    // Fila de entrada
    @State private var nameText = ""
    @State private var quantityText = "1"
    @State private var unit: UnitOfMeasure = .unit
    @State private var amountText = ""
    @State private var isOffer = false
    @State private var editingLineID: UUID?

    // Alta rapida de tienda sin salir de la pantalla
    @State private var showingNewShop = false
    @State private var newShopName = ""

    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case name, quantity, amount
    }

    /// Linea en construccion. Struct y no `PurchaseLine` a proposito: nada se
    /// inserta en la base de datos hasta que se guarda el ticket entero, asi
    /// que cancelar no deja restos ni productos creados a medias.
    struct DraftLine: Identifiable, Equatable {
        let id: UUID
        var rawName: String
        var quantity: Decimal
        var unit: UnitOfMeasure
        var lineTotal: Decimal
        var isOffer: Bool
        /// Producto ya existente, o nil si hay que crearlo al guardar.
        var productID: UUID?
        var productName: String
    }

    var body: some View {
        NavigationStack {
            Form {
                headerSection
                entrySection
                linesSection
            }
            .navigationTitle(ticket == nil ? "Nuevo ticket" : "Ticket")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) { totalBar }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar", action: save).disabled(!canSave)
                }
            }
            .alert("Nueva tienda", isPresented: $showingNewShop) {
                TextField("Nombre", text: $newShopName)
                Button("Cancelar", role: .cancel) { newShopName = "" }
                Button("Crear", action: createShop).disabled(newShopName.isEmpty)
            } message: {
                Text("Como la tengas tú en la cabeza: «Mercadona de casa», «el marroquí de la esquina».")
            }
            .onAppear(perform: load)
        }
    }

    // MARK: - Cabecera

    private var headerSection: some View {
        Section("Ticket") {
            Picker("Tienda", selection: $selectedShop) {
                Text("Sin tienda").tag(Shop?.none)
                ForEach(activeShops) { shop in
                    Text(shop.name).tag(Shop?.some(shop))
                }
            }
            Button("Nueva tienda…", systemImage: "plus.circle") { showingNewShop = true }
                .font(.subheadline)

            DatePicker("Fecha", selection: $date, displayedComponents: .date)

            Picker("Cuenta", selection: $selectedAccount) {
                Text("Sin cuenta").tag(Account?.none)
                ForEach(activeAccounts) { account in
                    Text(account.name).tag(Account?.some(account))
                }
            }
            Picker("Categoría", selection: $selectedCategory) {
                Text("Sin categoría").tag(TransactionCategory?.none)
                ForEach(expenseCategories) { category in
                    Text(category.name).tag(TransactionCategory?.some(category))
                }
            }
            if !familyTags.isEmpty {
                Picker("Miembro", selection: $selectedFamilyTag) {
                    Text("Sin asignar").tag(FamilyTag?.none)
                    ForEach(familyTags) { tag in
                        Text(tag.name).tag(FamilyTag?.some(tag))
                    }
                }
            }
        }
    }

    // MARK: - Fila de entrada

    private var entrySection: some View {
        Section(editingLineID == nil ? "Añadir línea" : "Editando línea") {
            TextField("Producto", text: $nameText)
                .focused($focus, equals: .name)
                .submitLabel(.next)
                .onSubmit { focus = .quantity }

            if !suggestions.isEmpty {
                productShortcuts
            }

            HStack(spacing: 8) {
                TextField("Cant.", text: $quantityText)
                    .keyboardType(.decimalPad)
                    .focused($focus, equals: .quantity)
                    .frame(maxWidth: 70)
                    .monospacedDigit()

                Picker("", selection: $unit) {
                    ForEach(UnitOfMeasure.allCases, id: \.self) { unit in
                        Text(unit.shortLabel).tag(unit)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()

                TextField("Importe", text: $amountText)
                    .keyboardType(.decimalPad)
                    .focused($focus, equals: .amount)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()

                Button {
                    isOffer.toggle()
                } label: {
                    Image(systemName: isOffer ? "tag.fill" : "tag")
                        .foregroundStyle(isOffer ? Color.orange : Color.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isOffer ? "En oferta" : "Sin oferta")
            }

            Button(editingLineID == nil ? "Añadir" : "Guardar línea", action: commitLine)
                .disabled(!canCommitLine)
        }
    }

    /// Sugerencias: sin texto, lo mas comprado en esa tienda; con texto, lo que
    /// casa. Mismo estilo que los atajos de categoria de `QuickAddView`.
    private var suggestions: [GroceryProduct] {
        let disponibles = products.filter { !$0.isArchived }
        guard nameText.isEmpty else {
            let buscado = PurchaseService.normalized(nameText)
            return disponibles
                .filter { PurchaseService.normalized($0.name).contains(buscado) }
                .prefix(12)
                .map { $0 }
        }
        guard let shop = selectedShop else { return Array(disponibles.prefix(12)) }
        let frecuentes = PurchaseService.frequentProducts(at: shop)
        return frecuentes.isEmpty ? Array(disponibles.prefix(12)) : frecuentes
    }

    private var productShortcuts: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(suggestions) { product in
                    Button {
                        pick(product)
                    } label: {
                        Label(product.name, systemImage: product.symbolName)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.tint.opacity(0.15), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Lineas

    private var linesSection: some View {
        Section("Líneas") {
            if draftLines.isEmpty {
                Text("Ninguna todavía.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
            ForEach(draftLines) { line in
                Button { edit(line) } label: { lineRow(line) }
                    .buttonStyle(.plain)
            }
            .onDelete { offsets in
                draftLines.remove(atOffsets: offsets)
            }
        }
    }

    private func lineRow(_ line: DraftLine) -> some View {
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
                if let rate = PurchaseService.unitPrice(
                    lineTotal: line.lineTotal, quantity: line.quantity, unit: line.unit
                ) {
                    Text("·")
                    Text(Money.formattedRate(rate, unit: line.unit.dimension.rateLabel))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
    }

    private var totalBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Total del ticket").font(.caption).foregroundStyle(.secondary)
                Text(Money.formatted(total))
                    .font(.title2.bold())
                    .monospacedDigit()
            }
            Spacer()
            Text("^[\(draftLines.count) línea](inflect: true)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: - Estado derivado

    private var activeShops: [Shop] { shops.filter { !$0.isArchived } }
    private var activeAccounts: [Account] { accounts.filter { !$0.isArchived } }
    private var expenseCategories: [TransactionCategory] { categories.filter { $0.kind == .expense } }

    private var total: Decimal {
        draftLines.reduce(Decimal.zero) { $0 + $1.lineTotal }
    }

    private var parsedQuantity: Decimal? {
        parseDecimal(quantityText).flatMap { $0 > 0 ? $0 : nil }
    }

    private var parsedAmount: Decimal? {
        parseDecimal(amountText)
    }

    private var canCommitLine: Bool {
        !nameText.trimmingCharacters(in: .whitespaces).isEmpty
            && parsedQuantity != nil
            && parsedAmount != nil
    }

    private var canSave: Bool {
        selectedShop != nil && selectedAccount != nil && !draftLines.isEmpty
    }

    /// El teclado decimal escribe con la coma del idioma del movil: se acepta
    /// coma o punto y se parsea con locale POSIX. Mismo criterio que
    /// `QuickAddView.parsedAmount`.
    private func parseDecimal(_ text: String) -> Decimal? {
        let normalized = text
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        return Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
    }

    // MARK: - Acciones

    private func load() {
        guard let ticket else {
            selectedAccount = recent.first?.account ?? activeAccounts.first
            selectedCategory = expenseCategories.first { $0.name.localizedCaseInsensitiveContains("aliment") }
            focus = .name
            return
        }
        selectedShop = ticket.shop
        date = ticket.date
        selectedAccount = ticket.account
        selectedCategory = ticket.category
        selectedFamilyTag = ticket.familyTag
        draftLines = ticket.sortedLines.map { line in
            DraftLine(
                id: line.id,
                rawName: line.rawName,
                quantity: line.quantity,
                unit: line.unit,
                lineTotal: line.lineTotal,
                isOffer: line.isOffer,
                productID: line.product?.id,
                productName: line.product?.name ?? line.rawName
            )
        }
    }

    private func createShop() {
        let shop = Shop(name: newShopName, sortOrder: shops.count)
        context.insert(shop)
        try? context.save()
        selectedShop = shop
        newShopName = ""
    }

    private func pick(_ product: GroceryProduct) {
        nameText = product.name
        unit = product.comparisonUnit
        if let shop = selectedShop, let last = PurchaseService.lastLine(of: product, at: shop) {
            quantityText = Money.csvString(last.quantity)
            unit = last.unit
        }
        focus = .quantity
    }

    private func commitLine() {
        guard let quantity = parsedQuantity, let amount = parsedAmount else { return }
        let nombre = nameText.trimmingCharacters(in: .whitespaces)
        let existente = PurchaseService.match(name: nombre, in: products)

        let nueva = DraftLine(
            id: editingLineID ?? UUID(),
            rawName: nombre,
            quantity: quantity,
            unit: unit,
            lineTotal: amount,
            isOffer: isOffer,
            productID: existente?.id,
            productName: existente?.name ?? nombre
        )

        if let editingLineID, let index = draftLines.firstIndex(where: { $0.id == editingLineID }) {
            draftLines[index] = nueva
        } else {
            draftLines.append(nueva)
        }

        resetEntry()
    }

    private func edit(_ line: DraftLine) {
        editingLineID = line.id
        nameText = line.rawName
        quantityText = Money.csvString(line.quantity)
        unit = line.unit
        amountText = Money.csvString(line.lineTotal)
        isOffer = line.isOffer
        focus = .name
    }

    /// Devolver el foco al campo de producto es toda la ergonomia de teclear
    /// 25 lineas seguidas: sin esto hay que tocar la pantalla en cada una.
    private func resetEntry() {
        editingLineID = nil
        nameText = ""
        quantityText = "1"
        unit = .unit
        amountText = ""
        isOffer = false
        focus = .name
    }

    private func save() {
        guard let shop = selectedShop else { return }

        let target = ticket ?? Transaction()
        if ticket == nil { context.insert(target) }

        // Editar un ticket rehace sus lineas: son pocas y asi no hay que
        // reconciliar altas, bajas y reordenaciones a mano.
        for old in target.sortedLines {
            context.delete(old)
        }

        target.date = date
        target.kind = .expense
        target.note = shop.name
        target.account = selectedAccount
        target.category = selectedCategory
        target.familyTag = selectedFamilyTag
        target.shop = shop
        target.isPurchaseTicket = true

        for (index, draft) in draftLines.enumerated() {
            let product = resolveProduct(for: draft)
            let line = PurchaseLine(
                rawName: draft.rawName,
                quantity: draft.quantity,
                unit: draft.unit,
                lineTotal: draft.lineTotal,
                isOffer: draft.isOffer,
                position: index,
                product: product
            )
            line.id = draft.id
            context.insert(line)
            line.transaction = target
        }

        // El importe del gasto ES la suma de las lineas (decision de la Fase 5).
        target.amount = total

        try? context.save()
        dismiss()
    }

    /// Producto ya existente, o uno nuevo creado al vuelo con la unidad base de
    /// la dimension que se acaba de teclear.
    private func resolveProduct(for draft: DraftLine) -> GroceryProduct? {
        if let id = draft.productID, let existente = products.first(where: { $0.id == id }) {
            return existente
        }
        if let porNombre = PurchaseService.match(name: draft.rawName, in: products) {
            return porNombre
        }
        let nuevo = GroceryProduct(
            name: draft.productName,
            comparisonUnit: draft.unit.dimension.baseUnit
        )
        context.insert(nuevo)
        return nuevo
    }
}
