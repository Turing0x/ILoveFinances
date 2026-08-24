import Foundation

/// Los valores que se siembran y, sobre todo, lo que se espera recuperar.
/// La tabla de esperados va compilada dentro de la app a proposito: tras
/// borrar y reinstalar no queda nada local con que comparar.
enum ProbeFixtures {

    struct Expectation {
        let label: String
        let value: Decimal
        let scale: Int
        /// Por que este valor esta en la lista.
        let rationale: String

        /// Si el valor cabe en su escala sin perder nada.
        ///
        /// 0,615 y 0,005 tienen 3 decimales y la escala de centimos solo
        /// guarda 2: el entero escalado NO puede representarlos. Eso no es un
        /// fallo del entero ni de CloudKit, es el limite de la escala, y hay
        /// que distinguirlo de una perdida real o el informe miente.
        var isRepresentableAtScale: Bool {
            var multiplied = value * Decimal(scale)
            var rounded = Decimal()
            NSDecimalRound(&rounded, &multiplied, 0, .plain)
            return rounded == multiplied
        }
    }

    /// Escala 10^2 para dinero. Escala 10^6 para cantidades de activo:
    /// InvestmentTrade.quantity lleva hasta 6 decimales, asi que si el
    /// veredicto acaba siendo "enteros escalados" hacen falta DOS escalas.
    /// Mejor descubrirlo aqui que en la Fase 4.
    static let money = 100
    static let quantity = 1_000_000

    static let scalars: [Expectation] = [
        .init(label: "simple",   value: Decimal(string: "0.1")!,          scale: money,
              rationale: "0,1 no es representable en binario. El caso canonico."),
        .init(label: "siete",    value: Decimal(string: "0.07")!,         scale: money,
              rationale: "Tampoco. Aparece en cualquier IVA o retencion."),
        .init(label: "suma",     value: Decimal(string: "0.30")!,         scale: money,
              rationale: "El resultado de 0,1 + 0,2, que en Double no es 0,3."),
        .init(label: "precio",   value: Decimal(string: "19.99")!,        scale: money,
              rationale: "Un importe cotidiano cualquiera."),
        .init(label: "grande",   value: Decimal(string: "1234567.89")!,   scale: money,
              rationale: "Magnitud alta: el error absoluto de Double crece."),
        .init(label: "redondeo", value: Decimal(string: "0.615")!,        scale: money,
              rationale: "El clasico que redondea mal a 2 decimales en binario."),
        .init(label: "negativo", value: Decimal(string: "-45.00")!,       scale: money,
              rationale: "Signo."),
        .init(label: "techo",    value: Decimal(string: "99999999.99")!,  scale: money,
              rationale: "Limite superior realista de un patrimonio."),
        .init(label: "micro",    value: Decimal(string: "0.005")!,        scale: money,
              rationale: "Medio centimo: el umbral de redondeo."),
        .init(label: "cantidad", value: Decimal(string: "12.345678")!,    scale: quantity,
              rationale: "6 decimales. No es dinero: es una participacion de fondo."),
    ]

    // MARK: - Lote de suma

    static let batchLabel = "lote"
    static let batchCount = 200
    static let batchUnit = Decimal(string: "0.01")!

    /// 200 x 0,01 EUR = 2,00 EUR exactos. Es la prueba que traduce el problema
    /// tecnico a lenguaje de negocio: si tras el viaje por la nube la suma no
    /// da 2,00 clavado, Decimal no vale para esta app.
    static var batchExpectedTotal: Decimal { Decimal(batchCount) * batchUnit }

    static var totalRecordCount: Int { scalars.count + batchCount }
}
