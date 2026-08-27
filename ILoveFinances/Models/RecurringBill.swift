import Foundation
import SwiftData

/// Movimiento recurrente: hipoteca, luz, seguro, cuota del gimnasio — y desde
/// la Fase 7 tambien lo que ENTRA todos los meses: nomina, servicios facturados
/// como autonomo, suscripciones de apps y webs.
///
/// El tipo lo decide `kind`. La clase sigue llamandose `RecurringBill` a
/// proposito: renombrarla renombraria el `RecordType` de CloudKit, que ya esta
/// desplegado en Production, y eso no es una operacion aditiva.
///
/// **Las ocurrencias futuras NO se materializan en base de datos** (PLAN.md
/// seccion 3). Se calculan al vuelo en `RecurringBillService` desde
/// `recurrence` + `dayOfMonth` + `startDate`. Materializarlas obliga a
/// regenerar y limpiar filas cada vez que cambia la periodicidad, y bajo
/// CloudKit genera duplicados. Solo cuando el usuario marca "pagada" se crea
/// una `Transaction` real enlazada por `recurringBill`.
///
/// El `notificationID: String?` que aparecia en el plan no esta aqui a
/// proposito: los identificadores de aviso son deterministas por ocurrencia
/// (`bill-<uuid>-<yyyy-MM-dd>`, ver `NotificationPlanner`), asi que un campo
/// que guardase uno solo sobraria — y en CloudKit un campo que sobra ya no se
/// puede borrar.
@Model
final class RecurringBill {
    var id: UUID = UUID()
    var name: String = ""                    // "Endesa", "Hipoteca"
    var estimatedAmount: Decimal = Decimal.zero
    var isVariableAmount: Bool = false        // la luz si, la hipoteca no
    /// `expense` o `income`. Raw con valor por defecto: es lo que hace que las
    /// filas ya sincronizadas antes de la Fase 7 sigan siendo gastos sin
    /// migracion de datos ninguna.
    var kindRaw: String = TransactionKind.expense.rawValue
    var recurrenceRaw: String = Recurrence.monthly.rawValue
    var dayOfMonth: Int = 1                   // dia previsto de cargo
    var startDate: Date = Date()
    var endDate: Date?                        // nil = indefinida
    var isActive: Bool = true
    var reminderDaysBefore: Int = 3
    var createdAt: Date = Date()

    var account: Account?
    var category: TransactionCategory?
    var familyTag: FamilyTag?

    @Relationship(deleteRule: .nullify, inverse: \Transaction.recurringBill)
    var payments: [Transaction]? = []

    init(
        name: String = "",
        estimatedAmount: Decimal = .zero,
        isVariableAmount: Bool = false,
        kind: TransactionKind = .expense,
        recurrence: Recurrence = .monthly,
        dayOfMonth: Int = 1,
        startDate: Date = Date(),
        endDate: Date? = nil,
        isActive: Bool = true,
        reminderDaysBefore: Int = 3,
        account: Account? = nil,
        category: TransactionCategory? = nil,
        familyTag: FamilyTag? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.estimatedAmount = estimatedAmount
        self.isVariableAmount = isVariableAmount
        self.kindRaw = kind == .income ? TransactionKind.income.rawValue : TransactionKind.expense.rawValue
        self.recurrenceRaw = recurrence.rawValue
        self.dayOfMonth = dayOfMonth
        self.startDate = startDate
        self.endDate = endDate
        self.isActive = isActive
        self.reminderDaysBefore = reminderDaysBefore
        self.createdAt = Date()
        self.account = account
        self.category = category
        self.familyTag = familyTag
    }

    /// Un recurrente es gasto o ingreso; `.transfer` no significa nada aqui y
    /// el getter lo normaliza a gasto, igual que hace con un raw corrupto.
    var kind: TransactionKind {
        get {
            let value = TransactionKind(rawValue: kindRaw) ?? .expense
            return value == .income ? .income : .expense
        }
        set { kindRaw = (newValue == .income ? TransactionKind.income : .expense).rawValue }
    }

    var isIncome: Bool { kind == .income }

    var recurrence: Recurrence {
        get { Recurrence(rawValue: recurrenceRaw) ?? .monthly }
        set { recurrenceRaw = newValue.rawValue }
    }

    /// Pagos —o cobros— ordenados de mas reciente a mas antiguo. Es lo que alimenta el
    /// historial y el grafico de variacion de la pantalla de detalle.
    var sortedPayments: [Transaction] {
        (payments ?? []).sorted { $0.date > $1.date }
    }
}
