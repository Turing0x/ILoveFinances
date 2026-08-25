# Prompt para extraer un ticket de compra a JSON

Pega este prompt en Claude junto con la **foto del ticket**. Su respuesta se
pega tal cual en la app: pestaña **Compras › + › Pegar ticket en JSON…**

El formato coincide con el modelo de datos de la Fase 5 (`Transaction` como
cabecera del ticket, `PurchaseLine` por línea, `GroceryProduct` normalizado).

---

## El prompt

````text
Eres un extractor de datos de tickets de compra españoles. Te doy la foto de un
ticket y devuelves ÚNICAMENTE un objeto JSON, sin texto antes ni después.

## Formato exacto

{
  "shop": "nombre del comercio tal y como aparece en el ticket",
  "date": "yyyy-MM-dd",
  "ticketTotal": "43.17",
  "lines": [
    {
      "rawName": "PAN BARRA 250G",
      "product": "Pan de barra",
      "quantity": "1",
      "unit": "unit",
      "lineTotal": "1.20",
      "discount": "0.00",
      "isOffer": false
    }
  ],
  "warnings": []
}

## Reglas de cada campo

- **Todos los números van como TEXTO entre comillas**, nunca como número JSON.
  Usa punto decimal y no pongas separador de millar: "1234.56", no "1.234,56".
  Es dinero y no puede perder precisión.

- **rawName**: lo que dice LITERALMENTE el ticket, en mayúsculas y con sus
  abreviaturas. No lo corrijas ni lo interpretes. Es el dato en bruto.

- **product**: el mismo producto con nombre limpio y estable, como lo diría una
  persona. Aquí SÍ normaliza: "LECHE ENT HAC 6X1L" → "Leche entera Hacendado".
  Incluye la marca dentro del nombre si el ticket la trae, porque dos marcas
  distintas no cuestan lo mismo y se comparan por separado. Quita del nombre el
  formato y el peso: el tamaño va en `quantity` + `unit`, no en el nombre.
  Usa siempre el MISMO nombre para el mismo producto entre tickets distintos.

- **quantity** y **unit**: el tamaño real de lo comprado.
  - `unit` sólo puede ser uno de estos cinco valores exactos:
    `unit` (unidades), `kg`, `g`, `l`, `ml`.
  - Si el ticket dice "2 x 1,20" → `quantity` "2", `unit` "unit", `lineTotal` "2.40".
  - Si dice "0,850 kg x 5,00 €/kg" → `quantity` "0.850", `unit` "kg", `lineTotal` "4.25".
  - Si el producto lleva el formato en el nombre ("LECHE 6X1L"), pásalo a la
    cantidad: `quantity` "6", `unit` "l".
  - Si no hay cantidad visible, pon "1" y `unit` "unit".
  - No conviertas entre magnitudes: los litros no se pasan a kilos jamás.

- **lineTotal**: el importe BRUTO de esa línea tal y como está impreso, antes de
  descuentos. No es el precio por unidad: es el total de la línea.

- **discount**: el descuento de ESA línea, **en positivo**. La app lo resta sola.
  Omite el campo si esa línea no lleva descuento.
  - Los tickets suelen imprimir el descuento en una línea aparte, justo debajo
    del producto y **vinculado por un código**. Ejemplo real de Carrefour:
    ```
    NAPOLITANA SUREME        CD62
       3 x ( 0,85 )                  2,55
    DESCUENTO EN 2ª UNIDAD   CD62   -0,64
    ```
    El `CD62` aparece en las dos: ese es el vínculo. Eso NO son dos líneas, es
    una sola con `lineTotal` "2.55" y `discount` "0.64".
  - Si no hay código, usa la proximidad: un descuento suele ir inmediatamente
    debajo del producto al que se aplica.
  - Cuando el producto rebajado no trae línea de descuento aparte, sino que ya
    aparece con el precio rebajado, pon ese importe en `lineTotal`, omite
    `discount` y marca `isOffer` en `true`.

- **isOffer**: `true` si el ticket marca esa línea como oferta, promoción o
  precio rebajado. Si no lo dice, `false`. **No hace falta ponerlo cuando hay
  `discount`**: la app marca esas líneas como oferta automáticamente.

- **ticketTotal**: el total impreso del ticket, el que pagaste (ya con los
  descuentos aplicados). Sirve de comprobación: la app avisa si no cuadra con la
  suma de las líneas una vez restados sus descuentos.

- **date**: la fecha del ticket en `yyyy-MM-dd`. Si no se lee, omite el campo
  entero; no la inventes ni pongas la de hoy.

- **warnings**: lista de avisos en español para el usuario. Mete aquí:
  - Líneas que no has podido leer bien o de las que dudas.
  - Descuentos GLOBALES que se aplican a la compra entera (un cupón, un % sobre
    el total, puntos de fidelidad): la app todavía no los admite, así que NO los
    incluyas en `lines`; menciónalos aquí y avisa de que el total no cuadrará.
    Ojo: esto NO se aplica a los descuentos de línea, que sí van en su `discount`.
  - Las bolsas y los envases SÍ son líneas normales: son algo que has comprado.
  - Cualquier motivo por el que el total no vaya a cuadrar.
  Si no hay nada que avisar, devuelve una lista vacía.

## Reglas generales

- Si un dato no se lee con seguridad, omite el campo opcional y dilo en
  `warnings`. NO inventes datos: es peor un importe inventado que un hueco.
- Incluye TODAS las líneas de producto del ticket, en el mismo orden del papel.
- No incluyas líneas que no sean productos: totales, subtotales, IVA, forma de
  pago, puntos de fidelidad, ahorro acumulado.
- Responde sólo con el JSON.
````

---

## Ejemplo de respuesta

Ticket real de Carrefour Express. Fíjate en la napolitana: el `-0,64` del papel
va como `discount`, no como línea aparte. Y la bolsa es un producto más.

```json
{
  "shop": "CARREFOUR EXPRESS",
  "date": "2026-08-24",
  "ticketTotal": "10.17",
  "lines": [
    {
      "rawName": "TOALLITA BEBE X 80",
      "product": "Toallitas de bebé",
      "quantity": "80",
      "unit": "unit",
      "lineTotal": "1.09"
    },
    {
      "rawName": "WAFER CHOCOLATE",
      "product": "Wafer de chocolate",
      "quantity": "1",
      "unit": "unit",
      "lineTotal": "1.29"
    },
    {
      "rawName": "BIFRUTAS TROPICAL 6U",
      "product": "Bifrutas tropical",
      "quantity": "6",
      "unit": "unit",
      "lineTotal": "2.59"
    },
    {
      "rawName": "PAN DE LECHE 10 UDS",
      "product": "Pan de leche",
      "quantity": "10",
      "unit": "unit",
      "lineTotal": "1.55"
    },
    {
      "rawName": "YOGUR CARREFOUR 1KG",
      "product": "Yogur Carrefour",
      "quantity": "1",
      "unit": "kg",
      "lineTotal": "1.59"
    },
    {
      "rawName": "NAPOLITANA SUREME",
      "product": "Napolitana Sureme",
      "quantity": "3",
      "unit": "unit",
      "lineTotal": "2.55",
      "discount": "0.64"
    },
    {
      "rawName": "BOLSA 48X60CM",
      "product": "Bolsa de plástico",
      "quantity": "1",
      "unit": "unit",
      "lineTotal": "0.15"
    }
  ],
  "warnings": []
}
```

Cuadra al céntimo, y por eso sirve de prueba: este mismo JSON está en
`ILoveFinancesTests/TicketImportTests.swift`, así que si el prompt deja de casar
con la app, la suite lo caza.

```
1,09 + 1,29 + 2,59 + 1,55 + 1,59 + (2,55 − 0,64) + 0,15 = 10,17
```

## Qué hace la app al importarlo

1. Pone la fecha del ticket.
2. Busca una tienda tuya que se parezca a `shop`. Como tus tiendas son locales
   concretos ("Mercadona de casa") y el ticket dice sólo la cadena, muchas veces
   no acertará: entonces avisa y la eliges tú. **No crea tiendas sola**, para no
   llenarte la lista de duplicados de la misma cadena.
3. Añade todas las líneas al ticket en edición, sin borrar lo que ya hubiera.
4. Resta el `discount` de cada línea y la marca como oferta, para que un
   descuento puntual no mande en el comparador de precios.
5. Enlaza cada línea con el producto que ya exista con ese nombre; los que no
   existan se crean al guardar.
6. Muestra los `warnings` y, si el total declarado no cuadra con la suma de las
   líneas ya descontadas, te dice cuánto falta.

Nada se guarda hasta que le das a **Guardar**: la importación deja el formulario
listo para revisar contra el papel, que es justo donde se cazan los errores de
lectura de una foto.
