import Foundation
import SwiftData

/// Comprobacion B del Paso 4: compara lo que vuelve de la nube contra la tabla
/// de esperados, con `==` exacto de Decimal.
///
/// Nunca con tolerancia. Una comparacion con margen enmascararia justo el fallo
/// que se esta buscando.
enum ProbeVerifier {

    /// Tri-estado a proposito. Marcar como FALLO algo que la escala nunca
    /// pudo representar convierte el informe en ruido.
    enum Outcome {
        case ok
        case fail
        case outOfScale

        var text: String {
            switch self {
            case .ok:         return "OK"
            case .fail:       return "FALLO"
            case .outOfScale: return "n/a"
            }
        }

        var isProblem: Bool { self == .fail }
    }

    struct Row {
        let label: String
        let expected: Decimal
        let decimal: Outcome
        let scaledInt: Outcome
        let string: Outcome
        let double: Outcome
        let decimalGot: Decimal
        let doubleGot: Decimal
    }

    struct Result {
        let rows: [Row]
        let missing: [String]
        let batchCount: Int
        let batchExpected: Decimal
        let batchFromDecimal: Decimal
        let batchFromScaledInt: Decimal
        let batchFromDouble: Decimal
    }

    private static func outcome(_ passed: Bool) -> Outcome { passed ? .ok : .fail }

    static func verify(context: ModelContext) throws -> Result {
        let probes = try context.fetch(FetchDescriptor<MoneyProbe>())
        let byLabel = Dictionary(grouping: probes.filter { !$0.isBatchItem }, by: \.label)

        var rows: [Row] = []
        var missing: [String] = []

        for expectation in ProbeFixtures.scalars {
            guard let probe = byLabel[expectation.label]?.first else {
                missing.append(expectation.label)
                continue
            }
            let scaled: Outcome = expectation.isRepresentableAtScale
                ? outcome(probe.decodedFromScaledInt == expectation.value)
                : .outOfScale

            rows.append(
                Row(
                    label: expectation.label,
                    expected: expectation.value,
                    decimal: outcome(probe.asDecimal == expectation.value),
                    scaledInt: scaled,
                    string: outcome(probe.decodedFromString == expectation.value),
                    double: outcome(probe.decodedFromDouble == expectation.value),
                    decimalGot: probe.asDecimal,
                    doubleGot: probe.decodedFromDouble
                )
            )
        }

        let batch = probes.filter(\.isBatchItem)
        return Result(
            rows: rows,
            missing: missing,
            batchCount: batch.count,
            batchExpected: ProbeFixtures.batchExpectedTotal,
            batchFromDecimal: batch.reduce(Decimal.zero) { $0 + $1.asDecimal },
            batchFromScaledInt: batch.reduce(Decimal.zero) { $0 + $1.decodedFromScaledInt },
            batchFromDouble: batch.reduce(Decimal.zero) { $0 + $1.decodedFromDouble }
        )
    }

    // MARK: - Informe

    static func report(_ result: Result) -> String {
        guard !result.rows.isEmpty else {
            return """
            No hay sondas en el store local.

            Si vienes de reinstalar, el mirroring todavia no ha importado.
            Deja la app en primer plano y reintenta en un minuto.
            """
        }

        var lines: [String] = []
        lines.append("ESCALARES — comparacion exacta contra los esperados")
        lines.append("")
        lines.append("  \("label".p(10))\("esperado".p(16))\("Decimal".p(9))\("Escalado".p(10))\("String".p(9))Double")
        for row in result.rows {
            lines.append(
                "  " + row.label.p(10)
                + Self.text(row.expected).p(16)
                + row.decimal.text.p(9)
                + row.scaledInt.text.p(10)
                + row.string.text.p(9)
                + row.double.text
            )
        }

        // Solo se detallan las filas que fallan: ver el valor real es lo que
        // convierte un "FALLO" en evidencia utilizable en el informe.
        if result.rows.contains(where: { $0.scaledInt == .outOfScale }) {
            let labels = result.rows.filter { $0.scaledInt == .outOfScale }.map(\.label)
            lines.append("")
            lines.append("  n/a en Escalado: \(labels.joined(separator: ", ")) tienen 3 decimales")
            lines.append("     y la escala de centimos (10^2) solo guarda 2. Limite de la")
            lines.append("     escala, no perdida por el viaje.")
        }

        let broken = result.rows.filter { $0.decimal.isProblem }
        if !broken.isEmpty {
            lines.append("")
            lines.append("DETALLE DE LOS FALLOS DE Decimal")
            for row in broken {
                lines.append("  \(row.label): esperado \(text(row.expected)) / recibido \(text(row.decimalGot))")
            }
        }

        if !result.missing.isEmpty {
            lines.append("")
            lines.append("NO HAN VUELTO: \(result.missing.joined(separator: ", "))")
        }

        lines.append("")
        lines.append("LOTE — \(result.batchCount) de \(ProbeFixtures.batchCount) filas de 0,01 EUR")
        lines.append("  esperado           \(text(result.batchExpected))")
        lines.append("  suma de Decimal    \(text(result.batchFromDecimal))  \(mark(result.batchFromDecimal == result.batchExpected))")
        lines.append("  suma de escalados  \(text(result.batchFromScaledInt))  \(mark(result.batchFromScaledInt == result.batchExpected))")
        lines.append("  suma de Double     \(text(result.batchFromDouble))  \(mark(result.batchFromDouble == result.batchExpected))")

        lines.append("")
        lines.append(verdict(result))
        return lines.joined(separator: "\n")
    }

    private static func verdict(_ result: Result) -> String {
        let complete = result.missing.isEmpty && result.batchCount == ProbeFixtures.batchCount
        guard complete else {
            return "SIN VEREDICTO: faltan registros por importar. Espera y reintenta."
        }

        let decimalClean = result.rows.allSatisfy { !$0.decimal.isProblem }
            && result.batchFromDecimal == result.batchExpected
        let scaledClean = result.rows.allSatisfy { !$0.scaledInt.isProblem }
            && result.batchFromScaledInt == result.batchExpected

        guard controlIsMeaningful(result) else {
            return """
            SIN VEREDICTO: el control Double tampoco falla en ninguna fila.
            Si ni siquiera Double pierde, el test no esta midiendo la conversion
            y un "todo OK" no significaria nada. Revisar antes de concluir.
            """
        }

        if decimalClean {
            return """
            VEREDICTO: Decimal sobrevive intacto al viaje por CloudKit.
            Se guarda como Double en el CKRecord, pero la conversion de vuelta
            recupera el decimal original en todos los casos probados.
            Se mantiene Decimal en PLAN.md seccion 3 y se elimina el plan B.
            """
        }
        if scaledClean {
            return """
            VEREDICTO: Decimal pierde precision. Los enteros escalados aguantan.
            Adoptar enteros escalados en los nueve campos monetarios de la
            seccion 3, con escala 10^2 para dinero y 10^6 para cantidades.
            Recordar: el importe pasa a ser calculado y deja de servir en un
            #Predicate; los filtros iran sobre el entero.
            """
        }
        return """
        VEREDICTO: ni Decimal ni los enteros escalados salen limpios.
        Resultado inesperado: revisar el volcado del CKRecord antes de decidir.
        """
    }

    /// Sin redondear, por el mismo motivo que en el inspector.
    private static func text(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).description(withLocale: Locale(identifier: "en_US_POSIX"))
    }

    private static func mark(_ ok: Bool) -> String { ok ? "OK" : "FALLO" }

    /// El control. Si Double saliera limpio en todo, el test no estaria
    /// midiendo nada y un "todo OK" no significaria nada.
    static func controlIsMeaningful(_ result: Result) -> Bool {
        result.rows.contains { $0.double.isProblem }
    }
}

private extension String {
    func p(_ width: Int) -> String {
        count >= width ? self + " " : self + String(repeating: " ", count: width - count)
    }
}
