# Fase 7 — Ingresos recurrentes y pestaña Recurrentes

Estado: **implementada** (27/08/2026). Pendiente de prueba en dispositivo y del
despliegue de esquema a Production.

Objetivo: llevar dentro de la app lo que ENTRA todos los meses —nómina,
servicios facturados como autónomo, suscripciones de apps y webs— con la misma
mecánica que ya tenían las facturas, y un resumen que diga con cuánto se cuenta:
gasto fijo, ingreso fijo y neto, mensual y anual.

---

## 1. Un campo, no una entidad

La opción evidente era `RecurringIncome` como `@Model` nuevo. Se descartó:

- El esquema de las diez entidades se desplegó a Production el **24/08/2026**.
  Una entidad nueva es un `RecordType` nuevo, y un `RecordType` sin desplegar
  **falla en silencio**: los datos se guardan en local y no sincronizan, sin
  error visible (PLAN.md §8).
- Obligaba a romper el alias `SchemaV2.models == SchemaV1.models`, a editar la
  aserción de diez nombres de `SchemaInvariantTests`, a un CSV de copia nuevo, y
  a duplicar `RecurringBillService`, `NotificationPlanner` y las tres vistas.
- Un ingreso recurrente **es** un gasto recurrente con el signo cambiado: mismas
  ocurrencias, mismo día del mes, mismos avisos, misma forma de marcarlo hecho.

Así que `RecurringBill` gana un atributo:

```swift
var kindRaw: String = TransactionKind.expense.rawValue

var kind: TransactionKind {
    get {
        let value = TransactionKind(rawValue: kindRaw) ?? .expense
        return value == .income ? .income : .expense
    }
    set { kindRaw = (newValue == .income ? TransactionKind.income : .expense).rawValue }
}
```

El **valor por defecto es lo que hace compatible el cambio**: las filas que ya
estaban sincronizadas eran facturas, y se leen como gastos sin convertir nada.
`.transfer` no significa nada aquí y el getter lo normaliza, igual que un raw
corrupto.

La clase sigue llamándose `RecurringBill` a propósito: renombrarla renombraría
el `RecordType`, que no es una operación aditiva.

## 2. `SchemaV3`, otra vez sin `MigrationStage`

Mismo razonamiento que la Fase 6 (`docs/fase6-transporte.md` §2.3): las tres
versiones describen **las mismas clases**, tienen el mismo checksum, y un stage
ligero entre dos versiones idénticas aborta la app dentro de
`NSLightweightMigrationStage.init`. Añadir una columna con default es justo lo
que CoreData migra por su cuenta.

`AppContainer` abre `Schema(SchemaV3.models)`. `ILoveFinancesMigrationPlan.schemas`
pasa a `[V1, V2, V3]`, `stages` sigue vacío.

### Lo que queda fuera del código

**Redesplegar el esquema a Production** en el Dashboard de CloudKit tras el
primer arranque. Hasta que se haga, `CD_kindRaw` no existe allí y los ingresos
recurrentes no sincronizan entre dispositivos — sin error.

## 3. Normalización mensual y anual

No había nada parecido en el proyecto. Dos piezas:

- `Recurrence.occurrencesPerYear`: 52 / 26 / 12 / 6 / 4 / 2 / 1. Semanal y
  quincenal son aproximaciones deliberadas (52 semanas son 364 días); la
  alternativa, 365/7, mete un decimal periódico en todas las sumas para no ganar
  nada en una cifra que ya es una estimación.
- `RecurringBillService.summary(bills:on:)` → `Summary` con gasto e ingreso
  mensual y anual, y `monthlyNet` / `annualNet`.

Dos decisiones dentro:

- El mensual sale del anual (`anual / 12`), no al revés. Redondear el mensual y
  multiplicarlo por doce desvía hasta doce céntimos.
- Cuenta lo **vigente**: activo y no terminado. Lo que empieza en el futuro **sí**
  cuenta — un alquiler que arranca el mes que viene ya es un compromiso, y
  descubrirlo el día 1 es lo que esta pantalla existe para evitar.

Es una cifra distinta de la de "Próximas": un seguro anual de 600 € pesa 50 €
todos los meses aunque solo se cobre en junio.

## 4. Avisos

El cuerpo del aviso cambia según el tipo: un ingreso dice "Entran 1.800,00 € el
30 · Santander", porque no es algo pendiente de hacer.

La clave sigue siendo `bill-<uuid>-<yyyy-MM-dd>`, así que `NotificationService`
—que filtra lo suyo por ese prefijo— no se toca y no quedan avisos huérfanos.

**El cupo de 64 pasa a compartirse** entre gastos e ingresos. No se reparte por
tipo: se ordena por fecha de disparo y se corta, así que lo que se pierde es lo
más lejano, que es lo que recupera la siguiente reprogramación. Hay test.

## 5. Pantallas

`BillsView` pasa a **`RecurringView`** y la pestaña se llama **Recurrentes**
(`Resumen · Movimientos · Bus · Recurrentes · Compras`).

- Selector arriba: **Gastos | Ingresos | Todo**, guardado en `@AppStorage`. No es
  un filtro de un rato: quien vive de facturas abre siempre en gastos.
- Sección **Resumen** con mensual y anual del scope; en "Todo", las tres líneas
  con el neto coloreado por signo.
- "Próximas" y el listado, ya con importes en verde o con signo según el tipo
  (`AmountText`, que ahora acepta importe + tipo además de una `Transaction`).
- El alta se abre del tipo que se está mirando.
- Palabras por tipo en editor, detalle y alta rápida: "Pagada" / "Cobrada",
  "Media pagada" / "Media cobrada", "Dónde se carga" / "Dónde entra".
- En el detalle, la desviación respecto al estimado **se colorea al revés** en un
  ingreso: cobrar de más es buena noticia.

`BillEditorView` filtra categorías por el tipo elegido (ya había seis de ingreso
sembradas: Nómina, Autónomo, Alquiler, Dividendos, Devoluciones, Otros) y limpia
la categoría al cambiar de tipo, para no dejar una de gasto colgando de un
ingreso.

`QuickAddView` toma el tipo del recurrente en vez de forzar `.expense`. Es la
línea crítica de toda la fase: sin ella, una nómina marcada como cobrada entraría
como un gasto de 1.800 €.

### Resumen (Dashboard)

- Tarjeta **Recurrentes** con gasto fijo, ingreso fijo y neto, mensual y anual.
- "Próximas facturas" pasa a "Próximos 30 días" con **dos totales separados**, a
  pagar y a cobrar. El total anterior era un `reduce` ciego al signo que habría
  sumado los ingresos como si fueran facturas.

## 6. Copia de seguridad

`recurring_bills.csv` gana la columna `kind` **al final**. La importación lee por
nombre de columna, así que una copia anterior a esta fase simplemente no la trae
y todo lo suyo se restaura como gasto. Hay test de las dos direcciones.

## 7. Pruebas

`ILoveFinancesTests/RecurringIncomeTests.swift`, 12 casos:

- Un recurrente sin tipo explícito es un gasto; un raw corrupto o un traspaso
  también.
- `occurrencesPerYear` de las siete periodicidades.
- El resumen normaliza un mix de mensual, anual, trimestral e ingresos; ignora
  desactivados y terminados; incluye lo que empieza en el futuro.
- Marcar cobrada una nómina crea una `Transaction` de tipo ingreso y **sube el
  saldo** de la cuenta.
- El aviso de un ingreso dice "Entran"; el de una factura no.
- Gastos e ingresos comparten el cupo de 64 ordenados por fecha, y en el corte
  entran de los dos tipos.
- Copia de seguridad: ida y vuelta con un ingreso, y restauración de un CSV sin
  la columna.

Suite completa: **112 tests en 15 suites**, en verde.

## 8. Hecho cuando (pendiente, en dispositivo)

- Doy de alta la nómina (mensual, día 30) y una suscripción anual, y las próximas
  6 ocurrencias del editor salen bien.
- El resumen de la pestaña dice gasto fijo, ingreso fijo y neto, mensual y anual,
  y cuadra con lo dado de alta.
- La tarjeta del Dashboard dice lo mismo.
- Marco un cobro y aparece en Movimientos como **Ingreso**, con el saldo subiendo.
- Llega el aviso del ingreso y dice que entra, no que hay que pagar.
- **Esquema redesplegado a Production** y el ingreso visible en un segundo
  dispositivo.
