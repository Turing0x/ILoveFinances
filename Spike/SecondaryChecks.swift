import Foundation
import SwiftData

/// Paso 6: dos preguntas pequenas cuya respuesta condiciona pantallas de la
/// Fase 1. Se ejecutan sobre un contenedor EN MEMORIA: no dependen de CloudKit
/// ni de la cuenta de iCloud, asi que valen igual en simulador.
enum SecondaryChecks {

    static func run() -> String {
        var lines: [String] = []
        lines.append("COMPROBACIONES SECUNDARIAS (Paso 6)")
        lines.append("")

        // 1. #Index — si esto se esta ejecutando, ya compilo.
        lines.append("1. #Index<MoneyProbe>([\\.createdAt], [\\.label])")
        lines.append("   COMPILA. Es la razon declarada para subir el deployment")
        lines.append("   target; la premisa se sostiene.")
        lines.append("")

        // 2. Decimal dentro de #Predicate.
        lines.append("2. Decimal dentro de #Predicate")
        lines.append(indent(decimalPredicateResult()))
        return lines.joined(separator: "\n")
    }

    /// El filtro "rango de importe" de la pantalla de Movimientos (PLAN.md
    /// seccion 6) depende de esto. Que el predicado COMPILE no basta: SwiftData
    /// traduce a Core Data en tiempo de ejecucion y ahi es donde falla si no
    /// soporta el tipo. Por eso se ejecuta un fetch de verdad.
    private static func decimalPredicateResult() -> String {
        do {
            let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
            let container = try ModelContainer(for: MoneyProbe.self, configurations: configuration)
            let context = ModelContext(container)

            for expectation in ProbeFixtures.scalars {
                context.insert(
                    MoneyProbe(label: expectation.label, value: expectation.value, scale: expectation.scale)
                )
            }
            try context.save()

            let floor = Decimal(string: "1.00")!
            let ceiling = Decimal(string: "100000.00")!
            let descriptor = FetchDescriptor<MoneyProbe>(
                predicate: #Predicate { $0.asDecimal >= floor && $0.asDecimal <= ceiling }
            )
            let found = try context.fetch(descriptor).map(\.label).sorted()

            // Los esperados se derivan de los propios fixtures, no se escriben
            // a mano: enumerarlos de memoria ya fallo una vez (se olvido
            // "cantidad", 12,345678, que si cae dentro del rango).
            let expected = ProbeFixtures.scalars
                .filter { $0.value >= floor && $0.value <= ceiling }
                .map(\.label)
                .sorted()
            guard found == expected else {
                return """
                FUNCIONA PERO DEVUELVE MAL.
                esperado \(expected), obtenido \(found).
                Filtrar por importe con Decimal no es de fiar: usar entero.
                """
            }
            return """
            FUNCIONA. Filtro [1,00 .. 100000,00] devuelve \(found).
            El filtro de rango de importe puede ir sobre Decimal.
            """
        } catch {
            return """
            FALLA EN EJECUCION: \(error)
            Argumento adicional a favor de los enteros escalados, independiente
            del resultado de la comprobacion B.
            """
        }
    }

    private static func indent(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { "   \($0)" }
            .joined(separator: "\n")
    }
}
