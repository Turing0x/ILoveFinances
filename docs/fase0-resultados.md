# Fase 0 — Resultados

Estado: **en curso**. Pendiente el viaje de ida y vuelta (Paso 4), que necesita
el iPhone desbloqueado.

Entorno: Xcode 26.6 (build 17F113) · SDK iOS 26.5 · Swift 6.3.3 en modo de
lenguaje 5 · iPhone 17 Pro Max físico (`FB3ABB2D-4067-5778-ACC3-011341DCB429`)
· team `M2J9PP4RR8`.

---

## Paso 6 — Comprobaciones secundarias · RESUELTAS

Ejecutadas en el simulador (no dependen de CloudKit: usan un contenedor en
memoria).

### 1. `#Index` compila

```swift
#Index<MoneyProbe>([\.createdAt], [\.label])
```

Compila sin avisos con deployment target iOS 26.0. **La premisa que justificaba
subir el target se sostiene**, y la Fase 1 puede apoyarse en índices en vez de
arrastrar el riesgo de rendimiento que `PLAN.md` §8 daba por abierto.

### 2. `Decimal` dentro de `#Predicate` · FUNCIONA

No basta con que compile: SwiftData traduce el predicado a Core Data en tiempo
de ejecución, y es ahí donde falla si no soporta el tipo. Por eso se ejecuta un
`fetch` real.

```
Filtro [1,00 .. 100000,00] sobre asDecimal -> ["cantidad", "precio"]
```

Correcto: de las diez sondas, solo `precio` (19,99) y `cantidad` (12,345678)
caen dentro. **El filtro de rango de importe de la pantalla de Movimientos
(`PLAN.md` §6) puede ir sobre `Decimal`.**

> Nota metodológica: la primera versión de esta comprobación daba FALLO, y el
> fallo estaba en el test, no en SwiftData — la lista de esperados se había
> escrito a mano y se olvidaba `cantidad`. Ahora los esperados se derivan de los
> propios fixtures aplicando el mismo filtro. Un test cuya expectativa se teclea
> a mano comprueba la memoria de quien lo escribió, no el sistema.

---

## Paso 5 — Fontanería de CloudKit · 3 de 4

Verificado sobre el **binario firmado**, no sobre los ficheros fuente — que es
la distinción que hace útil la comprobación.

| Punto | Estado | Evidencia |
|---|---|---|
| Capability iCloud + CloudKit | OK | La app firma y se instala en el iPhone. El perfil `iOS Team Provisioning Profile: dev.threedots.ilovefinances.spike` incluye `iCloud.dev.threedots.ilovefinances.spike`. |
| Background Modes → remote notifications | OK | `plutil -extract UIBackgroundModes` sobre el `Info.plist` **del bundle construido** devuelve `["remote-notification"]`. |
| `aps-environment` | OK | `codesign -d --entitlements` sobre el `.app` firmado: `<string>development</string>`. |
| Despliegue de esquema a Production | Pendiente | Requiere que el esquema exista en Development, o sea, haber sembrado antes. |

El contenedor `iCloud.dev.threedots.ilovefinances.spike` lo registró Xcode solo
al construir con `-allowProvisioningUpdates`; no hizo falta tocar el portal.

---

## Paso 3 — Tipo real en el `CKRecord`

Pendiente.

## Paso 4 — Viaje de ida y vuelta

Pendiente.

---

## Desviaciones respecto al plan

- **El contenedor real `iCloud.dev.threedots.ilovefinances` no se ha creado.**
  El plan proponía aprovechar el momento, pero registrar un contenedor exige un
  target que lo declare en sus entitlements, y el único target que existe es el
  spike — que no debe tocarlo. Se creará en la Fase 1 al nacer el target real.
  Coste de aplazarlo: ninguno.
- **Añadidos dos ficheros no previstos**, `ProbeVerifier.swift` (la comparación
  contra los esperados, que en el plan vivía dentro de la vista) y
  `AutoRunner.swift` (modo por argumentos de lanzamiento). El segundo existe
  porque la secuencia del Paso 4 —sembrar, esperar, inspeccionar, desinstalar,
  reinstalar, verificar— es larga y se presta a ejecutarla en mal orden; poder
  lanzarla desde la terminal la hace repetible.
