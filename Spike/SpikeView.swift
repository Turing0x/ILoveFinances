import SwiftData
import SwiftUI

struct SpikeView: View {
    let degradedReason: String?

    @Environment(\.modelContext) private var context
    @Query private var probes: [MoneyProbe]

    @State private var output = SpikeView.welcome
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let degradedReason {
                    degradedBanner(degradedReason)
                }
                actions
                Divider()
                ScrollView {
                    Text(output)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding()
                }
            }
            .navigationTitle("Fase 0")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Text("\(probes.count) local")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task {
            // Modo automatico: permite ejecutar la secuencia del Paso 4 desde
            // la linea de comandos en vez de a base de toques.
            guard let mode = AutoRunner.requested else { return }
            isWorking = true
            output = await AutoRunner.run(mode, context: context)
            isWorking = false
        }
    }

    private var actions: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button("Sembrar") { output = AutoRunner.seed(context: context) }
                Button("Inspeccionar", action: inspect)
                Button("Verificar") { output = AutoRunner.verify(context: context) }
            }
            .buttonStyle(.borderedProminent)

            HStack(spacing: 8) {
                Button("Secundarias") { output = SecondaryChecks.run() }
                    .buttonStyle(.bordered)
                Button("Borrar todo local", role: .destructive) {
                    output = AutoRunner.wipe(context: context)
                }
                .buttonStyle(.bordered)
            }
        }
        .controlSize(.small)
        .disabled(isWorking)
        .padding(.vertical, 10)
    }

    private func degradedBanner(_ reason: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SIN CLOUDKIT — los resultados no son validos")
                .font(.caption.bold())
            Text(reason)
                .font(.caption2)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.red.opacity(0.2))
    }

    private func inspect() {
        isWorking = true
        output = "Consultando CloudKit..."
        Task {
            output = await AutoRunner.inspect()
            isWorking = false
        }
    }

    private static let welcome = """
    Spike de la Fase 0 — precision de Decimal a traves de CloudKit

    1. Sembrar        \(ProbeFixtures.totalRecordCount) sondas en las cuatro codificaciones
    2. Inspeccionar   el tipo REAL de cada campo dentro del CKRecord
    3. Desinstalar la app y reinstalar
    4. Verificar      comparacion exacta de lo que vuelve de la nube

    Contenedor: \(SpikeApp.cloudKitContainerID)
    (desechable: el de la app llega virgen a la Fase 1)

    Tambien por linea de comandos:
      devicectl device process launch --console \\
        --device <id> dev.threedots.ilovefinances.spike --seed
    """
}
