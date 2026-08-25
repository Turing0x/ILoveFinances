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
    @State private var discountText = ""
    @State private var isOffer = false
    @State private var editingLineID: UUID?

    // Alta rapida de tienda sin salir de la pantalla
    @State private var showingNewShop = false
    @State private var newShopName = ""

    // Importacion desde el JSON que devuelve Claude al leer la foto del ticket
    @State private var showingImport = false
    @State private var importWarnings: [String] = []

    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case name, quantity, amount, discount
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
                warningsSection
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
            .sheet(isPresented: $showingImport) {
                TicketImportSheet(onImport: apply)
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

            Button("Pegar ticket en JSON…", systemImage: "doc.on.clipboard") {
                showingImport = true
            }
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

    /// Lo que el modelo de lenguaje no supo leer, o leyo raro. Se muestra
    /// hasta que el usuario lo descarta: importar un ticket a ciegas es como
    /// se cuelan importes mal leidos de una foto.
    @ViewBuilder
    private var warningsSection: some View {
        if !importWarnings.isEmpty {
            Section {
                ForEach(importWarnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                }
                Button("Entendido", role: .cancel) { importWarnings = [] }
                    .font(.subheadline)
            } header: {
                Text("Revisa esto")
            }
            .foregroundStyle(.orange)
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
                    .submitLabel(.next)
                    .onSubmit { focus = .discount }

                Button {
                    isOffer.toggle()
                } label: {
                    Image(systemName: isOffer ? "tag.fill" : "tag")
                        .foregroundStyle(isOffer ? Color.orange : Color.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isOffer ? "En oferta" : "Sin oferta")
            }

            LabeledContent("Descuento") {
                TextField("0,00", text: $discountText)
                    .keyboardType(.decimalPad)
                    .focused($focus, equals: .discount)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
            }

            if let pagado = payableAmount, (parsedDiscount ?? 0) > 0 {
                HStack(spacing: 6) {
                    Text("Pagado:")
                    Text(Money.formatted(pagado)).fontWeight(.medium)
                    if let cantidad = parsedQuantity,
                       let rate = PurchaseService.unitPrice(
                        lineTotal: pagado, quantity: cantidad, unit: unit
                       ) {
                        Text("·")
                        Text(Money.formattedRate(rate, unit: unit.dimension.rateLabel))
                    }
                }
                .font(.caption)
                .foregroundStyle(pagado < 0 ? Color.red : Color.secondary)
                .monospacedDigit()
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

    /// Vacio significa "sin descuento", no error. El campo es opcional y el
    /// caso mayoritario de una linea es no llevar ninguno.
    private var parsedDiscount: Decimal? {
        guard !discountText.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return parseDecimal(discountText).map { abs($0) }
    }

    /// Lo que se guarda en la linea: el importe impreso menos su descuento.
    ///
    /// El desglose NO se persiste — `PurchaseLine` no tiene campo para el
    /// descuento y anadirlo pedia `SchemaV2` con el esquema ya en Production.
    /// El descuento es una ayuda al teclear: se meten los dos numeros del papel
    /// y la app resta, que es lo que evita restar de cabeza en cada linea.
    private var payableAmount: Decimal? {
        guard let amount = parsedAmount else { return nil }
        return amount - (parsedDiscount ?? 0)
    }

    private var canCommitLine: Bool {
        guard !nameText.trimmingCharacters(in: .whitespaces).isEmpty,
              parsedQuantity != nil,
              parsedAmount != nil else { return false }

        // Un descuento escrito a medias no puede colarse como "sin descuento".
        let descuentoEscrito = !discountText.trimmingCharacters(in: .whitespaces).isEmpty
        if descuentoEscrito && parsedDiscount == nil { return false }

        // Descontar mas de lo que costo dejaria la linea en negativo.
        guard let pagado = payableAmount, pagado >= 0 else { return false }

        return true
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

    /// Vuelca el ticket importado en el formulario. NO guarda nada: deja todo
    /// listo para revisar, que es el punto — el modelo de lenguaje lee una
    /// foto y se equivoca, y el papel esta delante para comprobarlo.
    private func apply(_ ticket: TicketImportService.ParsedTicket) {
        if let fecha = ticket.date { date = fecha }

        // La tienda del ticket ("MERCADONA") casi nunca coincide con el nombre
        // que usa Raul ("Mercadona de casa"), asi que se intenta casar y, si no
        // sale, se deja el picker como estaba y se avisa. Crear tiendas solas
        // llenaria la lista de duplicados de la misma cadena.
        if selectedShop == nil, let nombre = ticket.shopName {
            let buscado = PurchaseService.normalized(nombre)
            selectedShop = activeShops.first { tienda in
                let propio = PurchaseService.normalized(tienda.name)
                return propio == buscado || propio.contains(buscado) || buscado.contains(propio)
            }
        }

        let nuevas = ticket.lines.enumerated().map { index, line in
            DraftLine(
                id: UUID(),
                rawName: line.rawName,
                quantity: line.quantity,
                unit: line.unit,
                lineTotal: line.lineTotal,
                isOffer: line.isOffer,
                productID: PurchaseService.match(name: line.productName, in: products)?.id,
                productName: line.productName
            )
        }
        draftLines.append(contentsOf: nuevas)

        var avisos = ticket.warnings
        if ticket.discountTotal > 0 {
            avisos.append(
                "Se aplicaron \(Money.formatted(ticket.discountTotal)) en descuentos. Esas líneas quedan marcadas como oferta."
            )
        }
        if selectedShop == nil, let nombre = ticket.shopName {
            avisos.append("El ticket es de «\(nombre)» y no hay ninguna tienda que se le parezca. Elígela o créala arriba.")
        }
        if let diferencia = ticket.totalMismatch {
            avisos.append(
                "El ticket dice \(Money.formatted(ticket.declaredTotal ?? .zero)) y las líneas suman \(Money.formatted(ticket.linesTotal)): faltan \(Money.formatted(diferencia)). Puede ser un descuento del súper o una línea mal leída."
            )
        }
        importWarnings = avisos
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
        guard let quantity = parsedQuantity, let pagado = payableAmount else { return }
        let nombre = nameText.trimmingCharacters(in: .whitespaces)
        let existente = PurchaseService.match(name: nombre, in: products)
        let descuento = parsedDiscount ?? 0

        let nueva = DraftLine(
            id: editingLineID ?? UUID(),
            rawName: nombre,
            quantity: quantity,
            unit: unit,
            lineTotal: pagado,
            // Un descuento es una oferta puntual: se marca sola para que quede
            // fuera del ranking por defecto sin tener que acordarse.
            isOffer: isOffer || descuento > 0,
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

    /// El campo de descuento sale VACIO y el importe muestra lo pagado, no el
    /// bruto: el desglose no se guarda en ninguna parte (ver `payableAmount`).
    /// No es un fallo — lo pagado, que es el dato real, esta intacto.
    private func edit(_ line: DraftLine) {
        editingLineID = line.id
        nameText = line.rawName
        quantityText = Money.csvString(line.quantity)
        unit = line.unit
        amountText = Money.csvString(line.lineTotal)
        discountText = ""
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
        discountText = ""
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

        // Cache de los productos creados en ESTE guardado. Sin ella, dos lineas
        // del mismo producto nuevo —dos bandejas de tomate, o un ticket
        // importado con repetidos— crearian dos `GroceryProduct` distintos: el
        // @Query de `products` no se refresca dentro del bucle.
        var creados: [String: GroceryProduct] = [:]

        for (index, draft) in draftLines.enumerated() {
            let product = resolveProduct(for: draft, creados: &creados)
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
    private func resolveProduct(for draft: DraftLine, creados: inout [String: GroceryProduct]) -> GroceryProduct? {
        if let id = draft.productID, let existente = products.first(where: { $0.id == id }) {
            return existente
        }
        if let porNombre = PurchaseService.match(name: draft.productName, in: products) {
            return porNombre
        }
        if let porLiteral = PurchaseService.match(name: draft.rawName, in: products) {
            return porLiteral
        }

        let clave = PurchaseService.normalized(draft.productName)
        if let yaCreado = creados[clave] { return yaCreado }

        let nuevo = GroceryProduct(
            name: draft.productName,
            comparisonUnit: draft.unit.dimension.baseUnit
        )
        context.insert(nuevo)
        creados[clave] = nuevo
        return nuevo
    }
}

/// Pegar el JSON que devuelve Claude tras leer la foto del ticket.
///
/// Solo texto: la app no lee imagenes ni hace OCR. El modelo de lenguaje
/// trabaja fuera, y aqui entra lo que el usuario copia.
struct TicketImportSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onImport: (TicketImportService.ParsedTicket) -> Void

    @State private var text = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button("Pegar del portapapeles", systemImage: "clipboard") {
                        text = UIPasteboard.general.string ?? ""
                        errorMessage = nil
                    }
                } footer: {
                    Text("Pídele a Claude que lea la foto del ticket con el prompt guardado y pega aquí su respuesta. El bloque ```json sobra, pero no molesta.")
                }

                Section("JSON") {
                    TextEditor(text: $text)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 220)
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Importar ticket")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Importar", action: importar)
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func importar() {
        do {
            let ticket = try TicketImportService.parse(text)
            onImport(ticket)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
