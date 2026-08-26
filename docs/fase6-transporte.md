# Fase 6 — Tarjetas de transporte y pestaña Bus

Estado: **implementada** (26/08/2026). Pendiente de prueba en dispositivo y del
despliegue de esquema a Production.

Objetivo: llevar el saldo de las tarjetas de transporte (bus) dentro de la app,
con la recarga como traspaso y el descuento por viaje en dos toques desde una
pestaña propia.

---

## 0. El widget, descartado

El plan inicial incluía un widget de pantalla de inicio con un toque = un viaje.
**Se descartó antes de escribir una línea de él**, y conviene que quede escrito
para no volver a proponerlo sin pensarlo:

- Una extensión de widget es otro proceso, con otro contenedor. Para que pudiera
  leer y escribir la base de datos habría que **mover el store SwiftData a un App
  Group**: copiar `default.store`, `-wal` y `-shm` a otro sitio, con datos reales
  ya sincronizados con CloudKit dentro. Es la operación de más riesgo de todo el
  proyecto.
- A cambio ahorraba abrir la app. Dos toques dentro de la app cuestan poco.

El `AppIntent` que haría falta no existe todavía, así que el día que se retome —
widget de pantalla de inicio o `ControlWidget` en el Centro de Control— se
empieza por ahí. `TransportService` ya está preparado: toda la lógica del viaje
vive fuera de las vistas precisamente para poder llamarla desde otro proceso.

---

## 1. Modelo contable

| Hecho real | En la app |
|---|---|
| Tarjeta de bus con saldo | `Account` de tipo `.transport` |
| Recargar la tarjeta | `Transaction` `.transfer` desde la cuenta que paga → la tarjeta |
| Coger el bus | `Transaction` `.expense` **sobre la propia tarjeta**, importe = `farePerTrip` |

**El gasto se reconoce al viajar, no al recargar.** Es la decisión cerrada #3 de
`PLAN.md` (las tarjetas de crédito) aplicada a otro sitio: como un traspaso
aporta cero a `incomeExpenseAmount`, "Transporte" en el resumen del mes es el
dinero realmente viajado y no un pico de 20 € el día de la recarga.

El saldo **no se persiste**: sale de `Account.balance`, que ya suma las dos
orillas de un traspaso. Por eso deshacer un viaje es simplemente borrar su
transacción, sin ningún contador que corregir.

---

## 2. Modelo de datos

### 2.1 `AccountType.transport`

Caso nuevo, con label "Tarjeta de transporte" y símbolo `bus`. `typeRaw` es
`String`, así que **añadir un caso no toca el esquema de CloudKit**.

### 2.2 Dos atributos en `Account`

```swift
var transportCardNumber: String?
var farePerTrip: Decimal = Decimal.zero
```

Cumplen los invariantes que fija `SchemaInvariantTests`: uno opcional, el otro
con valor por defecto. Y dos derivados, sin persistir: `isTransportCard` y
`remainingTrips` (viajes que quedan, truncando hacia abajo).

**No se añadió ningún marcador `isTransportTrip` a `Transaction`.** Un gasto
sobre una cuenta `.transport` ya es la definición de viaje; un campo
denormalizado más en un esquema ya desplegado, a cambio de nada.

### 2.3 `SchemaV2`, y por qué no hay `MigrationStage`

El esquema está desplegado a Production desde el 24/08/2026 y ya hay datos
reales. El cambio es aditivo, que es lo único legal ahí.

Se creó `SchemaV2` (versión `2.0.0`, las mismas diez entidades) y se enchufó al
`SchemaMigrationPlan` y a `AppContainer`. **Lo que no hay es un stage, y no por
dejadez: con un `.lightweight(fromVersion: SchemaV1.self, toVersion:
SchemaV2.self)` la app ABORTA al arrancar**, dentro de
`NSLightweightMigrationStage.init`. Un stage exige que las dos versiones
describan modelos distintos, y aquí `SchemaV2.models` son literalmente las mismas
clases que `SchemaV1.models`, con el mismo checksum.

Tener un stage de verdad obligaría a duplicar las diez clases `@Model` dentro de
un `enum SchemaV1` propio y congelarlas para siempre. Se decidió no pagar eso por
dos atributos opcionales: CoreData migra este caso —añadir columnas— en ligero
por su cuenta, y los 101 tests pasan sobre el esquema resultante.

**Regla para el próximo cambio:** si es aditivo, se sube el `versionIdentifier` y
ya. Si **no** lo es —renombrar un campo, cambiar un tipo, partir una entidad—
entonces sí toca el namespace congelado y el stage escrito a mano, porque ahí la
migración automática no existe y el fallo sería pérdida de datos, no un aborto
visible.

### 2.4 Lo que queda por hacer fuera del código

1. **Export CSV antes de instalar** esta versión. Hay datos reales.
2. **Volver a desplegar el esquema a Production en cuanto se guarde la primera
   tarjeta.** `CD_Account.transportCardNumber` y `farePerTrip` no existen allí, y
   escribir en un campo que Production no conoce hace que CloudKit rechace la
   escritura y SwiftData reintente **en silencio**: el dato se queda en el móvil y
   todo parece ir bien. Mismo agujero ya documentado en §8 de `PLAN.md` para
   `CD_FamilyTag`.

---

## 3. `TransportService`

`ILoveFinances/Services/TransportService.swift`. Toda la lógica del viaje fuera
de las vistas: lo piden los tests hoy y lo pedirá el widget el día que se haga.

- `cards(context:)` — tarjetas activas, ordenadas por nombre. El filtro por tipo
  va en memoria, no en un `#Predicate`: comparar contra el rawValue de un enum
  dentro de un predicado es de lo que SwiftData traduce mal.
- `trips(card:limit:)` y `trips(card:in:)` — se leen de la relación
  `card.transactions`, no con un predicado sobre relación (la parte frágil de
  SwiftData, ver `TransactionFilter`).
- `spent(card:in:)`, `balanceAfterTrip(card:)`.
- `registerTrip(card:date:context:)` — gasto por la tarifa, con concepto "Viaje",
  `merchant` = nombre de la tarjeta y categoría `Transporte` **si existe**; si
  alguien la borró, el viaje se guarda sin categoría en vez de fallar. Devuelve la
  transacción para poder deshacerla.
- `undo(trip:context:)`.

**Saldo insuficiente: avisa, no bloquea.** Apuntar los viajes de ayer antes de
apuntar la recarga que ya se hizo es un orden de trabajo normal; bloquearlo
convertiría una app de apuntes en un validador. El aviso ("Te quedarías en
−0,20 €") vive en la confirmación de la pantalla, no en el servicio.

Lanza en dos casos, los dos de programación: cuenta que no es de transporte, y
tarifa sin configurar.

---

## 4. Pantallas

### Pestaña Bus

`ILoveFinances/Features/Transport/TransportView.swift`. Quinta pestaña, en el
orden `Resumen · Movimientos · Bus · Facturas · Compras`.

- Tarjeta con nombre, número, saldo grande y "Quedan N viajes".
- Con más de una tarjeta, un selector segmentado; con una sola no hay nada que
  elegir.
- Botón ancho **"Utilizada en viaje"** → `confirmationDialog` con el importe y el
  saldo resultante → registra.
- Tras registrar, fila "Viaje registrado · **Deshacer**" que se apaga sola a los
  8 segundos (con `.task(id:)`, no comparando fechas: nada volvería a dibujar la
  vista al vencer el plazo).
- Viajes del mes con swipe-to-delete y pie con el total.
- Toolbar **"Recargar"** → `QuickAddView` prellenado como traspaso hacia la
  tarjeta, vía `TransportRechargePrefill`, mismo patrón que el `BillPrefill` de
  la Fase 2. El importe no se prellena: cambia en cada recarga.
- Estado vacío con botón que abre el editor de cuenta ya en tipo `.transport`.

### Alta de la tarjeta

En `AccountEditor` (Ajustes → Cuentas), sección condicionada a `type ==
.transport` con número y precio por viaje. Guardar exige tarifa > 0; el número es
opcional. Fuera del tipo transporte los dos campos se limpian al guardar, y el
campo de IBAN se oculta para las tarjetas de transporte, que no lo tienen.

`AccountEditor` acepta ahora un `initialType`, que es lo que permite entrar
directo desde la pestaña Bus.

---

## 5. Limpieza incluida: `Money.parseInput`

El parseo del importe tecleado (coma o punto → `Decimal` con locale POSIX) estaba
**copiado en seis vistas**. Ahora vive en `Money.parseInput(_:)` y las seis lo
usan.

Al escribir sus tests apareció un fallo que las seis copias compartían: un `","`
suelto —lo que queda al borrar el campo con el teclado decimal— se parseaba como
**0** en vez de como "todavía no hay nada escrito". `parseInput` exige al menos un
dígito.

---

## 6. Copia de seguridad

`BackupService` exporta dos columnas más al final de `accounts.csv`:
`transportCardNumber` y `farePerTrip`. Se leen por nombre y toleran su ausencia,
así que **una copia hecha antes de esta fase sigue restaurando** — fijado por un
test.

---

## 7. Pruebas

101 tests en verde. Nuevos:

- `TransportServiceTests` (12): la tarifa se descuenta exacta; diez viajes sobre
  20,00 € a 1,20 € dejan 8,00 € **exactos**; la recarga no cuenta como gasto y el
  viaje sí; deshacer devuelve el saldo; saldo insuficiente no bloquea; sin tarifa
  o sobre una cuenta que no es tarjeta, lanza; con y sin la categoría sembrada;
  listado que excluye archivadas; viajes restantes truncados; gasto del periodo.
- `BackupRoundTripTests`: ida y vuelta de una tarjeta, y restauración de una copia
  anterior a esta fase.
- `MoneyArithmeticTests`: `parseInput` con coma, punto, espacios, vacío, ilegible.
- `SchemaInvariantTests`: el plan de migración termina en la versión que la app
  abre.

---

## 8. Hecho cuando (pendiente, en dispositivo)

- Se crea una tarjeta con número y precio por viaje, y aparece en Cuentas con su
  saldo.
- Una recarga desde la corriente sube el saldo de la tarjeta, baja el de la
  corriente, y **no** aparece como gasto en el Resumen del mes.
- Desde Bus, dos toques registran un viaje y el saldo baja exactamente el precio
  configurado.
- El viaje aparece en Movimientos como gasto de Transporte y se puede deshacer,
  desde el aviso y con swipe.
- Con dos tarjetas, se elige cuál sin salir de la pestaña.
- Un viaje con saldo insuficiente avisa y deja continuar.
- Restaurar la copia CSV anterior a esta fase sigue funcionando.
- **Tras guardar la primera tarjeta: redesplegar el esquema a Production** y
  comprobar que la tarjeta llega a iCloud.
