# ILoveFinances GF — Plan de desarrollo

App **iPhone** de finanzas familiares para uso personal de Raúl. SwiftUI + SwiftData, **iOS 26+**, euro como única divisa, sin backend propio.

Estado del documento: **Fases 0, 1, 2 y 5 cerradas** (24 de agosto de 2026; resultados de la Fase 0 en `docs/fase0-resultados.md`). **Esquema desplegado a CloudKit Production el 24/08/2026**: desde esa fecha, todo cambio de modelo exige `SchemaV2` + `MigrationStage`. En Production hay **7 de los 10** `RecordType`; los tres que faltan se despliegan cuando se usen (ver §8). La Fase 3 puede empezar.

> La **Fase 5** (tickets de compra y comparador de precios) no estaba planificada y se adelanto a las Fases 3 y 4: necesitaba entrar en el esquema v1 **antes** del despliegue a Production, que es la ultima ventana en que se pueden anadir entidades en sitio. Ver la seccion de fases.

**Decisiones cerradas** (ver §8): solo iPhone · coste medio ponderado · tarjetas de crédito como `Account` · efectivo como cuenta `cash` con ajuste mensual · precios de inversión híbridos empezando en manual · backup a CSV en Fase 1 · 1 año de histórico importado.

**Datos firmes del proyecto:**

| | |
|---|---|
| Bundle ID | `dev.threedots.ilovefinances` |
| Contenedor CloudKit | `iCloud.dev.threedots.ilovefinances` |
| Team | `M2J9PP4RR8` |
| Deployment target | iOS 26.0 |
| Modo de lenguaje | Swift 5 (compilador 6.3) |
| Proyecto Xcode | generado con XcodeGen desde `project.yml`; el `.xcodeproj` no va a git |

---

## 1. Visión y alcance

### Qué hace

Un único registro de la vida financiera de la casa, con cuatro bloques:

1. **Ingresos y gastos.** Transacciones con importe, fecha, cuenta, categoría y, opcionalmente, el miembro de la familia al que se atribuyen. Entrada manual rápida y, más adelante, importación desde el CSV que exporta el banco.
2. **Compras y facturas.** Facturas recurrentes (luz, hipoteca, seguros, colegio) con fecha prevista y recordatorio local. Cuando llega el cargo, se marca como pagada y genera la transacción real.
3. **Inversiones.** Cartera de activos (acciones, ETFs, fondos, cripto) con movimientos de compra/venta, coste medio, P&L realizado y no realizado.
4. **Dashboard.** Saldo total, gasto del mes por categoría, comparativa con el mes anterior, próximas facturas, valor de la cartera.

CloudKit en la base de datos **privada** del usuario. Con un único dispositivo su valor no es sincronizar: es **continuidad** — cambio de iPhone, restauración tras pérdida, y no perder cinco años de movimientos si el móvil se cae al mar. No es una copia de seguridad (ver riesgo de borrado propagado en §8); por eso la Fase 1 incluye export a CSV.

### Qué NO hace — explícito

Estas exclusiones no son "para más adelante", son decisiones de diseño. Si alguna cambia, el modelo de datos hay que revisarlo entero.

| No hace | Por qué |
|---|---|
| Login, cuentas de usuario, registro | Un solo usuario. Meter auth añade servidor, sesiones y recuperación de contraseña para cero beneficio. |
| Multiusuario, permisos, roles | El "miembro de la familia" es una etiqueta en la transacción. No hay nadie más usando la app. |
| Multidivisa, tipos de cambio | Todo en euros. Si en el futuro hay un activo en USD, se decide entonces (ver §8). |
| Conexión bancaria automática (PSD2, Plaid, Tink) | Coste recurrente, alta como TPP o intermediario, y fricción legal desproporcionada para uso personal. El CSV cubre el 90% del valor. |
| Compartir presupuestos o cartera con terceros | CloudKit se usa solo en base de datos privada. Nada de `CKShare`. |
| Web app, versión Android, iPad, widget de macOS | **Solo iPhone.** Descartar iPad ahorra `NavigationSplitView`, layout adaptativo y una segunda pasada de pruebas en cada pantalla. |
| Cifrado propio de la base de datos | Data Protection de iOS + Keychain de CloudKit son suficientes para un dispositivo personal con código de acceso. |
| Presupuestos con reglas complejas (envelope budgeting, rollover) | Fase futura como mucho. El MVP muestra gasto real, no gasto planificado. |
| Asesoramiento fiscal o cálculo de IRPF | La app calcula P&L. No modela retenciones ni FIFO fiscal español (ver §8, decisión abierta). |

---

## 2. Arquitectura

### Patrón: MV con SwiftData, no MVVM por defecto

SwiftData ya expone modelos observables (`@Model` genera conformidad con `Observable`). Meter un `ViewModel` entre la vista y `@Query` obliga a duplicar el estado y a perder la actualización automática de las consultas. Así que:

- **Vistas de listado y detalle:** usan `@Query` directamente. Cero ViewModel.
- **Vistas con lógica no trivial** (importador CSV, formulario de movimiento de inversión, cálculo de proyecciones): sí llevan un objeto `@Observable` propio, porque tienen estado que no vive en la base de datos (fichero parseado, mapeo de columnas, errores de validación).

Regla práctica: si el estado de la pantalla es "lo que hay en la base de datos", `@Query`. Si hay estado intermedio que puede descartarse sin guardar, un `@Observable`.

### Capas

```
Views (SwiftUI)
  ↓ @Query / @Environment(\.modelContext)
Models (@Model SwiftData) + extensiones de cálculo
  ↓
Services (sin estado, sin UI)
  · CSVImportService      → parseo, mapeo, detección de duplicados
  · RecurringBillService  → genera próximas ocurrencias, programa notificaciones
  · PortfolioService      → coste medio, P&L, valoración
  · NotificationService   → wrapper de UNUserNotificationCenter
Persistence
  · ModelContainer + configuración CloudKit
```

Los servicios son structs o enums con métodos estáticos/puros siempre que se pueda. Reciben lo que necesitan por parámetro y devuelven valores; no guardan `ModelContext` como propiedad. Esto los hace testeables sin levantar un contenedor.

### Concurrencia: modo Swift 5, todo en el hilo principal

Xcode 26 activa Swift 6 estricto por defecto en proyectos nuevos. Aquí se fija **modo de lenguaje Swift 5** explícitamente (`SWIFT_VERSION = 5.0` en `project.yml`), y la razón es concreta: ni `ModelContext` ni las clases `@Model` son `Sendable`. En modo 6 cada servicio que toque la base de datos exige `@ModelActor` y una capa de conversión a tipos `Sendable` para cruzar la frontera de aislamiento.

Para una app personal, de un solo usuario, con datos locales y sin operaciones largas salvo la importación de CSV, ese coste no compra nada. La regla práctica: **todo lo que toque `ModelContext` vive en `@MainActor`.** Si la importación de un CSV grande llega a bloquear la interfaz —cosa que hay que medir, no suponer—, se aísla ese servicio concreto en un `@ModelActor` sin migrar el resto.

Migrar a Swift 6 después es posible y el proyecto es pequeño. Empezar por ahí habría gastado las primeras horas peleando con el compilador en vez de con el problema.

### Organización de carpetas (Xcode)

```
ILoveFinancesGF/
├── App/
│   ├── ILoveFinancesGFApp.swift      // @main, ModelContainer
│   └── AppContainer.swift             // configuración del contenedor + CloudKit
├── Models/
│   ├── Account.swift
│   ├── Transaction.swift
│   ├── TransactionCategory.swift
│   ├── FamilyTag.swift
│   ├── RecurringBill.swift
│   ├── Asset.swift
│   ├── InvestmentTrade.swift
│   ├── PriceQuote.swift
│   ├── ImportProfile.swift            // mapeo de columnas por banco
│   ├── ImportRule.swift               // autocategorización por texto
│   └── Enums/                         // TransactionKind, AccountType, Recurrence…
├── Features/
│   ├── Dashboard/
│   ├── Transactions/
│   ├── Bills/
│   ├── Investments/
│   ├── Import/
│   └── Settings/
├── Services/
│   ├── CSVImportService.swift
│   ├── RecurringBillService.swift
│   ├── PortfolioService.swift
│   ├── NotificationService.swift
│   └── BackupService.swift            // export CSV a iCloud Drive
├── Shared/
│   ├── Extensions/                    // Decimal+Money, Date+Period
│   ├── Formatters/                    // EUR currency formatter
│   └── Components/                    // AmountText, CategoryChip, PeriodPicker
├── Resources/
│   ├── Assets.xcassets
│   └── SeedCategories.json            // categorías por defecto al primer arranque
└── Preview Content/
```

`Features/` agrupa por pantalla, no por tipo. Cada carpeta tiene sus vistas y, si aplica, su `@Observable`. Evita el clásico `Views/` con 40 ficheros sin relación.

### Sincronización CloudKit

`ModelConfiguration` con `cloudKitDatabase: .automatic`. Implicaciones que condicionan el modelo de datos y hay que respetar desde el día uno:

- **Todos los atributos deben ser opcionales o tener valor por defecto.** CloudKit no soporta campos obligatorios sin default.
- **No se puede usar `@Attribute(.unique)`.** La unicidad hay que garantizarla en código (ver deduplicación de CSV, §4).
- **Todas las relaciones deben ser opcionales** y tener su inversa declarada.
- **No hay `deleteRule: .deny`.** Usar `.nullify` y controlar el borrado en la UI.
- **Nada de relaciones auto-referenciales.** Una entidad que se relaciona consigo misma (el caso clásico: `TransactionCategory.parent` / `TransactionCategory.children`) es históricamente frágil en `NSPersistentCloudKitContainer`. La jerarquía de categorías se modela con `parentID: UUID?` plano y se resuelve en código (§3).

Conviene un target de debug con contenedor solo local para desarrollar rápido sin depender de la cuenta de iCloud.

### Fontanería de CloudKit — no es solo `cloudKitDatabase: .automatic`

Sin estos cuatro puntos la sincronización no funciona, y el criterio de cierre de la Fase 1 no se cumple:

1. **Capability iCloud** activada en el target, con **CloudKit** marcado y un contenedor propio (`iCloud.com.raul.ILoveFinancesGF`).
2. **Background Modes → Remote notifications.** Sin esto la app solo sincroniza al abrirla, nunca en segundo plano.
3. **Push Notifications** en el entitlement (CloudKit las usa internamente; no hay que pedir permiso al usuario).
4. **Despliegue del esquema a Production.** El contenedor de Development se genera solo al ejecutar en debug. Antes de instalar una build de release o TestFlight hay que pulsar *Deploy Schema to Production* en el CloudKit Console — y repetirlo con cada cambio de modelo. Es la causa número uno de "en debug sincroniza y en release no".

Y una implicación operativa: el esquema de CloudKit en Production es **aditivo**. Se pueden añadir campos y tipos de registro; no se pueden borrar ni cambiar de tipo. De ahí que §8 insista en congelar el esquema antes de meter datos reales.

---

## 3. Modelo de datos

### Decisiones transversales

**`Decimal` para todos los importes, nunca `Double`.** `Double` no representa 0,1 exacto; sumar 300 gastos de céntimos acumula error visible. Todas las operaciones aritméticas van con `Decimal` y `NSDecimalNumber.RoundingMode.plain` a 2 decimales al mostrar (4-6 decimales en cantidades de activos).

> **Verificado en la Fase 0 — `Decimal` se queda.** (24/08/2026, ver `docs/fase0-resultados.md`.)
>
> El hallazgo tiene dos mitades y las dos importan:
>
> - **Se almacena como `Double`.** El volcado del `CKRecord` crudo muestra `CD_asDecimal` con tipo `Double` y exactamente los mismos bits que un campo de control `Double` (`0.010000000000000000208` para 0,01). CloudKit no tiene tipo decimal y el mirroring lo degrada. La sospecha estaba fundada.
> - **Vuelve intacto de todas formas.** Tras sembrar 210 registros, desinstalar la app y reinstalarla, los diez valores patológicos (`0.1`, `0.07`, `0.615`, `1234567.89`, `99999999.99`, `12.345678`…) y la suma de 200 filas de `0,01 €` regresan de la nube con igualdad **exacta** de `Decimal`. La conversión de vuelta recupera el decimal original para cualquier importe de magnitud realista.
>
> Lo que da crédito al resultado: en la misma prueba el campo de control `Double` **sí falla** en tres filas. Si el control hubiera salido limpio, un "todo OK" solo probaría que la comparación no mide nada.
>
> Queda descartado el plan B de persistir céntimos en `Int`. Aviso que sobrevive de aquella exploración: una escala de céntimos no puede representar fracciones de céntimo (`0,005` se pierde), así que si algún día un precio por unidad o un tipo de cambio necesita más de 2 decimales, `Decimal` sigue valiendo y el entero escalado no.

**Un solo signo de importe.** El importe se guarda **siempre positivo** y el signo lo determina `kind` (`.expense` / `.income`). Alternativa descartada: guardar negativos para gastos — hace que cualquier suma o filtro requiera recordar el convenio y produce bugs silenciosos al importar CSV (cada banco usa el suyo).

**Enums con `String` como raw value.** Un `Int` raw value se rompe si reordenas los casos; el `String` sobrevive a refactors y es legible al depurar la base de datos.

**`id: UUID` explícito en cada entidad.** SwiftData usa `PersistentIdentifier` internamente, pero para deduplicación de CSV, exportación y depuración conviene un identificador estable y propio.

**Índices.** El deployment target es iOS 26 y `#Index` está disponible desde el día uno — **verificado que compila** en la Fase 0. `Transaction` lleva `#Index<Transaction>([\.date], [\.date, \.kindRaw])`, que cubre el listado ordenado por fecha y los filtros por tipo. Con esto desaparece el riesgo de rendimiento que obligaba a medir con datasets sintéticos antes de cerrar la Fase 1.

Fijar el suelo en iOS 26 no cuesta nada aquí: el dispositivo es propio, ya va en 26, y no hay usuarios ajenos a los que dejar atrás.

**Predicados y propiedades calculadas.** `#Predicate` solo puede filtrar por atributos persistidos. `signedAmount`, `grossAmount` o el saldo de una cuenta son calculados y **no** se pueden usar en un `FetchDescriptor`: hay que filtrar por `kindRaw` y `amount` por separado, o traer y filtrar en memoria. Tenerlo presente al diseñar cada consulta.

**`Decimal` sí funciona dentro de `#Predicate`** — verificado en la Fase 0 con un `fetch` real, no solo comprobando que compila. El filtro de rango de importe de la pantalla de Movimientos (§6) puede ir directo sobre `amount`.

### Entidades

#### `Account` — cuenta

```swift
@Model
final class Account {
    var id: UUID = UUID()
    var name: String = ""
    var typeRaw: String = AccountType.checking.rawValue
    var openingBalance: Decimal = Decimal.zero   // saldo al dar de alta
    var iban: String?                            // últimos 4 dígitos, solo para reconocer el CSV
    var colorHex: String?
    var isArchived: Bool = false
    var createdAt: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \Transaction.account)
    var transactions: [Transaction]? = []

    /// Inversa obligatoria de Transaction.counterpartAccount: traspasos ENTRANTES a esta cuenta.
    /// CloudKit exige inversa declarada en toda relación; sin esto la sincronización falla.
    @Relationship(deleteRule: .nullify, inverse: \Transaction.counterpartAccount)
    var incomingTransfers: [Transaction]? = []

    /// Inversa de ImportProfile.account. Sin usar hasta la Fase 3, obligatoria ya.
    @Relationship(deleteRule: .nullify, inverse: \ImportProfile.account)
    var importProfiles: [ImportProfile]? = []

    var type: AccountType {
        get { AccountType(rawValue: typeRaw) ?? .checking }
        set { typeRaw = newValue.rawValue }
    }
}

enum AccountType: String, Codable, CaseIterable {
    case checking      // cuenta corriente
    case savings       // ahorro
    case card          // tarjeta de crédito
    case cash          // efectivo
    case brokerage     // bróker / cuenta de valores
}
```

El saldo actual **no se persiste**: se calcula como `openingBalance + Σ ingresos − Σ gastos ∓ traspasos`, sumando `transactions` e `incomingTransfers` con la función `signedAmount(for:)` de más abajo. Persistirlo obliga a mantenerlo consistente en cada alta, edición, borrado e importación, y con sync CloudKit entre dos dispositivos eso se desincroniza. Si el cálculo pesa, se cachea en memoria por sesión, no en disco.

#### `Transaction` — transacción

```swift
@Model
final class Transaction {
    var id: UUID = UUID()
    var date: Date = Date()
    var amount: Decimal = Decimal.zero        // siempre positivo
    var kindRaw: String = TransactionKind.expense.rawValue
    var note: String = ""                     // concepto / descripción
    var merchant: String?                     // comercio, si se puede extraer
    var createdAt: Date = Date()

    // Deduplicación de importaciones CSV
    var importHash: String?                   // ver §4
    var importBatchID: UUID?

    // Marcadores
    var isRecurringInstance: Bool = false     // generada por una RecurringBill
    var receiptData: Data?                    // foto de ticket, @Attribute(.externalStorage)

    var account: Account?
    var category: TransactionCategory?
    var familyTag: FamilyTag?
    var recurringBill: RecurringBill?

    var kind: TransactionKind {
        get { TransactionKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    /// Importe con signo **relativo a una cuenta concreta**.
    /// No puede ser una propiedad sin parámetro: un traspaso resta en origen y suma en destino,
    /// así que su signo depende de desde qué cuenta se mire.
    func signedAmount(for account: Account) -> Decimal {
        switch kind {
        case .income:  return amount
        case .expense: return -amount
        case .transfer:
            // Positivo si la cuenta consultada es el destino, negativo si es el origen.
            return account.id == counterpartAccount?.id ? amount : -amount
        }
    }

    /// Aporte al cómputo de gasto/ingreso del periodo. Un traspaso entre cuentas propias
    /// no es ni gasto ni ingreso: no mueve patrimonio, solo lo cambia de sitio.
    var incomeExpenseAmount: Decimal {
        switch kind {
        case .income:   return amount
        case .expense:  return -amount
        case .transfer: return .zero
        }
    }
}

enum TransactionKind: String, Codable, CaseIterable {
    case income
    case expense
    case transfer      // movimiento entre cuentas propias: no es gasto ni ingreso
}
```

Sobre `transfer`: un traspaso de la cuenta corriente al ahorro no debe contar como gasto en el dashboard. Se modela como **una** transacción de tipo `.transfer` con `account` (origen) y un campo adicional `counterpartAccount: Account?` (destino). Crear dos transacciones espejo es la alternativa, pero duplica el borrado y la edición. Con una sola, el cálculo de saldo resta en origen y suma en destino.

Esto tiene dos consecuencias que hay que respetar en todo el código, y son la causa de las dos funciones de importe de arriba:

- **El signo de un traspaso no es global, es por cuenta.** Un único `signedAmount` sin parámetro es imposible de escribir correctamente: la misma fila vale `−200` para la corriente y `+200` para el ahorro. De ahí `signedAmount(for:)`.
- **Todo agregado de gasto o ingreso debe excluir los traspasos.** Dashboard, gráfico por categoría, totales de filtro: todos usan `incomeExpenseAmount`, que devuelve cero para `.transfer`. Solo los cálculos de saldo usan `signedAmount(for:)`.

```swift
    var counterpartAccount: Account?   // solo para kind == .transfer
```

`receiptData` con `@Attribute(.externalStorage)` para que las fotos no engorden el store. Cuidado: CloudKit tiene límites de tamaño por registro; comprimir a JPEG ~0.6 antes de guardar.

#### `TransactionCategory` — categoría

**No se llama `Category`**, y el motivo se descubrió al compilar en la Fase 1: el runtime de Objective-C exporta su propio tipo `Category` (`objc/runtime.h`), y en cuanto ese header entra en ámbito cualquier uso genérico —`FetchDescriptor<Category>`— queda ambiguo y no compila. La app llegó a compilar con el nombre corto por casualidad; bastaba un `import` de más para romperla. Renombrar salía gratis entonces y sería **imposible** después: el `RecordType` de CloudKit no se puede borrar ni renombrar una vez desplegado a Production.

```swift
@Model
final class TransactionCategory {
    var id: UUID = UUID()
    var name: String = ""
    var symbolName: String = "tag"     // SF Symbol
    var colorHex: String = "#888888"
    var kindRaw: String = TransactionKind.expense.rawValue  // categoría de gasto o de ingreso
    var isSystem: Bool = false         // las que vienen sembradas, no borrables
    var sortOrder: Int = 0

    /// Jerarquía por ID plano, NO por relación auto-referencial.
    /// `TransactionCategory.parent` + `TransactionCategory.children` es el patrón natural en SwiftData,
    /// pero las relaciones de una entidad consigo misma son frágiles bajo
    /// NSPersistentCloudKitContainer. Con dos niveles fijos, un UUID sale más barato.
    var parentID: UUID?

    @Relationship(deleteRule: .nullify, inverse: \Transaction.category)
    var transactions: [Transaction]? = []

    /// Inversa de ImportRule.category, obligatoria para CloudKit.
    @Relationship(deleteRule: .nullify, inverse: \ImportRule.category)
    var importRules: [ImportRule]? = []

    var isSubcategory: Bool { parentID != nil }
}
```

Jerarquía de dos niveles como máximo (Hogar → Luz, Agua). Más niveles complican el desglose del dashboard sin aportar nada en uso doméstico. La restricción se impone en la UI, no en el modelo.

Resolver padres e hijos es una consulta plana sobre `parentID` y un agrupamiento en memoria — con menos de cien categorías, irrelevante en coste:

```swift
let hijos = Dictionary(grouping: todas.filter { $0.parentID != nil }, by: \.parentID!)
```

Borrar una categoría padre debe reasignar `parentID = nil` en sus hijas desde la UI. No hay `deleteRule` que lo haga por nosotros — precio de renunciar a la relación, y es un método de cinco líneas.

Categorías sembradas al primer arranque desde `SeedCategories.json`: Vivienda, Alimentación, Transporte, Salud, Educación, Ocio, Suscripciones, Seguros, Impuestos, Otros; e ingresos: Nómina, Autónomo, Alquiler, Dividendos, Devoluciones, Otros.

#### `FamilyTag` — miembro de la familia

```swift
@Model
final class FamilyTag {
    var id: UUID = UUID()
    var name: String = ""              // "Raúl", "Ana", "Común", "Niños"
    var colorHex: String = "#4A90D9"
    var sortOrder: Int = 0

    @Relationship(deleteRule: .nullify, inverse: \Transaction.familyTag)
    var transactions: [Transaction]? = []

    /// Inversa de ImportRule.familyTag, obligatoria para CloudKit.
    @Relationship(deleteRule: .nullify, inverse: \ImportRule.familyTag)
    var importRules: [ImportRule]? = []
}
```

Deliberadamente pobre: sin email, sin permisos, sin identidad. Es una etiqueta de color con nombre, sirve para filtrar y para el desglose "quién gasta qué". Si en el futuro hiciera falta un usuario real, se crea una entidad `User` nueva y esta se queda como está.

#### `RecurringBill` — factura recurrente

```swift
@Model
final class RecurringBill {
    var id: UUID = UUID()
    var name: String = ""                    // "Endesa", "Hipoteca"
    var estimatedAmount: Decimal = Decimal.zero
    var isVariableAmount: Bool = false       // luz sí, hipoteca no
    var recurrenceRaw: String = Recurrence.monthly.rawValue
    var dayOfMonth: Int = 1                  // día previsto de cargo
    var startDate: Date = Date()
    var endDate: Date?                       // nil = indefinida
    var isActive: Bool = true
    var reminderDaysBefore: Int = 3
    var notificationID: String?              // identificador en UNUserNotificationCenter

    var account: Account?
    var category: TransactionCategory?
    var familyTag: FamilyTag?

    @Relationship(deleteRule: .nullify, inverse: \Transaction.recurringBill)
    var payments: [Transaction]? = []
}

enum Recurrence: String, Codable, CaseIterable {
    case weekly, biweekly, monthly, bimonthly, quarterly, semiannual, annual
}
```

**Las ocurrencias futuras no se materializan en base de datos.** Se calculan al vuelo desde `recurrence` + `dayOfMonth` + `startDate`. Materializarlas obliga a regenerar y limpiar filas cada vez que cambia la periodicidad, y con sync entre dos dispositivos genera duplicados. Solo cuando el usuario marca "pagada" se crea una `Transaction` real enlazada por `recurringBill`.

Para saber si una ocurrencia ya está pagada: existe una `Transaction` con ese `recurringBill` y `date` dentro de la ventana de esa ocurrencia.

#### `Asset` — activo

```swift
@Model
final class Asset {
    var id: UUID = UUID()
    var name: String = ""                    // "Vanguard FTSE All-World"
    var ticker: String?                       // "VWCE"
    var isin: String?
    var assetTypeRaw: String = AssetType.etf.rawValue
    var currencyCode: String = "EUR"          // ISO 4217; USD para lo cotizado fuera del euro
    var notes: String = ""
    var isArchived: Bool = false

    var account: Account?                     // bróker donde está

    @Relationship(deleteRule: .cascade, inverse: \InvestmentTrade.asset)
    var trades: [InvestmentTrade]? = []

    @Relationship(deleteRule: .cascade, inverse: \PriceQuote.asset)
    var quotes: [PriceQuote]? = []
}

enum AssetType: String, Codable, CaseIterable {
    case stock, etf, fund, bond, crypto, other
}
```

No hay entidad `Position`. La posición (cantidad, coste medio, valor actual) es una **función derivada** de los trades ordenados por fecha, calculada por `PortfolioService`. Persistir la posición significa recalcularla y guardarla en cada alta/edición/borrado de trade, y con CloudKit dos dispositivos pueden escribir posiciones inconsistentes. Derivarla siempre es correcto por construcción. Si con muchos trades el cálculo pesa, se cachea en memoria.

#### `InvestmentTrade` — movimiento de inversión

```swift
@Model
final class InvestmentTrade {
    var id: UUID = UUID()
    var date: Date = Date()
    var sideRaw: String = TradeSide.buy.rawValue
    var quantity: Decimal = Decimal.zero      // participaciones/acciones, hasta 6 decimales
    var pricePerUnit: Decimal = Decimal.zero  // EUR por unidad
    var fees: Decimal = Decimal.zero          // comisiones + canon (o retención, en dividendos)
    var cashAmount: Decimal = Decimal.zero    // solo para .dividend: importe bruto cobrado
    var note: String = ""

    var asset: Asset?

    var side: TradeSide {
        get { TradeSide(rawValue: sideRaw) ?? .buy }
        set { sideRaw = newValue.rawValue }
    }

    /// Importe bruto de la operación.
    /// Un dividendo NO puede derivarlo de quantity*pricePerUnit: ambos valen cero
    /// en ese caso y el resultado sería siempre 0 €. Por eso existe `cashAmount`.
    var grossAmount: Decimal {
        side == .dividend ? cashAmount : quantity * pricePerUnit
    }

    /// Efectivo que entra (+) o sale (−) de la cuenta del bróker.
    var cashFlow: Decimal {
        switch side {
        case .buy:      return -(grossAmount + fees)
        case .sell:     return grossAmount - fees
        case .dividend: return cashAmount - fees      // fees = retención practicada
        case .split:    return .zero                  // no mueve dinero
        }
    }
}

enum TradeSide: String, Codable, CaseIterable {
    case buy
    case sell
    case dividend       // quantity = 0, pricePerUnit = 0; el importe va en cashAmount
    case split          // quantity = factor de desdoblamiento (2 = 2x1); no mueve dinero
}
```

`dividend` y `split` dentro de la misma entidad en vez de tablas separadas: son pocos casos, comparten asset y fecha, y separarlos triplicaría el código de recorrido cronológico en `PortfolioService`.

#### `PriceQuote` — cotización

```swift
@Model
final class PriceQuote {
    var id: UUID = UUID()
    var date: Date = Date()
    var price: Decimal = Decimal.zero        // en la divisa nativa del activo, NO convertido
    var currencyCode: String = "EUR"         // copia de Asset.currencyCode al capturar
    var fxRateToEUR: Decimal = 1             // tipo de cambio del día; 1 si ya es EUR
    var sourceRaw: String = QuoteSource.manual.rawValue

    var asset: Asset?

    /// Valor en euros, derivado. El precio de mercado nunca se guarda ya convertido:
    /// hacerlo destruye el dato original de forma irreversible.
    var priceEUR: Decimal { price * fxRateToEUR }
}

enum QuoteSource: String, Codable {
    case manual
    case api
}
```

Histórico de precios, no solo el último. Permite dibujar la evolución del valor de la cartera sin depender de una API que solo dé el precio de hoy.

**Un registro por día y activo como máximo**, y esa unicidad hay que imponerla en código: CloudKit prohíbe `@Attribute(.unique)`. Antes de insertar, `PortfolioService` busca una cotización de ese activo con `date` en el mismo día natural y la actualiza en vez de crear otra. Sin este cuidado, un refresco automático diario deja miles de filas basura en un año.

#### `ImportProfile` — perfil de importación de un banco

```swift
@Model
final class ImportProfile {
    var id: UUID = UUID()
    var name: String = ""                    // "BBVA cuenta corriente"
    var headerSignature: String = ""         // hash de las cabeceras detectadas
    var columnMappingJSON: String = "{}"     // [índice de columna: campo destino]
    var separator: String = ";"
    var encodingRaw: String = "utf8"
    var dateFormat: String = "dd/MM/yyyy"
    var amountStyleRaw: String = "singleSigned"   // o "debitCredit"
    var lastUsedAt: Date = Date()

    var account: Account?                    // cuenta a la que importa por defecto
}
```

El mapeo va como JSON en un `String` y no como diccionario: SwiftData no persiste `[Int: String]` de forma fiable a través de CloudKit, y el contenido nunca se consulta con predicados — solo se lee entero al abrir el importador.

`headerSignature` es lo que permite reconocer el banco en la segunda importación (§4). Se calcula como SHA-256 de las cabeceras normalizadas y unidas por `|`.

#### `ImportRule` — regla de autocategorización

```swift
@Model
final class ImportRule {
    var id: UUID = UUID()
    var pattern: String = ""                 // subcadena a buscar en el concepto: "MERCADONA"
    var priority: Int = 0                    // menor gana; orden editable por el usuario
    var isActive: Bool = true
    var matchCount: Int = 0                  // cuántas veces ha acertado, para depurar reglas
    var createdAt: Date = Date()

    var category: TransactionCategory?
    var familyTag: FamilyTag?                // opcional: además de categorizar, atribuye
}
```

Ambas entidades estaban usadas a fondo en §4 pero ausentes del modelo. Como el esquema de CloudKit en Production es aditivo y frágil de cambiar, **entran en el esquema v1 de la Fase 1 aunque no se usen hasta la Fase 3**. Una tabla vacía no cuesta nada; añadir una entidad después de tener datos reales sincronizados, sí.

Y la decisión ya se pagó sola. Sus tres relaciones —`ImportProfile.account`, `ImportRule.category`, `ImportRule.familyTag`— **no tenían inversa declarada** en la primera versión de este documento. CloudKit rechaza el store entero por eso, y no al compilar: en ejecución, con un `Store failed to load` que nombra las tres. Escribirlas en la Fase 1 convirtió un fallo de la Fase 3 con datos reales dentro en media hora de trabajo. Las inversas ya están arriba, en `Account`, `TransactionCategory` y `FamilyTag`.

### Diagrama de relaciones

```
Account 1──* Transaction *──1 TransactionCategory   (jerarquía por parentID: UUID?, sin relación)
   │              *──1 FamilyTag
   │              *──1 RecurringBill
   │
   └─1──* Asset 1──* InvestmentTrade
              1──* PriceQuote

RecurringBill *──1 Account, *──1 TransactionCategory, *──1 FamilyTag
Transaction   *──1 counterpartAccount  (solo kind == .transfer)
               └── inversa: Account.incomingTransfers

ImportProfile *──1 Account
ImportRule    *──1 TransactionCategory, *──1 FamilyTag
```

---

## 4. Importación de CSV

El punto donde una app de finanzas personales se gana o se pierde. Los CSV de banco español son un desastre: cabeceras en la fila 4, columnas `Fecha valor` y `Fecha operación` distintas, importes con coma decimal y punto de millar, codificación ISO-8859-1, y saldo acumulado en la última columna.

### Flujo

```
Elegir fichero (.fileImporter)
   ↓
Detectar codificación y separador
   ↓
Detectar fila de cabecera
   ↓
Mapear columnas  ← manual la primera vez, recordado después
   ↓
Parsear filas → [ImportedRow] en memoria (nada tocado en BD)
   ↓
Clasificar cada fila: nueva / duplicado exacto / posible duplicado
   ↓
PREVISUALIZAR: el usuario revisa, edita, desmarca
   ↓
Confirmar → crear Transactions en un batch con importBatchID
```

### Detección de formato

- **Codificación:** intentar UTF-8; si falla la decodificación, ISO Latin 1 (`.isoLatin1`), que es lo que sueltan la mayoría de bancos españoles. Detectar y quitar BOM.
- **Separador:** contar `;`, `,` y `\t` en las primeras 20 líneas y quedarse con el que dé un número de campos constante. En España el separador suele ser `;` precisamente porque la coma es decimal.
- **Fila de cabecera:** la primera fila cuyo número de campos coincide con la moda del fichero y cuyos campos son mayoritariamente no numéricos.
- **Importes:** normalizar `1.234,56` → `1234.56` y `1,234.56` → `1234.56`. La heurística: si hay `.` y `,`, el último que aparece es el decimal. Si solo hay uno, es decimal si va seguido de exactamente 2 dígitos al final; si no, es separador de millar. Parsear siempre con `Decimal(string:)` sobre la cadena normalizada, nunca `Double(string)`.
- **Fechas:** probar en orden `dd/MM/yyyy`, `dd-MM-yyyy`, `yyyy-MM-dd`, `dd/MM/yy`. Fijar `Locale(identifier: "en_US_POSIX")` en el `DateFormatter` para que no dependa de la configuración del móvil.

### Mapeo de columnas

Pantalla con una fila por columna del CSV, mostrando la cabecera detectada y las 3 primeras filas de ejemplo, y un `Picker` con el campo destino:

| Campo destino | Obligatorio | Notas |
|---|---|---|
| Fecha | Sí | Si hay dos fechas, preguntar cuál usar; por defecto fecha de operación |
| Importe | Sí | Puede venir en una columna con signo o en dos (Débito / Haber) |
| Concepto | Sí | Se vuelca a `note` |
| Comercio | No | Si el banco lo separa |
| Saldo | No | Se ignora, pero sirve para validar (ver más abajo) |
| Ignorar | — | Por defecto para el resto |

**El mapeo se guarda** en una entidad `ImportProfile` (§3), asociado a `headerSignature`. `UserDefaults` queda descartado: los perfiles deben viajar por CloudKit para sobrevivir a un cambio de móvil, y ya hay más de un banco en juego. La segunda importación del mismo banco no pide nada.

**Signo del importe:** si el banco da una sola columna con negativos, `kind = amount < 0 ? .expense : .income` y se guarda el valor absoluto. Si da dos columnas, la que tenga valor decide el `kind`. Este switch se elige en la pantalla de mapeo, no se adivina.

**Validación con la columna saldo:** si el CSV trae saldo acumulado, comprobar que `saldo[n] - saldo[n-1] == importe[n]`. Si no cuadra en alguna fila, avisar de que el parseo puede estar mal — es la forma más barata de detectar un error de signo o decimal antes de meter basura.

### Detección de duplicados

Dos niveles, porque el problema real es reimportar el mismo mes solapado.

**1. Duplicado exacto — `importHash`.** SHA-256 de la concatenación normalizada:

```
accountID | yyyy-MM-dd | importe con 2 decimales | concepto en minúsculas sin espacios múltiples
```

Se guarda en `Transaction.importHash`. Antes de insertar, se consulta si ese hash ya existe en la cuenta. Si existe → duplicado exacto, se marca y se desmarca por defecto en la previsualización.

Como CloudKit prohíbe `@Attribute(.unique)`, la unicidad la impone el `CSVImportService` con un `FetchDescriptor` filtrado por los hashes del lote (una sola consulta con `predicate` de pertenencia, no una por fila).

**2. Posible duplicado — heurística.** Misma cuenta, mismo importe, fecha a ±3 días, y concepto con similitud alta (distancia de Levenshtein normalizada > 0.85). Cubre el caso de que el banco cambie ligeramente el concepto o mueva la fecha valor. Estos se marcan en ámbar y **sí** vienen seleccionados por defecto, pero visibles — decide el usuario.

Nota: dos compras reales idénticas el mismo día en el mismo comercio (dos cafés de 1,50 €) son un falso positivo legítimo del nivel 1. Por eso el hash incluye un contador de ocurrencia dentro del propio lote: si en el CSV vienen dos filas idénticas, la segunda lleva sufijo `#2` y no se considera duplicado de la primera.

### Previsualización

Lista con las filas parseadas, cada una con:

- Checkbox de importar (desmarcado si es duplicado exacto).
- Fecha, concepto, importe formateado en EUR con su signo y color.
- `Picker` de categoría, precargado por reglas de autocategorización.
- Etiqueta de estado: `Nueva` / `Duplicada` / `Posible duplicada`.
- Cabecera con el resumen: "142 filas, 118 nuevas, 21 duplicadas, 3 posibles duplicadas. Total: −2.340,18 €".

**Autocategorización por reglas de texto.** Al confirmar una importación, si el usuario cambia la categoría de una fila, se ofrece guardar la regla como `ImportRule` ("Todo lo que contenga MERCADONA → Alimentación"). Regla simple: subcadena en el concepto, insensible a mayúsculas y acentos (`.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)`), menor `priority` gana, orden editable. Nada de machine learning; con 30 reglas se cubre casi todo el gasto recurrente. `matchCount` sirve para detectar reglas muertas o demasiado golosas.

**Confirmar es atómico.** Todas las transacciones del lote comparten `importBatchID`. Eso permite un "Deshacer importación" en Ajustes que borre el lote entero — imprescindible cuando el mapeo estaba mal y se han metido 200 filas con el signo cambiado.

---

## 5. Inversiones

### Cálculos necesarios

**Coste medio ponderado (average cost).** Recorriendo los trades por fecha:

- Compra: `nuevoCoste = costeTotal + (qty·precio + fees)`, `nuevaCantidad = cantidad + qty`, `costeMedio = nuevoCoste / nuevaCantidad`.
- Venta: la cantidad vendida sale al coste medio vigente. `costeTotal -= qtyVendida · costeMedio`. El coste medio **no cambia** con una venta.
- Split: multiplica cantidad por el factor y divide el coste medio por el mismo factor. Coste total intacto.
- Dividendo: no toca cantidad ni coste. Se acumula aparte como ingreso.

**P&L realizado** (por venta): `qtyVendida · (precioVenta − costeMedio) − feesVenta`. Se acumula por activo y por año natural.

**P&L no realizado:** `cantidadActual · (precioActual − costeMedio)`. Depende de tener un precio actual — ahí está la decisión pendiente.

**Valor de cartera:** `Σ cantidadActual · precioActual` por activo. Con evolución temporal si hay histórico en `PriceQuote`.

**Rentabilidad:** empezar por la simple `(valorActual + realizado + dividendos − aportado) / aportado`. Un TWR o un XIRR son más correctos cuando hay aportaciones periódicas, pero requieren series de flujos y no aportan tanto en un primer momento. Dejarlo para después de tener el resto funcionando.

> Aviso: esto son cálculos de gestión, no cálculos fiscales. Hacienda en España exige FIFO para acciones y tiene la regla de los dos meses para pérdidas en valores homogéneos. Ver §8.

### De dónde salen los precios — **decidido: Opción C (híbrido), arrancando en manual**

Las tres opciones siguen documentadas porque justifican la elección. El modelo de datos ya soporta las tres (`PriceQuote.source`), así que la Fase 4 arranca con entrada manual y la ruta de API se añade después **sin migración de esquema**.

#### Opción A — Precio manual

El usuario introduce el precio cuando quiere; se guarda como `PriceQuote` con `source = .manual`. El dashboard muestra "valorado a 12/08/2026".

| A favor | En contra |
|---|---|
| Cero dependencias externas, cero coste, cero claves API | Fricción: hay que abrir la app y teclear precios para ver valor actualizado |
| Funciona offline y no se rompe nunca | El P&L no realizado está desactualizado la mayor parte del tiempo |
| Nada de términos de servicio ni límites de peticiones | Con 10 activos, actualizar es tedioso |
| Sirve igual para fondos no cotizados o activos ilíquidos | El gráfico de evolución tiene huecos |

#### Opción B — API de mercado

Servicio externo que devuelve cotizaciones por ticker o ISIN. Candidatos habituales: Yahoo Finance (no oficial, se rompe sin aviso), Alpha Vantage (gratuito con límite estricto de peticiones), Twelve Data, Financial Modeling Prep, EOD Historical Data (de pago, cubre fondos europeos y UCITS con ISIN).

| A favor | En contra |
|---|---|
| Valor de cartera siempre al día sin esfuerzo | Coste recurrente si quieres cobertura de UCITS europeos por ISIN — los gratuitos cubren mal el mercado europeo |
| Permite gráficos de evolución completos | Hay que guardar una clave API; en una app local significa meterla en el binario o pedírsela al usuario |
| Refresco en background posible | Dependencia que puede caer, cambiar de formato o cerrar el plan gratuito |
| | Los fondos de inversión (no ETF) muchas veces no están disponibles a ningún precio |
| | Añade capa de red, caché, manejo de errores y estados de carga a toda la sección |

#### Opción C — Híbrido

API para lo que se pueda resolver por ticker (acciones, ETFs cotizados), entrada manual como respaldo y para todo lo demás. `PriceQuote.source` ya está en el modelo precisamente para esto, y `PortfolioService` es indiferente al origen.

| A favor | En contra |
|---|---|
| Cubre el 100% de los activos sin obligarte a elegir | Es el más trabajo: hay que construir las dos rutas |
| Degrada bien: si la API falla, sigue habiendo precio manual | Dos caminos que mantener y probar |
| Permite empezar en manual y añadir API después sin tocar el modelo | |

**Por qué C y no B:** la Opción B pura obliga a que *todos* los activos sean resolubles por una API, y basta un fondo no cotizado o un UCITS que solo se encuentre por ISIN en un servicio de pago para que la sección quede coja. C degrada bien: si la API falla, cae en el último precio manual conocido y la pantalla sigue funcionando con su fecha de valoración a la vista.

**Por qué manual primero:** la ruta manual es la que hay que construir de todas formas (es el respaldo), no tiene dependencias y permite cerrar la Fase 4 entera sin bloquearse eligiendo proveedor. La API es una mejora incremental sobre una Fase 4 ya terminada, no un requisito para cerrarla.

**Método de coste: medio ponderado — decidido.** El plan usa coste medio, que es lo estándar para gestión y lo que muestra el bróker. FIFO queda descartado: implica mantener lotes individuales en vez de un agregado, triplica el código de `PortfolioService` y solo aporta si las cifras van a alimentar la declaración de la renta. Si algún día hace falta, se implementa como un cálculo alternativo sobre los mismos `InvestmentTrade` — no requiere cambiar el modelo, y por eso es seguro aplazarlo.

---

## 6. Pantallas y navegación

`TabView` de cuatro pestañas. Solo iPhone: no hay `NavigationSplitView` ni layout adaptativo. Cada pantalla se diseña una vez, para un ancho.

```
┌─ Resumen ─────────── Movimientos ──── Facturas ──── Inversiones ─┐
```

### Resumen (Dashboard)

- Selector de periodo arriba: Mes / Trimestre / Año / Personalizado.
- Tarjeta de saldo total (suma de cuentas activas), con desglose desplegable por cuenta.
- Ingresos vs gastos del periodo, con variación respecto al periodo anterior. **Los traspasos no computan** (`incomeExpenseAmount`, §3).
- Gráfico de gasto por categoría (Swift Charts, donut o barras horizontales). Tocar un segmento navega a los movimientos filtrados.
- Próximas facturas (siguientes 30 días), con importe estimado y estado.
- Valor de la cartera y P&L no realizado (a partir de Fase 4).
- Desglose por miembro de la familia si hay más de un `FamilyTag` en uso.

### Movimientos

- Lista agrupada por día, con encabezados de sección y subtotal diario.
- Búsqueda por concepto y comercio.
- Filtros: cuenta, categoría, miembro, tipo, rango de fechas, rango de importe. El conjunto de filtros activo se muestra como chips eliminables.
- Deslizar para borrar y para duplicar.
- Botón `+` → hoja de alta rápida.
- Detalle: edición completa, foto de ticket, transacciones relacionadas (mismo comercio).

**Alta rápida.** Es la pantalla más usada de la app y merece optimización: teclado numérico enfocado al abrir, importe primero, categoría con las 6 más usadas recientemente accesibles de un toque, fecha por defecto hoy. Guardar y cerrar en tres toques.

### Facturas

- Sección "Próximas": ocurrencias calculadas de los siguientes 60 días, ordenadas por fecha, con acción `Marcar pagada` que abre el alta prellenada con importe estimado y categoría.
- Sección "Todas": listado de `RecurringBill` activas e inactivas.
- Detalle: configuración, historial de pagos con el importe real de cada mes y su gráfico — útil para las variables como la luz.

### Inversiones

- Resumen de cartera: valor total, coste total, P&L no realizado y realizado del año, y la fecha de la última valoración.
- Lista de activos: nombre, cantidad, coste medio, precio actual, P&L en importe y porcentaje con color.
- Detalle de activo: histórico de trades, gráfico de precio, botón de actualizar precio.
- Alta de movimiento: compra / venta / dividendo / split.

### Ajustes (dentro de Resumen, no como pestaña)

Cuentas, categorías, miembros, reglas de autocategorización, importar CSV, historial de importaciones con deshacer, estado de sincronización iCloud, y **copia de seguridad**: exportar todo a CSV manualmente y activar el volcado automático a iCloud Drive (§7, Fase 1).

**Tarjetas de crédito y efectivo** (decisiones cerradas, §8) se configuran aquí:

- Cada tarjeta es una `Account` de tipo `.card`. El gasto se registra el día de la compra; la liquidación mensual es una transacción `.transfer` desde la cuenta corriente hacia la tarjeta. Suena a más trabajo, pero el CSV de la tarjeta ya trae los movimientos: no se teclean.
- El efectivo es una `Account` de tipo `.cash` con un movimiento mensual de ajuste ("Gasto en efectivo no detallado") que cuadra el saldo con lo que hay en la cartera. Apuntar cada café a mano es lo que mata este tipo de apps en dos semanas.

---

## 7. Roadmap

Cada fase se cierra cuando cumple sus criterios. No se empieza la siguiente con la anterior a medias — en un proyecto de una persona, arrastrar tres frentes abiertos es la forma habitual de no terminar ninguno.

### Fase 0 — Spike de esquema · CERRADA (24/08/2026)

No era una fase de producto: era la que evitaba rehacer el modelo con datos reales dentro. Resultados completos en `docs/fase0-resultados.md`.

| Criterio | Resultado |
|---|---|
| `Decimal` sobrevive al viaje por CloudKit con `==` exacto | **Sí.** 10 valores patológicos y la suma de 200 × 0,01 €, tras desinstalar la app y reinstalarla. Se almacena como `Double` pero vuelve intacto. Plan B descartado. |
| `#Index` compila | Sí. |
| `Decimal` sirve en `#Predicate` | Sí, verificado con un `fetch` real y no solo compilando. |
| Fontanería de CloudKit: entitlement, background modes, `aps-environment` | Verificada sobre el binario firmado. |
| Despliegue de esquema a Production | Pendiente: acción manual en el CloudKit Console. |
| Entrada de cambios en **segundo plano** | No probada. Con un solo dispositivo no hay forma limpia de generar un cambio externo; lo verificado es que el mirroring importa datos que el dispositivo no tenía, que no es lo mismo. Se arrastra a la Fase 1. |

### Fase 1 — MVP: transacciones, categorías, dashboard · CERRADA (24/08/2026)

Alcance: entidades `Account`, `Transaction`, `TransactionCategory`, `FamilyTag` — **y `ImportProfile` + `ImportRule` vacías**, para que el esquema v1 ya las contenga (§3). Alta/edición/borrado manual. Lista con filtros y búsqueda. Dashboard con saldo, ingresos vs gastos y gasto por categoría. CloudKit funcionando. Categorías sembradas al primer arranque. `VersionedSchema` desde el primer commit. **Export CSV de toda la base de datos, manual**: un botón en Ajustes que exporta una carpeta con cuatro CSV, y su restauración. El volcado automático queda descartado (ver §8).

**Hecho cuando:**

- Puedo registrar un gasto en menos de 10 segundos desde que abro la app.
- El saldo mostrado coincide con el saldo real de mi cuenta tras introducir un mes de movimientos a mano.
- Un traspaso entre cuentas propias no aparece como gasto en el dashboard, y **sí** mueve el saldo de las dos cuentas implicadas, con el signo correcto en cada una.
- Desinstalo la app, la reinstalo, y todos mis datos vuelven de iCloud sin hacer nada.
- Puedo filtrar por categoría, cuenta, miembro y rango de fechas, y los totales del filtro cuadran.
- Borrar una categoría no borra sus transacciones (quedan sin categoría), y sus subcategorías quedan como categorías de primer nivel.
- El export CSV se puede reimportar y reconstruye la base de datos completa. Una copia de seguridad que no se ha probado a restaurar no es una copia de seguridad.
- La app arranca en frío en menos de 2 segundos con 1.000 transacciones.

### Fase 2 — Facturas recurrentes y recordatorios · CERRADA (24/08/2026)

Alcance: entidad `RecurringBill`, cálculo de ocurrencias, pantalla de facturas, notificaciones locales, marcar como pagada generando la transacción, historial de importes por factura.

**Hecho cuando:**

- Doy de alta la hipoteca y veo las próximas 6 ocurrencias correctamente calculadas.
- Recibo la notificación N días antes, y desaparece de "próximas" al marcarla pagada.
- Marcar pagada crea una transacción enlazada, editable, con el importe real si difiere del estimado.
- El historial de la factura de la luz muestra la variación mes a mes.
- Cambiar la periodicidad de una factura recalcula las ocurrencias futuras y reprograma las notificaciones sin dejar huérfanas.
- Desactivar una factura cancela sus notificaciones pendientes.
- Con 20 facturas activas dadas de alta, `pendingNotificationRequests` nunca supera 64 (ver riesgo de cupo en §8).

### Fase 3 — Importación de CSV · SIGUIENTE (tras la Fase 5)

Alcance: `CSVImportService` completo, detección de formato, pantalla de mapeo con perfiles guardados, deduplicación de dos niveles, previsualización editable, autocategorización por reglas, deshacer importación por lote.

**Hecho cuando:**

- Importo el CSV real de mi banco sin editar el fichero previamente.
- La segunda importación del mismo banco no me pide mapear columnas.
- Reimportar un CSV con un mes de solape detecta el 100% de los duplicados exactos y no me obliga a revisarlos uno a uno.
- Los importes con coma decimal y punto de millar se parsean bien; verifico contra la columna de saldo del propio CSV.
- Las reglas de autocategorización clasifican correctamente al menos el 70% de un extracto mensual típico.
- "Deshacer importación" deja la base de datos exactamente como estaba antes del lote.
- Un CSV corrupto o con formato inesperado muestra un error claro y no deja nada a medias en la base de datos.

### Fase 4 — Inversiones

Alcance: `Asset`, `InvestmentTrade`, `PriceQuote`, `PortfolioService` con coste medio y P&L, pantallas de cartera y activo, gráfico de evolución. Origen de precios según la decisión de §5.

**Hecho cuando:**

- Introduzco mi histórico real de compras y el coste medio coincide con el que muestra mi bróker.
- Una venta parcial produce un P&L realizado correcto y deja bien la posición restante.
- Un split se refleja correctamente en cantidad y coste medio sin alterar el coste total.
- Los dividendos suman al rendimiento sin ensuciar el coste.
- El valor de la cartera se ve en el dashboard con la fecha de la valoración usada.
- Un dividendo con importe real produce ese importe en el rendimiento, y no cero (el bug que `cashAmount` corrige en §3).
- Actualizar el precio de un activo dos veces el mismo día deja **una** `PriceQuote`, no dos.
- Si el precio proviene de API: un fallo de red no rompe la pantalla, muestra el último precio conocido con su fecha.

### Fase 5 — Tickets de compra y comparador de precios · CERRADA (24/08/2026)

**No estaba en este plan.** Se adelantó a las Fases 3 y 4 por una razón de esquema, no de prioridad: añade tres entidades, y la única ventana en la que eso es barato es antes de desplegar a CloudKit Production. Después habría exigido `SchemaV2` + `MigrationStage` con datos reales sincronizados.

Alcance: entidades `Shop`, `GroceryProduct` y `PurchaseLine`, más `Transaction.shop` / `isPurchaseTicket` / `purchaseLines`. Enum `UnitOfMeasure` con normalización por dimensión. `PurchaseService` con precio por unidad de medida y ranking por tienda. Cuarta pestaña "Compras" con alta de tickets, detalle y comparador. Tiendas y productos en Ajustes. Copia de seguridad ampliada con tres CSV nuevos.

**Decisiones cerradas de la fase:**

| Decisión | Motivo |
|---|---|
| El **`Transaction` ES el ticket**, sin entidad de cabecera aparte | El gasto ya tiene fecha, importe, cuenta y categoría. Así el dashboard, los saldos y los filtros siguen funcionando sin tocarlos. Y en la Fase 3, una fila importada del banco se podrá detallar sin reconciliar nada. |
| Nombres `Shop` y `GroceryProduct` | `StoreKit` exporta su propio `Product`. Es el mismo problema que dejó a `TransactionCategory` sin llamarse `Category`, y renombrar tras Production es imposible. |
| **Entrada solo manual.** Nunca foto ni OCR | Decisión del usuario, sin matices. |
| **Cantidad + unidad** en cada línea | Sin ellas el comparador es deshonesto: 1,20 € no dice nada si no se sabe si son 250 g o 500 g. |
| El **total se calcula** sumando las líneas | Un campo menos que teclear y descuadre imposible. Contrapartida asumida: un error de tecleo entra sin aviso. |
| **Sin líneas de ajuste** en la interfaz | Contrapartida asumida y consciente: un cupón global del super no se puede representar, y el gasto de esos tickets queda por encima de lo pagado. El esquema **sí** las admite (`lineTotal` acepta negativos, `product` es opcional), así que activarlas más adelante no exige migrar nada. |
| **Producto creado al vuelo** al teclear uno nuevo | Interrumpir con una confirmación por producto nuevo es lo que hace abandonar en el primer ticket, que es todo productos nuevos. Los duplicados se limpian luego en Ajustes. |
| `Transaction.purchaseLines` con **`.cascade`** | Única excepción al `.nullify` de la casa, fijada por un test. Una línea sin ticket pierde fecha y tienda a la vez y se queda como basura consultable. |
| Marca **dentro del nombre** del producto | "Leche entera Hacendado" y "Leche entera Pascual" no cuestan lo mismo. Un campo de marca obligaría a decidir si el comparador cruza marcas, y esa decisión no tiene respuesta buena. |
| **Sin tabla de alias** de producto | `PurchaseLine.rawName` guarda lo que decía el ticket en cada línea: una tabla de alias se puede derivar de ahí más adelante sin tocar el esquema. |

**Hecho cuando:**

- Apunto el ticket entero del super sin que teclear se haga cuesta arriba, y el total cuadra con el papel.
- El gasto aparece en Resumen y Movimientos como cualquier otro, sin nada roto.
- Busco "pan" y veo cada compra con fecha, tienda y precio por unidad de medida, con la tienda más barata la primera.
- Un formato de 750 g y otro de 1 kg se comparan bien: gana el más barato por kilo, no el de importe menor.
- Las ofertas quedan fuera del ranking salvo que las incluya.
- Borrar un ticket borra sus líneas; borrar un producto **no** borra el histórico.
- La copia CSV exporta y restaura los tickets enteros, y una copia anterior a esta fase sigue restaurando.

### Fuera de fases (candidatos futuros)

Widget de pantalla de inicio con el gasto del mes. Presupuestos por categoría con aviso al superar. Líneas de ajuste en los tickets (cupón global, bolsa, envase): el esquema ya las admite, solo falta ofrecerlas en la interfaz. Atajos de Siri / App Intents para "apunta 12 euros en comida". Exportación a PDF del resumen anual. Face ID al abrir. Cálculo FIFO paralelo al coste medio, si algún día las cifras van a la declaración.

---

## 7 bis. Estrategia de pruebas

No hay QA ni usuarios que reporten fallos: un error de céntimos o un coste medio mal calculado no se detecta hasta que se toma una decisión con un número falso. Las pruebas cubren **el cálculo, no la UI**.

Framework: **Swift Testing** (`@Test`, `#expect`, `arguments:`). Las tablas de casos de aquí abajo son literalmente tablas, y con `arguments:` cada fila falla por separado y dice cuál — con un bucle dentro de un test, solo sabes que algo falló.

**Lo que se prueba, y por qué justo esto:** los servicios son funciones puras sobre valores (§2), lo cual los hace baratos de probar sin levantar un `ModelContainer`.

| Objetivo | Casos mínimos |
|---|---|
| **Aritmética de dinero** | Sumar 1.000 importes de `0,01 €` da exactamente `10,00 €`. Es el test que caza un `Double` colado en un cálculo intermedio. |
| **Parser de importes CSV** | `1.234,56` · `1,234.56` · `1234,56` · `-45,00` · `45,00-` (signo al final, lo usa algún banco) · `1.234` · `(45,00)`. |
| **Parser de fechas** | Los cuatro formatos de §4, con `en_US_POSIX` fijado, comprobando que no dependen del locale del dispositivo. |
| **Saldos y traspasos** | Un `.transfer` de 200 € resta 200 en origen, suma 200 en destino, y aporta 0 al gasto del periodo. |
| **Deduplicación** | Dos filas idénticas en el mismo CSV se importan las dos; reimportar el fichero entero no crea ninguna. |
| **`PortfolioService`** | Compra → venta parcial → split → dividendo, en ese orden, verificando cantidad, coste medio, coste total y P&L realizado tras cada paso contra cifras calculadas a mano. |
| **Invariante de CloudKit** | Un test que recorra el esquema por reflexión y falle si algún atributo es no-opcional sin valor por defecto, si hay una relación sin inversa, si alguna usa `.deny`, o si una entidad se relaciona consigo misma. **Ya se ha cobrado su primera pieza**: nombró las tres relaciones de `ImportProfile`/`ImportRule` a las que les faltaba la inversa, antes de que nadie tocara CloudKit. |

Las pantallas se prueban a mano contra los criterios de "hecho cuando" de cada fase. Automatizar UI tests para un proyecto de una persona cuesta más de lo que ahorra.

---

## 8. Riesgos y decisiones

### Riesgos técnicos

| Riesgo | Impacto | Mitigación |
|---|---|---|
| **CloudKit y migraciones de esquema.** Cambiar un modelo con sync activo puede romper la sincronización o requerir migración manual. | Alto | Congelar el esquema de cada fase antes de usar la app con datos reales. Usar `VersionedSchema` y `SchemaMigrationPlan` desde la Fase 1, aunque al principio solo haya una versión. Hacer copia de seguridad (export CSV) antes de cada actualización con cambio de modelo. |
| **Restricciones de CloudKit sobre el modelo.** Todo opcional o con default, sin `.unique`, sin `.deny`, sin auto-relaciones. | Medio | Ya incorporado en los modelos de §3. Test por reflexión que falle si alguien mete un atributo obligatorio o una relación sin inversa (§7 bis). |
| ~~**`Decimal` puede perder precisión al viajar por CloudKit.**~~ | ~~Alto~~ | **RESUELTO en la Fase 0.** Se almacena como `Double`, pero vuelve con igualdad exacta en los 10 valores patológicos y en la suma del lote. Ver `docs/fase0-resultados.md`. |
| **Esquema de CloudKit en Production es aditivo.** No se pueden borrar campos ni cambiarles el tipo una vez desplegados. | Alto | Meter en el esquema v1 todas las entidades previstas, aunque estén vacías (`ImportProfile`, `ImportRule`). Congelar antes de introducir datos reales. |
| **Fontanería de CloudKit incompleta.** Falta un entitlement o Background Modes y la sincronización no ocurre, o funciona en debug y no en release. | Medio | Tres de los cuatro puntos de §2 verificados en la Fase 0 sobre el binario firmado. Queda el despliegue de esquema a Production, que hay que repetir con **cada** cambio de modelo. |
| **Tres `RecordType` sin desplegar a Production.** SwiftData crea el tipo al sincronizar el PRIMER registro de la entidad, no al arrancar. `CD_FamilyTag`, `CD_ImportProfile` y `CD_ImportRule` no existen aún en Production porque sus tablas siempre han estado vacías. Escribir en una entidad cuyo tipo falta en Production hace que CloudKit rechace la escritura y SwiftData reintente **en silencio**: el dato se queda en el móvil y todo parece ir bien. | Medio | Aceptado a conciencia, sin código: **desplegar de nuevo en cuanto cada una estrene su primera fila** — `FamilyTag` al crear el primer miembro, las dos de importación al empezar la Fase 3. Añadir un `RecordType` es aditivo y no exige migración. Se descartó forzarlos con un botón de depuración; la contrapartida asumida es que esto depende de acordarse. |
| **Cupo de 64 notificaciones locales pendientes** por app en iOS. Con varias facturas recurrentes se agota y las últimas se pierden en silencio. | Medio | `RecurringBillService` programa una ventana deslizante (siguientes 60 días), no todo el futuro, y reprograma al abrir la app. Criterio de cierre de la Fase 2. |
| **Aritmética con `Decimal`.** Es fácil colar un `Double` por descuido en un cálculo intermedio. | Alto (corrección silenciosa) | Prohibir `Double` en cualquier tipo relacionado con dinero. Tests de suma sobre 1.000 importes de céntimos comparando con el valor exacto esperado (§7 bis). |
| **Coste medio con decimales periódicos.** `costeTotal / cantidad` puede no ser exacto (p. ej. 100 € / 3 participaciones). | Medio | Mantener el coste medio a 6 decimales y **derivar siempre el coste total del acumulado**, nunca de `costeMedio × cantidad`. Redondear solo al mostrar. |
| **CSV de banco que cambia de formato.** | Medio | Perfiles de importación por firma de cabeceras: si no coincide, se pide mapear de nuevo en vez de fallar. |
| **Fotos de tickets y límites de CloudKit.** | Bajo | `@Attribute(.externalStorage)` + compresión JPEG antes de guardar. Poner un tope de tamaño. |
| **Borrado propagado.** CloudKit sincroniza, no respalda: un borrado accidental desaparece también de la nube y de cualquier dispositivo futuro. | Alto | Export CSV **manual** en la Fase 1, con restauración probada, más el aviso de antigüedad de la copia. Mitigación parcial y conscientemente aceptada: sin volcado automático, el riesgo depende de acordarse. |
| **Conflictos de sincronización.** Ya no aplica con un solo dispositivo, pero reaparecería si algún día hay un segundo. | Muy bajo | CloudKit resuelve con last-writer-wins. Con un solo usuario es aceptable; no merece la pena implementar CRDT. |

### Decisiones cerradas

| # | Decisión | Motivo |
|---|---|---|
| 1 | **Precios de inversión: híbrido (C), empezando en manual** | La ruta manual hay que construirla igual como respaldo, no tiene dependencias y permite cerrar la Fase 4 sin elegir proveedor. La API se añade después sin tocar el modelo (§5). |
| 2 | **Coste medio ponderado, no FIFO** | Es lo que muestra el bróker y lo estándar para gestión. FIFO exige mantener lotes individuales, triplica `PortfolioService`, y solo aporta si las cifras alimentan la declaración. Se puede añadir después sobre los mismos datos. |
| 3 | **Tarjetas de crédito como `Account` de tipo `.card`** | Contablemente correcto: el gasto se registra el día de la compra, no el día de la liquidación. El "doble movimiento" que parecía costoso no lo es, porque el CSV de la tarjeta trae los movimientos hechos. Afecta a la Fase 1. |
| 4 | **Efectivo como cuenta `.cash` con ajuste mensual** | Registrar cada café a mano es lo que hace abandonar estas apps. Un único movimiento de "gasto en efectivo no detallado" al mes cuadra el saldo y cuesta 30 segundos. Afecta a la Fase 1. |
| 5 | **1 año de histórico importado** | Suficiente para comparativas mes a mes y año anterior. Cinco años dan gráficos bonitos y muchas horas de categorización manual. |
| 6 | **Divisa: `currency` solo en `Asset` y `PriceQuote`** | El precio se guarda en su divisa nativa y se convierte al mostrar. Convertir al guardar destruye el dato real de mercado para siempre, y es irreversible. No abre multidivisa en transacciones: los gastos siguen siendo solo euros (§1). Aplicar antes de la Fase 4. |
| 7 | **Solo iPhone** | Sin iPad no hay `NavigationSplitView` ni layout adaptativo: cada pantalla se diseña una vez. CloudKit se mantiene igual, pero su valor pasa a ser continuidad entre dispositivos y recuperación tras un cambio de móvil, no sincronización simultánea. |
| 8 | **Copia de seguridad: export CSV manual, en la Fase 1** | CloudKit propaga los borrados, así que hace falta una copia fuera de la nube. Se decidió **solo manual**, sin volcado automático. Contrapartida asumida: la copia solo existe cuando uno se acuerda, que es justo lo que el volcado automático cubría. Se compensa con «Última copia: hace N días» en Ajustes, en rojo a partir de 30 — hace visible el olvido, no lo evita. Criterio de cierre: la restauración tiene que estar probada. |

### Decisiones que siguen abiertas

Solo una, y no bloquea nada hasta la Fase 4:

1. **¿Hay en tu cartera fondos no cotizados, o productos que solo se encuentren por ISIN?** No cambia la opción elegida (el híbrido los cubre por la vía manual en cualquier caso), pero determina si merece la pena pagar un proveedor que cubra UCITS europeos o basta con uno gratuito para acciones y ETFs. Responder antes de construir la ruta de API, no antes de empezar la Fase 4.

---

## 9. Por dónde empezar

Fases 0, 1, 2 y 5 cerradas. El siguiente paso es la Fase 3:

0. **Desplegar el esquema a Production otra vez en cuanto se guarde el primer `ImportProfile` o `ImportRule`.** Sus `RecordType` todavía no existen allí (§8); hasta que se desplieguen, el sync de esas dos entidades falla sin decir nada.
1. Revisar `ImportProfile` e `ImportRule` contra un CSV real del banco antes de escribir código. **Ya no hay ventana barata**: el esquema está desplegado a Production, así que cualquier campo que falte entra con `SchemaV2` + `MigrationStage` y copia de seguridad previa. Añadir campos sigue siendo legal; borrarlos o cambiarles el tipo, no.
2. `CSVImportService`: parseo y detección de formato, con tests sobre ficheros reales (coma decimal, punto de millar, fechas del banco), verificando contra la columna de saldo del propio CSV.
3. Deduplicación de dos niveles y deshacer por lote, antes de las pantallas. Es la parte que protege la base de datos.
4. Pantalla de mapeo de columnas con guardado de perfil, y previsualización editable.
5. Autocategorización por `ImportRule`, medida contra un extracto mensual típico (objetivo ≥70%).

**Hecho ya, fuera de la lista:** el target `Spike` se borró el 24/08/2026, tras el despliegue a Production. Su valor está en `docs/fase0-resultados.md`, no en el código; el historial de git lo conserva.

**Deuda arrastrada, aún abierta:** la entrada de cambios de CloudKit en **segundo plano** sigue sin probarse (viene de la Fase 0, §8).
