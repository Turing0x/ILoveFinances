# Fase 0 — Resultados

**Cerrada el 24 de agosto de 2026**, salvo el despliegue de esquema a Production
(ver *Pendiente* al final).

**Veredicto: se mantiene `Decimal`.** El plan B de enteros escalados queda
descartado y eliminado de `PLAN.md` §3.

Entorno: Xcode 26.6 (17F113) · SDK iOS 26.5 · Swift 6.3.3 en modo de lenguaje 5
· iPhone 17 Pro Max físico (`FB3ABB2D-4067-5778-ACC3-011341DCB429`) · team
`M2J9PP4RR8` · contenedor desechable `iCloud.dev.threedots.ilovefinances.spike`.

---

## La pregunta

`PLAN.md` §3 apoya todo el diseño monetario en `Decimal`, pero CloudKit no tiene
tipo decimal. Si `NSPersistentCloudKitContainer` lo degradaba a `Double`, los
importes volverían de la nube con error de precisión — invisible en una fila,
acumulable en un total anual. `PLAN.md` §8 lo clasificaba como riesgo Alto.

## La respuesta, en dos mitades

### Cómo se guarda: como `Double`. El riesgo era real.

Volcado del `CKRecord` crudo, campo a campo (`--inspect`):

```
CD_asDecimal            Double      0.010000000000000000208
CD_asDouble             Double      0.010000000000000000208
CD_asScaledInt          Int64       1
CD_asString             NSTaggedPointerString "0.01"
CD_isBatchItem          Int64       1
CD_scale                Int64       100
```

`CD_asDecimal` viaja como `Double`, con **exactamente los mismos bits** que el
campo de control `CD_asDouble`. La sospecha estaba fundada.

> Detalle que estuvo a punto de dar un falso negativo: la primera versión del
> inspector imprimía `__NSCFNumber` para todo campo numérico y `CD_asScaledInt`
> —que es un `Int`— salía como `1.0`. `type(of:)` devuelve la clase puente de
> `NSNumber`, e intentar `as? Double` tampoco sirve porque `NSNumber` se puentea
> a `Double` aunque dentro lleve un entero. Lo único que lo distingue es
> `objCType`. Sin esa corrección el volcado no habría respondido nada.

### Cómo vuelve: intacto. El riesgo no se materializa.

Viaje completo: sembrar en el iPhone → esperar al mirroring → **desinstalar la
app** (borra el store local, no los datos de CloudKit) → reinstalar → dejar
rehidratar → comparar con `==` exacto de `Decimal`.

Los 210 registros volvieron de la nube sin intervención.

```
  label     esperado        Decimal  Escalado  String   Double
  simple    0.1             OK       OK        OK       OK
  siete     0.07            OK       OK        OK       OK
  suma      0.3             OK       OK        OK       OK
  precio    19.99           OK       OK        OK       FALLO
  grande    1234567.89      OK       OK        OK       FALLO
  redondeo  0.615           OK       n/a       OK       OK
  negativo  -45             OK       OK        OK       OK
  techo     99999999.99     OK       OK        OK       FALLO
  micro     0.005           OK       n/a       OK       OK
  cantidad  12.345678       OK       OK        OK       OK

LOTE — 200 de 200 filas de 0,01 EUR
  esperado           2
  suma de Decimal    2  OK
  suma de escalados  2  OK
  suma de Double     2  OK
```

**`Decimal` acierta en las diez sondas y en la suma del lote.** Se almacena como
`Double`, pero la conversión de vuelta recupera el decimal original: la
representación decimal más corta que round-trippea con ese `Double` es el valor
que se guardó, para cualquier importe de magnitud realista.

Dos lecturas de la tabla que importan más que el OK:

- **La columna `Double` falla en tres filas.** Eso es lo que hace creíble el
  resultado. Si el control hubiera salido limpio, un "todo OK" solo probaría que
  la comparación no mide nada — por eso el veredicto se niega a emitirse si el
  control no falla en ninguna fila.
- **`n/a` en Escalado no es un fallo.** `0,615` y `0,005` tienen 3 decimales y la
  escala de céntimos (10²) solo guarda 2. Es el límite de la escala, no una
  pérdida del viaje. La primera versión del informe los marcaba como FALLO y
  eso convertía el resultado en ruido.

### Lo que esto deja como aviso para la Fase 4

Que los enteros escalados no puedan con `0,005` es irrelevante ahora, pero
señala algo real: **una escala de céntimos no representa fracciones de céntimo.**
Si algún día un precio por unidad o un tipo de cambio necesita más de 2
decimales, `Decimal` sigue valiendo y el entero escalado no. Un motivo más para
no haber migrado.

---

## Comprobaciones secundarias (Paso 6)

### `#Index` compila

```swift
#Index<MoneyProbe>([\.createdAt], [\.label])
```

Sin avisos, con deployment target iOS 26.0. **La premisa que justificaba subir
el target se sostiene** y el riesgo de rendimiento que `PLAN.md` §8 daba por
abierto desaparece.

### `Decimal` funciona dentro de `#Predicate`

No basta con que compile: SwiftData traduce el predicado a Core Data en tiempo
de ejecución. Con un `fetch` real, el filtro `[1,00 .. 100000,00]` devuelve
`["cantidad", "precio"]` — correcto. **El filtro de rango de importe de la
pantalla de Movimientos (`PLAN.md` §6) puede ir sobre `Decimal`.**

> La primera versión daba FALLO, y el fallo estaba en el test: los esperados se
> habían escrito a mano y se olvidaba `cantidad` (12,345678), que sí cae en el
> rango. Ahora se derivan de los propios fixtures aplicando el mismo filtro. Un
> test cuya expectativa se teclea a mano comprueba la memoria de quien lo
> escribió, no el sistema.

---

## Fontanería de CloudKit (Paso 5)

Verificado sobre el **binario firmado**, no sobre los ficheros fuente — que es
lo que hace útil la comprobación.

| Punto | Estado | Evidencia |
|---|---|---|
| Capability iCloud + CloudKit | OK | Perfil `iOS Team Provisioning Profile: dev.threedots.ilovefinances.spike`, con `iCloud.dev.threedots.ilovefinances.spike` dentro. |
| Background Modes → remote notifications | OK | `plutil -extract UIBackgroundModes` sobre el `Info.plist` del bundle construido: `["remote-notification"]`. |
| `aps-environment` | OK | `codesign -d --entitlements` sobre el `.app` firmado: `development`. |
| Despliegue a Production | **Pendiente** | Ver abajo. |

**El contenedor iCloud no hizo falta crearlo a mano.** El plan lo daba por
inevitable; `xcodebuild -allowProvisioningUpdates` lo registró solo al construir
para el dispositivo.

**Entrada de cambios en segundo plano: no probada.** Con un solo dispositivo no
se puede generar un cambio externo limpio. Lo verificado es que el mirroring
importa datos que este dispositivo no tiene (la rehidratación tras reinstalar),
que no es lo mismo. Queda pendiente para la Fase 1.

---

## Pendiente

**Desplegar el esquema del contenedor spike a Production.** Es una acción en el
CloudKit Console (web) sobre la cuenta de Apple, así que la tiene que hacer
Raúl: console.cloudkit.apple.com → contenedor `iCloud.dev.threedots.ilovefinances.spike`
→ Deploy Schema to Production. Ensaya el flujo sin tocar el contenedor real.

**Contenedor real `iCloud.dev.threedots.ilovefinances`: sin crear**, a propósito.
Registrarlo exige un target que lo declare en sus entitlements, y el único que
existe es el desechable, que no debe tocarlo. Nace con el target real en la
Fase 1. Coste de aplazarlo: ninguno.

**El target `Spike` sigue en el repositorio.** El plan preveía borrarlo al
cerrar; se mantiene hasta que el despliegue a Production esté hecho, por si hay
que volver a sembrar. Su valor está en este documento, no en el código.

---

## Desviaciones respecto al plan

- **Dos ficheros no previstos.** `ProbeVerifier.swift`, porque la comparación
  contra los esperados no cabía dentro de la vista sin ensuciarla; y
  `AutoRunner.swift`, que permite ejecutar la secuencia por argumentos de
  lanzamiento. Esta segunda resultó decisiva: la secuencia completa —sembrar,
  esperar, inspeccionar, desinstalar, reinstalar, verificar— se repitió cuatro
  veces al ir corrigiendo el propio instrumental, y hacerlo a base de toques
  habría sido inviable.
- **Se añadió un guardia al veredicto**: si el control `Double` no falla en
  ninguna fila, el informe se niega a concluir. Un test que no distingue entre
  "no hay pérdida" y "no estoy midiendo" no sirve para decidir un esquema
  permanente.

## Cómo repetirlo

```bash
xcodegen generate
xcodebuild -project ILoveFinances.xcodeproj -scheme Spike \
  -destination 'id=FB3ABB2D-4067-5778-ACC3-011341DCB429' \
  -allowProvisioningUpdates build
```

```bash
xcrun devicectl device process launch --console --terminate-existing \
  --device FB3ABB2D-4067-5778-ACC3-011341DCB429 \
  dev.threedots.ilovefinances.spike --seed
```

Argumentos: `--seed`, `--inspect`, `--verify`, `--secondary`, `--wipe`.
