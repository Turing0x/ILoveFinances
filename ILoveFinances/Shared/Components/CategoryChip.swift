import SwiftUI

struct CategoryChip: View {
    let category: TransactionCategory?

    var body: some View {
        Label(category?.name ?? "Sin categoría", systemImage: category?.symbolName ?? "questionmark")
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color(hex: category?.colorHex).opacity(0.18), in: Capsule())
            .foregroundStyle(Color(hex: category?.colorHex))
    }
}

struct FilterChip: View {
    let label: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(label).font(.caption)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill").font(.caption2)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.tint.opacity(0.15), in: Capsule())
    }
}

extension Color {
    /// Convierte "#RRGGBB" en color. Devuelve gris si el texto no vale, en vez
    /// de fallar: un color mal escrito no debe tirar una pantalla.
    init(hex: String?) {
        guard let hex else { self = .gray; return }
        var value = hex.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let number = UInt32(value, radix: 16) else { self = .gray; return }
        self = Color(
            red: Double((number >> 16) & 0xFF) / 255,
            green: Double((number >> 8) & 0xFF) / 255,
            blue: Double(number & 0xFF) / 255
        )
    }
}
