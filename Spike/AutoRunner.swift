import Foundation
import SwiftData

/// Modo automatico por argumentos de lanzamiento.
///
/// El spike se puede pulsar a mano, pero la secuencia del Paso 4 —sembrar,
/// esperar, inspeccionar, desinstalar, reinstalar, verificar— es larga y se
/// presta a errores de orden. Con esto se ejecuta desde la linea de comandos
/// con `devicectl ... --console` y el informe sale por stdout.
enum AutoRunner {

    enum Mode: String {
        case seed = "--seed"
        case inspect = "--inspect"
        case verify = "--verify"
        case secondary = "--secondary"
        case wipe = "--wipe"
    }

    static var requested: Mode? {
        CommandLine.arguments.compactMap(Mode.init(rawValue:)).first
    }

    /// Devuelve el informe y ademas lo imprime, para que sea visible tanto en
    /// pantalla como en la consola de devicectl.
    static func run(_ mode: Mode, context: ModelContext) async -> String {
        let report: String
        switch mode {
        case .seed:      report = seed(context: context)
        case .inspect:   report = await inspect()
        case .verify:    report = verify(context: context)
        case .secondary: report = SecondaryChecks.run()
        case .wipe:      report = wipe(context: context)
        }

        print("")
        print("===== SPIKE \(mode.rawValue) =====")
        print(report)
        print("===== FIN \(mode.rawValue) =====")
        return report
    }

    // MARK: - Acciones compartidas con la UI

    static func seed(context: ModelContext) -> String {
        let existing = (try? context.fetchCount(FetchDescriptor<MoneyProbe>())) ?? 0
        guard existing == 0 else {
            return "Ya hay \(existing) sondas locales. Borra antes de volver a sembrar."
        }

        for expectation in ProbeFixtures.scalars {
            context.insert(
                MoneyProbe(label: expectation.label, value: expectation.value, scale: expectation.scale)
            )
        }
        for index in 0..<ProbeFixtures.batchCount {
            context.insert(
                MoneyProbe(
                    label: "\(ProbeFixtures.batchLabel)-\(index)",
                    value: ProbeFixtures.batchUnit,
                    scale: ProbeFixtures.money,
                    isBatchItem: true
                )
            )
        }

        do {
            try context.save()
            return """
            Sembradas \(ProbeFixtures.totalRecordCount) sondas en el store local.

            Ahora el mirroring tiene que subirlas. Inspecciona cada pocos minutos
            hasta ver las \(ProbeFixtures.totalRecordCount) en CloudKit.

            Leer los valores en este mismo arranque no probaria nada: saldrian
            del store local, que nunca paso por la nube.
            """
        } catch {
            return "Fallo al guardar: \(error)"
        }
    }

    static func inspect() async -> String {
        do {
            return CloudKitInspector.report(try await CloudKitInspector.dump())
        } catch {
            return "Fallo al inspeccionar CloudKit:\n\(error)"
        }
    }

    static func verify(context: ModelContext) -> String {
        do {
            return ProbeVerifier.report(try ProbeVerifier.verify(context: context))
        } catch {
            return "Fallo al verificar: \(error)"
        }
    }

    static func wipe(context: ModelContext) -> String {
        do {
            try context.delete(model: MoneyProbe.self)
            try context.save()
            return "Store local vacio. Los datos siguen en CloudKit."
        } catch {
            return "Fallo al borrar: \(error)"
        }
    }
}
