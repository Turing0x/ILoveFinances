import Foundation
import Testing
@testable import ILoveFinances

/// El JSON lo escribe un modelo de lenguaje leyendo una foto, asi que llega
/// con variaciones: comas decimales, bloques de codigo markdown, campos
/// ausentes. Fallar por cualquiera de esas obligaria a editar a mano justo lo
/// que se acaba de pegar.
@Suite("Importacion de un ticket desde JSON")
struct TicketImportTests {

    private let completo = """
    {
      "shop": "MERCADONA",
      "date": "2026-08-24",
      "ticketTotal": "8.95",
      "lines": [
        {"rawName": "LECHE ENT 6X1L", "product": "Leche entera Hacendado",
         "quantity": "6", "unit": "l", "lineTotal": "5.40", "isOffer": false},
        {"rawName": "PAN BARRA", "product": "Pan de barra",
         "quantity": "1", "unit": "unit", "lineTotal": "1.20", "isOffer": true},
        {"rawName": "QUESO LONCHAS 200G", "product": "Queso en lonchas",
         "quantity": "200", "unit": "g", "lineTotal": "2.35", "isOffer": false}
      ]
    }
    """

    @Test("Un JSON completo se parsea entero y con importes exactos")
    func jsonCompleto() throws {
        let ticket = try TicketImportService.parse(completo)

        #expect(ticket.shopName == "MERCADONA")
        #expect(ticket.lines.count == 3)
        #expect(ticket.declaredTotal == Decimal(string: "8.95")!)
        #expect(ticket.linesTotal == Decimal(string: "8.95")!)
        #expect(ticket.totalMismatch == nil)

        let leche = ticket.lines[0]
        #expect(leche.rawName == "LECHE ENT 6X1L")
        #expect(leche.productName == "Leche entera Hacendado")
        #expect(leche.quantity == 6)
        #expect(leche.unit == .l)
        #expect(leche.lineTotal == Decimal(string: "5.40")!)
        #expect(!leche.isOffer)

        #expect(ticket.lines[1].isOffer)
        #expect(ticket.lines[2].unit == .g)
        #expect(ticket.lines[2].quantity == 200)

        // La fecha se interpreta en el calendario local, no en UTC.
        let componentes = Calendar.current.dateComponents([.year, .month, .day], from: try #require(ticket.date))
        #expect(componentes.year == 2026)
        #expect(componentes.month == 8)
        #expect(componentes.day == 24)
    }

    /// Un chat devuelve la respuesta envuelta en ```json. Pedirle al usuario
    /// que lo recorte a mano seria pedirle que edite lo que acaba de copiar.
    @Test("El JSON envuelto en un bloque de codigo tambien vale")
    func conBloqueDeCodigo() throws {
        let envuelto = "```json\n" + completo + "\n```"
        let ticket = try TicketImportService.parse(envuelto)
        #expect(ticket.lines.count == 3)
        #expect(ticket.shopName == "MERCADONA")
    }

    @Test("Coma decimal y punto de millar se entienden igual", arguments: [
        ("1.20", "1.2"),
        ("1,20", "1.2"),
        ("1.234,56", "1234.56"),
        ("0,615", "0.615"),
        ("5,40 €", "5.4"),
        (" 2.35 ", "2.35"),
    ])
    func numerosEnAmbosFormatos(entrada: String, esperado: String) throws {
        let valor = try #require(TicketImportService.decimal(from: entrada))
        #expect(valor == Decimal(string: esperado)!)
    }

    @Test("Sin cantidad se asume una unidad")
    func cantidadAusente() throws {
        let json = """
        {"lines": [{"rawName": "PAN", "lineTotal": "1.20"}]}
        """
        let ticket = try TicketImportService.parse(json)
        #expect(ticket.lines[0].quantity == 1)
        #expect(ticket.lines[0].unit == .unit)
        #expect(ticket.lines[0].productName == "PAN")   // sin product, se usa el literal
        #expect(ticket.shopName == nil)
        #expect(ticket.date == nil)
    }

    @Test("Una unidad desconocida no rompe la importacion, avisa")
    func unidadDesconocida() throws {
        let json = """
        {"lines": [{"rawName": "JAMON", "quantity": "2", "unit": "lonchas", "lineTotal": "3.00"}]}
        """
        let ticket = try TicketImportService.parse(json)
        #expect(ticket.lines[0].unit == .unit)
        #expect(ticket.warnings.count == 1)
        #expect(ticket.warnings[0].contains("lonchas"))
    }

    /// La interfaz no admite lineas de descuento (decision de la Fase 5). Se
    /// importa igual, pero avisando, para que el usuario decida en pantalla.
    @Test("Un importe negativo se importa con aviso")
    func importeNegativo() throws {
        let json = """
        {"lines": [
          {"rawName": "PAN", "lineTotal": "1.20"},
          {"rawName": "CUPON DTO", "lineTotal": "-2.00"}
        ]}
        """
        let ticket = try TicketImportService.parse(json)
        #expect(ticket.lines.count == 2)
        #expect(ticket.warnings.contains { $0.contains("CUPON DTO") })
    }

    /// El total del papel es solo comprobacion: lo que se guarda es la suma.
    /// Pero si no cuadran, hay que decirlo — es lo unico que caza una linea
    /// que el modelo leyo mal en la foto.
    @Test("Si el total del papel no cuadra con las lineas, se detecta")
    func descuadre() throws {
        let json = """
        {"ticketTotal": "10.00", "lines": [
          {"rawName": "PAN", "lineTotal": "1.20"},
          {"rawName": "LECHE", "lineTotal": "5.40"}
        ]}
        """
        let ticket = try TicketImportService.parse(json)
        #expect(ticket.linesTotal == Decimal(string: "6.60")!)
        #expect(ticket.totalMismatch == Decimal(string: "3.40")!)
    }

    @Test("Un texto que no es JSON da un error claro")
    func noEsJSON() {
        #expect(throws: TicketImportService.ImportError.self) {
            try TicketImportService.parse("hola que tal")
        }
    }

    @Test("Un JSON sin lineas se rechaza")
    func sinLineas() {
        #expect(throws: TicketImportService.ImportError.self) {
            try TicketImportService.parse("""
            {"shop": "MERCADONA", "lines": []}
            """)
        }
    }

    @Test("Un importe ilegible se rechaza nombrando la linea")
    func importeIlegible() {
        #expect(throws: TicketImportService.ImportError.self) {
            try TicketImportService.parse("""
            {"lines": [{"rawName": "PAN", "lineTotal": "uno veinte"}]}
            """)
        }
    }

    /// El ejemplo de `docs/prompt-ticket-json.md` tiene que parsear tal cual.
    /// Si alguien toca el prompt y deja de casar con el modelo, esto lo caza:
    /// el documento y el parser son un contrato, y viven en ficheros distintos.
    ///
    /// Es un ticket REAL de Carrefour Express, con su descuento en 2a unidad y
    /// su bolsa. Cuadra al centimo, asi que sirve de prueba de verdad y no de
    /// ejemplo inventado.
    @Test("El ejemplo del prompt documentado se importa y cuadra al centimo")
    func ejemploDelPrompt() throws {
        let json = """
        {
          "shop": "CARREFOUR EXPRESS",
          "date": "2026-08-24",
          "ticketTotal": "10.17",
          "lines": [
            {"rawName": "TOALLITA BEBE X 80", "product": "Toallitas de bebé",
             "quantity": "80", "unit": "unit", "lineTotal": "1.09"},
            {"rawName": "WAFER CHOCOLATE", "product": "Wafer de chocolate",
             "quantity": "1", "unit": "unit", "lineTotal": "1.29"},
            {"rawName": "BIFRUTAS TROPICAL 6U", "product": "Bifrutas tropical",
             "quantity": "6", "unit": "unit", "lineTotal": "2.59"},
            {"rawName": "PAN DE LECHE 10 UDS", "product": "Pan de leche",
             "quantity": "10", "unit": "unit", "lineTotal": "1.55"},
            {"rawName": "YOGUR CARREFOUR 1KG", "product": "Yogur Carrefour",
             "quantity": "1", "unit": "kg", "lineTotal": "1.59"},
            {"rawName": "NAPOLITANA SUREME", "product": "Napolitana Sureme",
             "quantity": "3", "unit": "unit", "lineTotal": "2.55", "discount": "0.64"},
            {"rawName": "BOLSA 48X60CM", "product": "Bolsa de plástico",
             "quantity": "1", "unit": "unit", "lineTotal": "0.15"}
          ],
          "warnings": []
        }
        """
        let ticket = try TicketImportService.parse(json)

        #expect(ticket.lines.count == 7)
        #expect(ticket.warnings.isEmpty)

        // La napolitana: 2,55 impresos menos 0,64 de descuento.
        let napolitana = ticket.lines[5]
        #expect(napolitana.lineTotal == Decimal(string: "1.91")!)
        #expect(napolitana.discount == Decimal(string: "0.64")!)
        #expect(napolitana.isOffer)   // marcada sola por llevar descuento

        // Ninguna otra linea se marca como oferta.
        #expect(ticket.lines.filter(\.isOffer).count == 1)

        // El total del papel: 10,17. Sin descuadre.
        #expect(ticket.linesTotal == Decimal(string: "10.17")!)
        #expect(ticket.declaredTotal == Decimal(string: "10.17")!)
        #expect(ticket.totalMismatch == nil)
        #expect(ticket.discountTotal == Decimal(string: "0.64")!)
    }

    // MARK: - Descuentos por linea

    @Test("Un descuento se resta del importe y marca la linea como oferta")
    func descuentoDeLinea() throws {
        let json = """
        {"lines": [
          {"rawName": "NAPOLITANA SUREME", "quantity": "3", "unit": "unit",
           "lineTotal": "2.55", "discount": "0.64"}
        ]}
        """
        let ticket = try TicketImportService.parse(json)

        #expect(ticket.lines[0].lineTotal == Decimal(string: "1.91")!)
        #expect(ticket.lines[0].discount == Decimal(string: "0.64")!)
        #expect(ticket.lines[0].isOffer)
        #expect(ticket.warnings.isEmpty)
    }

    /// El prompt pide el descuento en positivo, pero un modelo de lenguaje
    /// puede devolverlo con el signo del papel. Las dos formas valen.
    @Test("El descuento vale igual en positivo que en negativo", arguments: ["0.64", "-0.64"])
    func descuentoConCualquierSigno(valor: String) throws {
        let json = """
        {"lines": [{"rawName": "PAN", "lineTotal": "2.55", "discount": "\(valor)"}]}
        """
        let ticket = try TicketImportService.parse(json)
        #expect(ticket.lines[0].lineTotal == Decimal(string: "1.91")!)
        #expect(ticket.lines[0].discount == Decimal(string: "0.64")!)
    }

    /// Sin descuento nada cambia respecto a como funcionaba antes.
    @Test("Una linea sin descuento se comporta igual que siempre")
    func sinDescuentoNoHayRegresion() throws {
        let json = """
        {"lines": [{"rawName": "PAN", "quantity": "1", "lineTotal": "1.20"}]}
        """
        let ticket = try TicketImportService.parse(json)
        #expect(ticket.lines[0].lineTotal == Decimal(string: "1.20")!)
        #expect(ticket.lines[0].discount == .zero)
        #expect(!ticket.lines[0].isOffer)
        #expect(ticket.discountTotal == .zero)
    }

    @Test("El total de descuentos suma los de todas las lineas")
    func totalDeDescuentos() throws {
        let json = """
        {"lines": [
          {"rawName": "PAN", "lineTotal": "1.20", "discount": "0.30"},
          {"rawName": "LECHE", "lineTotal": "5.40", "discount": "0.34"},
          {"rawName": "QUESO", "lineTotal": "2.35"}
        ]}
        """
        let ticket = try TicketImportService.parse(json)
        #expect(ticket.discountTotal == Decimal(string: "0.64")!)
        #expect(ticket.linesTotal == Decimal(string: "8.31")!)
        #expect(ticket.lines.filter(\.isOffer).count == 2)
    }

    @Test("Un descuento mayor que el importe se importa con aviso")
    func descuentoExcesivo() throws {
        let json = """
        {"lines": [{"rawName": "PAN BARRA", "lineTotal": "1.20", "discount": "2.00"}]}
        """
        let ticket = try TicketImportService.parse(json)
        #expect(ticket.lines[0].lineTotal == Decimal(string: "-0.80")!)
        #expect(ticket.warnings.count == 1)
        #expect(ticket.warnings[0].contains("PAN BARRA"))
    }

    @Test("Un descuento ilegible se rechaza nombrando la linea")
    func descuentoIlegible() {
        #expect(throws: TicketImportService.ImportError.self) {
            try TicketImportService.parse("""
            {"lines": [{"rawName": "PAN", "lineTotal": "1.20", "discount": "medio euro"}]}
            """)
        }
    }

}
