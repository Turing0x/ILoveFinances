import Foundation
import SwiftData

/// Copia de seguridad completa a CSV, y restauracion desde ella.
///
/// Existe pronto y no al final porque es lo que permite equivocarse sin
/// consecuencias durante el resto del desarrollo. Y porque CloudKit sincroniza
/// pero NO respalda: un borrado se propaga a la nube y a cualquier dispositivo
/// futuro.
///
/// Formato: una carpeta con un CSV por entidad, con las relaciones
/// expresadas por UUID. Carpeta y no fichero unico porque un CSV con secciones
/// separadas por marcas deja de abrirse en Numbers, y eso se pierde a cambio de
/// nada.
enum BackupService {

    enum FileName {
        static let accounts = "accounts.csv"
        static let categories = "categories.csv"
        static let familyTags = "family_tags.csv"
        static let transactions = "transactions.csv"
        static let recurringBills = "recurring_bills.csv"
        static let manifest = "manifest.csv"
    }

    enum BackupError: LocalizedError {
        case missingFile(String)
        case malformedRow(file: String, detail: String)

        var errorDescription: String? {
            switch self {
            case .missingFile(let name):
                return "Falta el fichero \(name) en la carpeta de copia."
            case .malformedRow(let file, let detail):
                return "Fila incorrecta en \(file): \(detail)"
            }
        }
    }

    // MARK: - Exportar

    /// Devuelve el contenido de cada fichero. No escribe en disco: de eso se
    /// encarga la vista con `fileExporter`, que es quien tiene el permiso del
    /// usuario para elegir destino.
    static func export(context: ModelContext) throws -> [String: String] {
        let accounts = try context.fetch(FetchDescriptor<Account>())
        let categories = try context.fetch(FetchDescriptor<TransactionCategory>())
        let familyTags = try context.fetch(FetchDescriptor<FamilyTag>())
        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        let recurringBills = try context.fetch(FetchDescriptor<RecurringBill>())

        return [
            FileName.manifest: CSVCodec.encode(
                header: ["schemaVersion", "exportedAt", "accounts", "categories", "familyTags", "transactions", "recurringBills"],
                rows: [[
                    "\(SchemaV1.versionIdentifier)",
                    CSVCodec.string(from: Date()),
                    "\(accounts.count)", "\(categories.count)",
                    "\(familyTags.count)", "\(transactions.count)",
                    "\(recurringBills.count)",
                ]]
            ),
            FileName.accounts: CSVCodec.encode(
                header: ["id", "name", "type", "openingBalance", "iban", "colorHex", "isArchived", "createdAt"],
                rows: accounts.map { account in
                    [
                        account.id.uuidString, account.name, account.typeRaw,
                        CSVCodec.string(from: account.openingBalance),
                        account.iban ?? "", account.colorHex ?? "",
                        CSVCodec.string(from: account.isArchived),
                        CSVCodec.string(from: account.createdAt),
                    ]
                }
            ),
            FileName.categories: CSVCodec.encode(
                header: ["id", "name", "symbolName", "colorHex", "kind", "isSystem", "sortOrder", "parentID", "createdAt"],
                rows: categories.map { category in
                    [
                        category.id.uuidString, category.name, category.symbolName,
                        category.colorHex, category.kindRaw,
                        CSVCodec.string(from: category.isSystem),
                        "\(category.sortOrder)",
                        CSVCodec.string(from: category.parentID),
                        CSVCodec.string(from: category.createdAt),
                    ]
                }
            ),
            FileName.familyTags: CSVCodec.encode(
                header: ["id", "name", "colorHex", "sortOrder", "createdAt"],
                rows: familyTags.map { tag in
                    [
                        tag.id.uuidString, tag.name, tag.colorHex,
                        "\(tag.sortOrder)", CSVCodec.string(from: tag.createdAt),
                    ]
                }
            ),
            FileName.transactions: CSVCodec.encode(
                header: [
                    "id", "date", "amount", "kind", "note", "merchant",
                    "accountID", "counterpartAccountID", "categoryID", "familyTagID",
                    "isRecurringInstance", "recurringBillID", "occurrenceDate",
                    "importHash", "importBatchID", "createdAt",
                ],
                rows: transactions.map { transaction in
                    [
                        transaction.id.uuidString,
                        CSVCodec.string(from: transaction.date),
                        CSVCodec.string(from: transaction.amount),
                        transaction.kindRaw,
                        transaction.note,
                        transaction.merchant ?? "",
                        CSVCodec.string(from: transaction.account?.id),
                        CSVCodec.string(from: transaction.counterpartAccount?.id),
                        CSVCodec.string(from: transaction.category?.id),
                        CSVCodec.string(from: transaction.familyTag?.id),
                        CSVCodec.string(from: transaction.isRecurringInstance),
                        CSVCodec.string(from: transaction.recurringBill?.id),
                        transaction.occurrenceDate.map(CSVCodec.string(from:)) ?? "",
                        transaction.importHash ?? "",
                        CSVCodec.string(from: transaction.importBatchID),
                        CSVCodec.string(from: transaction.createdAt),
                    ]
                }
            ),
            FileName.recurringBills: CSVCodec.encode(
                header: [
                    "id", "name", "estimatedAmount", "isVariableAmount", "recurrence",
                    "dayOfMonth", "startDate", "endDate", "isActive", "reminderDaysBefore",
                    "accountID", "categoryID", "familyTagID", "createdAt",
                ],
                rows: recurringBills.map { bill in
                    [
                        bill.id.uuidString, bill.name,
                        CSVCodec.string(from: bill.estimatedAmount),
                        CSVCodec.string(from: bill.isVariableAmount),
                        bill.recurrenceRaw,
                        "\(bill.dayOfMonth)",
                        CSVCodec.string(from: bill.startDate),
                        bill.endDate.map(CSVCodec.string(from:)) ?? "",
                        CSVCodec.string(from: bill.isActive),
                        "\(bill.reminderDaysBefore)",
                        CSVCodec.string(from: bill.account?.id),
                        CSVCodec.string(from: bill.category?.id),
                        CSVCodec.string(from: bill.familyTag?.id),
                        CSVCodec.string(from: bill.createdAt),
                    ]
                }
            ),
        ]
    }

    // MARK: - Restaurar

    struct RestoreSummary {
        var accounts = 0
        var categories = 0
        var familyTags = 0
        var transactions = 0
        var recurringBills = 0
    }

    /// **Reemplaza todo.** Borra lo que haya y reconstruye desde el CSV.
    ///
    /// Es lo que se espera de una restauracion, y es destructivo de verdad: con
    /// CloudKit activo el borrado se propaga a la nube. Quien llame a esto debe
    /// haber pedido una confirmacion escrita, no un OK.
    ///
    /// Se parsea TODO antes de borrar nada: si el fichero esta corrupto, la
    /// base de datos se queda como estaba en vez de a medias.
    @discardableResult
    static func restoreReplacingAll(files: [String: String], context: ModelContext) throws -> RestoreSummary {
        let accountRows = try table(FileName.accounts, in: files).rows
        let categoryRows = try table(FileName.categories, in: files).rows
        let familyTagRows = try table(FileName.familyTags, in: files).rows
        let transactionRows = try table(FileName.transactions, in: files).rows
        // Una copia de la Fase 1 no trae facturas: ausente significa "ninguna",
        // no fichero corrupto. Si esto fuese `missingFile`, actualizar la app
        // invalidaria las copias hechas antes de actualizarla.
        let billRows = (try? table(FileName.recurringBills, in: files).rows) ?? []

        // Punto de no retorno.
        try context.delete(model: Transaction.self)
        try context.delete(model: RecurringBill.self)
        try context.delete(model: Account.self)
        try context.delete(model: TransactionCategory.self)
        try context.delete(model: FamilyTag.self)

        var accountsByID: [UUID: Account] = [:]
        for row in accountRows {
            guard let id = CSVCodec.uuid(from: row["id"] ?? "") else {
                throw BackupError.malformedRow(file: FileName.accounts, detail: "id vacio o invalido")
            }
            let account = Account(
                name: row["name"] ?? "",
                type: AccountType(rawValue: row["type"] ?? "") ?? .checking,
                openingBalance: CSVCodec.decimal(from: row["openingBalance"] ?? "") ?? .zero,
                iban: emptyToNil(row["iban"]),
                colorHex: emptyToNil(row["colorHex"])
            )
            account.id = id
            account.isArchived = CSVCodec.bool(from: row["isArchived"] ?? "")
            if let created = CSVCodec.date(from: row["createdAt"] ?? "") { account.createdAt = created }
            context.insert(account)
            accountsByID[id] = account
        }

        var categoriesByID: [UUID: TransactionCategory] = [:]
        for row in categoryRows {
            guard let id = CSVCodec.uuid(from: row["id"] ?? "") else {
                throw BackupError.malformedRow(file: FileName.categories, detail: "id vacio o invalido")
            }
            let category = TransactionCategory(
                id: id,
                name: row["name"] ?? "",
                symbolName: row["symbolName"] ?? "tag",
                colorHex: row["colorHex"] ?? "#888888",
                kind: TransactionKind(rawValue: row["kind"] ?? "") ?? .expense,
                isSystem: CSVCodec.bool(from: row["isSystem"] ?? ""),
                sortOrder: Int(row["sortOrder"] ?? "") ?? 0,
                parentID: CSVCodec.uuid(from: row["parentID"] ?? "")
            )
            if let created = CSVCodec.date(from: row["createdAt"] ?? "") { category.createdAt = created }
            context.insert(category)
            categoriesByID[id] = category
        }

        var tagsByID: [UUID: FamilyTag] = [:]
        for row in familyTagRows {
            guard let id = CSVCodec.uuid(from: row["id"] ?? "") else {
                throw BackupError.malformedRow(file: FileName.familyTags, detail: "id vacio o invalido")
            }
            let tag = FamilyTag(
                name: row["name"] ?? "",
                colorHex: row["colorHex"] ?? "#4A90D9",
                sortOrder: Int(row["sortOrder"] ?? "") ?? 0
            )
            tag.id = id
            if let created = CSVCodec.date(from: row["createdAt"] ?? "") { tag.createdAt = created }
            context.insert(tag)
            tagsByID[id] = tag
        }

        // Las facturas van ANTES que las transacciones: cada pago se engancha a
        // la suya por UUID y para eso tiene que existir ya.
        var billsByID: [UUID: RecurringBill] = [:]
        for row in billRows {
            guard let id = CSVCodec.uuid(from: row["id"] ?? "") else {
                throw BackupError.malformedRow(file: FileName.recurringBills, detail: "id vacio o invalido")
            }
            guard let estimated = CSVCodec.decimal(from: row["estimatedAmount"] ?? "") else {
                throw BackupError.malformedRow(file: FileName.recurringBills, detail: "importe ilegible en \(id)")
            }
            let bill = RecurringBill(
                name: row["name"] ?? "",
                estimatedAmount: estimated,
                isVariableAmount: CSVCodec.bool(from: row["isVariableAmount"] ?? ""),
                recurrence: Recurrence(rawValue: row["recurrence"] ?? "") ?? .monthly,
                dayOfMonth: Int(row["dayOfMonth"] ?? "") ?? 1,
                startDate: CSVCodec.date(from: row["startDate"] ?? "") ?? Date(),
                endDate: CSVCodec.date(from: row["endDate"] ?? ""),
                isActive: CSVCodec.bool(from: row["isActive"] ?? ""),
                reminderDaysBefore: Int(row["reminderDaysBefore"] ?? "") ?? 3,
                account: CSVCodec.uuid(from: row["accountID"] ?? "").flatMap { accountsByID[$0] },
                category: CSVCodec.uuid(from: row["categoryID"] ?? "").flatMap { categoriesByID[$0] },
                familyTag: CSVCodec.uuid(from: row["familyTagID"] ?? "").flatMap { tagsByID[$0] }
            )
            bill.id = id
            if let created = CSVCodec.date(from: row["createdAt"] ?? "") { bill.createdAt = created }
            context.insert(bill)
            billsByID[id] = bill
        }

        for row in transactionRows {
            guard let id = CSVCodec.uuid(from: row["id"] ?? "") else {
                throw BackupError.malformedRow(file: FileName.transactions, detail: "id vacio o invalido")
            }
            guard let amount = CSVCodec.decimal(from: row["amount"] ?? "") else {
                throw BackupError.malformedRow(file: FileName.transactions, detail: "importe ilegible en \(id)")
            }
            let transaction = Transaction(
                date: CSVCodec.date(from: row["date"] ?? "") ?? Date(),
                amount: amount,
                kind: TransactionKind(rawValue: row["kind"] ?? "") ?? .expense,
                note: row["note"] ?? "",
                merchant: emptyToNil(row["merchant"]),
                account: CSVCodec.uuid(from: row["accountID"] ?? "").flatMap { accountsByID[$0] },
                counterpartAccount: CSVCodec.uuid(from: row["counterpartAccountID"] ?? "").flatMap { accountsByID[$0] },
                category: CSVCodec.uuid(from: row["categoryID"] ?? "").flatMap { categoriesByID[$0] },
                familyTag: CSVCodec.uuid(from: row["familyTagID"] ?? "").flatMap { tagsByID[$0] }
            )
            transaction.id = id
            transaction.isRecurringInstance = CSVCodec.bool(from: row["isRecurringInstance"] ?? "")
            transaction.recurringBill = CSVCodec.uuid(from: row["recurringBillID"] ?? "").flatMap { billsByID[$0] }
            transaction.occurrenceDate = CSVCodec.date(from: row["occurrenceDate"] ?? "")
            transaction.importHash = emptyToNil(row["importHash"])
            transaction.importBatchID = CSVCodec.uuid(from: row["importBatchID"] ?? "")
            if let created = CSVCodec.date(from: row["createdAt"] ?? "") { transaction.createdAt = created }
            context.insert(transaction)
        }

        try context.save()

        return RestoreSummary(
            accounts: accountRows.count,
            categories: categoryRows.count,
            familyTags: familyTagRows.count,
            transactions: transactionRows.count,
            recurringBills: billRows.count
        )
    }

    // MARK: - Auxiliares

    private static func table(_ name: String, in files: [String: String]) throws -> CSVCodec.Table {
        guard let text = files[name] else { throw BackupError.missingFile(name) }
        return try CSVCodec.decode(text)
    }

    private static func emptyToNil(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}
