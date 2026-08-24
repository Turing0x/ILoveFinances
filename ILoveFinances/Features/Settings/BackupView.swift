import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Copia de seguridad manual y restauracion.
///
/// CloudKit sincroniza pero NO respalda: un borrado se propaga a la nube y a
/// cualquier dispositivo futuro. Esto es lo unico que separa un despiste de
/// perder anos de datos.
struct BackupView: View {
    @Environment(\.modelContext) private var context

    @AppStorage("lastBackupAt") private var lastBackupTimestamp: Double = 0

    @State private var document: BackupDocument?
    @State private var showingExporter = false
    @State private var showingImporter = false
    @State private var showingRestoreConfirmation = false
    @State private var confirmationText = ""
    @State private var pendingFiles: [String: String]?
    @State private var message: String?

    private static let confirmationWord = "RESTAURAR"

    var body: some View {
        List {
            Section {
                Button("Exportar copia", systemImage: "square.and.arrow.up", action: export)
                lastBackupRow
            } footer: {
                Text("Una carpeta con un CSV por entidad: cuentas, categorías, miembros, movimientos, facturas, tiendas, productos y líneas de ticket. Se abren en Numbers y sirven para restaurar.")
            }

            Section {
                Button("Restaurar desde una copia", systemImage: "square.and.arrow.down") {
                    showingImporter = true
                }
                .foregroundStyle(.red)
            } footer: {
                Text("Restaurar BORRA todo lo que haya ahora y lo sustituye por el contenido de la copia. Con iCloud activo, ese borrado se propaga a la nube y a cualquier dispositivo futuro.")
            }

            if let message {
                Section { Text(message).font(.callout) }
            }
        }
        .navigationTitle("Copia de seguridad")
        .fileExporter(
            isPresented: $showingExporter,
            document: document,
            contentType: .folder,
            defaultFilename: defaultFilename
        ) { result in
            switch result {
            case .success:
                lastBackupTimestamp = Date().timeIntervalSince1970
                message = "Copia guardada."
            case .failure(let error):
                message = "No se pudo guardar: \(error.localizedDescription)"
            }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.folder]
        ) { result in
            handlePickedFolder(result)
        }
        .alert("Restaurar y borrar todo", isPresented: $showingRestoreConfirmation) {
            TextField(Self.confirmationWord, text: $confirmationText)
                .textInputAutocapitalization(.characters)
            Button("Cancelar", role: .cancel) { reset() }
            Button("Restaurar", role: .destructive, action: restore)
                .disabled(confirmationText != Self.confirmationWord)
        } message: {
            Text("Esto borra todos los movimientos, cuentas, categorías, miembros, facturas y compras actuales, también en iCloud. Escribe \(Self.confirmationWord) para confirmar.")
        }
    }

    // MARK: - Antigüedad de la copia

    @ViewBuilder
    private var lastBackupRow: some View {
        if lastBackupTimestamp == 0 {
            Label("Nunca has hecho una copia", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
        } else {
            let date = Date(timeIntervalSince1970: lastBackupTimestamp)
            let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
            LabeledContent("Última copia") {
                Text(days == 0 ? "hoy" : "hace \(days) d")
                    .foregroundStyle(days >= 30 ? .red : .secondary)
            }
        }
    }

    private var defaultFilename: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return "ILoveFinances-\(formatter.string(from: Date()))"
    }

    // MARK: - Acciones

    private func export() {
        do {
            document = BackupDocument(files: try BackupService.export(context: context))
            showingExporter = true
        } catch {
            message = "No se pudo preparar la copia: \(error.localizedDescription)"
        }
    }

    private func handlePickedFolder(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            message = "No se pudo abrir: \(error.localizedDescription)"
        case .success(let folder):
            // Carpeta elegida por el usuario: fuera del sandbox, hace falta
            // abrir el recurso con ambito de seguridad antes de leer.
            let accessed = folder.startAccessingSecurityScopedResource()
            defer { if accessed { folder.stopAccessingSecurityScopedResource() } }

            do {
                var files: [String: String] = [:]
                let contents = try FileManager.default.contentsOfDirectory(
                    at: folder, includingPropertiesForKeys: nil
                )
                for url in contents where url.pathExtension == "csv" {
                    files[url.lastPathComponent] = try String(contentsOf: url, encoding: .utf8)
                }
                pendingFiles = files
                confirmationText = ""
                showingRestoreConfirmation = true
            } catch {
                message = "No se pudo leer la carpeta: \(error.localizedDescription)"
            }
        }
    }

    private func restore() {
        guard let pendingFiles else { return }
        do {
            let summary = try BackupService.restoreReplacingAll(files: pendingFiles, context: context)
            message = """
            Restaurado: \(summary.accounts) cuentas, \(summary.categories) categorías, \
            \(summary.familyTags) miembros, \(summary.transactions) movimientos, \
            \(summary.recurringBills) facturas, \(summary.shops) tiendas, \
            \(summary.products) productos, \(summary.purchaseLines) líneas de ticket.
            """
            // La restauracion cambia las facturas por completo, asi que los
            // avisos pendientes ya no describen nada real.
            NotificationService.shared.reschedule(context: context)
        } catch {
            message = "No se restauró nada: \(error.localizedDescription)"
        }
        reset()
    }

    private func reset() {
        pendingFiles = nil
        confirmationText = ""
    }
}

/// Documento-carpeta: cada CSV es un fichero dentro. Se exporta una carpeta y
/// no un fichero unico porque un CSV con varias secciones deja de abrirse en
/// Numbers, y eso se perdia a cambio de nada.
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.folder] }

    let files: [String: String]

    init(files: [String: String]) { self.files = files }

    init(configuration: ReadConfiguration) throws {
        var loaded: [String: String] = [:]
        for (name, wrapper) in configuration.file.fileWrappers ?? [:] {
            if let data = wrapper.regularFileContents {
                loaded[name] = String(data: data, encoding: .utf8) ?? ""
            }
        }
        files = loaded
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let wrappers = files.mapValues { FileWrapper(regularFileWithContents: Data($0.utf8)) }
        return FileWrapper(directoryWithFileWrappers: wrappers)
    }
}
