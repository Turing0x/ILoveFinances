import SwiftData
import SwiftUI

/// Pestana Bus (Fase 6).
///
/// La pantalla existe para una sola cosa y todo lo demas esta subordinado a
/// ella: **descontar un viaje en dos toques**, boton y confirmacion. El saldo,
/// los viajes restantes y el historial estan para dar contexto a ese toque, no
/// al reves.
///
/// Por eso el boton no esta en una barra ni detras de un `NavigationLink`: es
/// lo primero que se ve al abrir la pestana, y con una sola tarjeta dada de
/// alta no hay que elegir nada antes.
struct TransportView: View {
    @Environment(\.modelContext) private var context

    @Query(sort: \Account.name) private var accounts: [Account]

    @State private var selectedCardID: UUID?
    @State private var confirmingTrip = false
    @State private var lastTrip: Transaction?
    @State private var recharging: TransportRechargePrefill?
    @State private var creatingCard = false
    @State private var errorMessage: String?

    /// Cuanto dura el aviso de "Viaje registrado · Deshacer".
    private static let undoWindow: TimeInterval = 8

    var body: some View {
        NavigationStack {
            List {
                if let card = selectedCard {
                    cardSection(card)
                    tripSection(card)
                }
            }
            .navigationTitle("Bus")
            .toolbar {
                if let card = selectedCard {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Recargar", systemImage: "plus.circle") {
                            recharging = TransportRechargePrefill(card: card)
                        }
                    }
                }
            }
            .sheet(item: $recharging) { QuickAddView(recharge: $0) }
            .sheet(isPresented: $creatingCard) {
                AccountEditor(account: nil, initialType: .transport)
            }
            .overlay { emptyState }
            .alert("No se pudo registrar el viaje", isPresented: errorBinding) {
                Button("Entendido", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .onAppear(perform: selectDefaultCard)
            .onChange(of: cards.map(\.id)) { _, _ in selectDefaultCard() }
            // El aviso se apaga solo. Comparar una fecha limite contra `Date()`
            // no serviria: nada volveria a dibujar la vista al vencer el plazo.
            .task(id: lastTrip?.id) {
                guard lastTrip != nil else { return }
                try? await Task.sleep(for: .seconds(Self.undoWindow))
                if !Task.isCancelled { lastTrip = nil }
            }
        }
    }

    // MARK: - Datos

    private var cards: [Account] {
        accounts.filter { $0.type == .transport && !$0.isArchived }
    }

    private var selectedCard: Account? {
        cards.first { $0.id == selectedCardID } ?? cards.first
    }

    /// Con una sola tarjeta no hay nada que elegir; con varias se recuerda la
    /// ultima mientras la pestana siga viva.
    private func selectDefaultCard() {
        if selectedCardID == nil || !cards.contains(where: { $0.id == selectedCardID }) {
            selectedCardID = cards.first?.id
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    // MARK: - Tarjeta y boton

    @ViewBuilder
    private func cardSection(_ card: Account) -> some View {
        Section {
            if cards.count > 1 { cardPicker }

            VStack(spacing: 6) {
                Text(card.name)
                    .font(.headline)
                if let numero = card.transportCardNumber, !numero.isEmpty {
                    Text(numero)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                SignedAmountText(value: card.balance,
                                 font: .system(size: 44, weight: .semibold, design: .rounded))
                Text(remainingText(card))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)

            Button {
                confirmingTrip = true
            } label: {
                Label("Utilizada en viaje", systemImage: "bus.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .confirmationDialog(
                "¿Descontar \(Money.formatted(card.farePerTrip)) de \(card.name)?",
                isPresented: $confirmingTrip,
                titleVisibility: .visible
            ) {
                Button("Registrar viaje") { registerTrip(card) }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text(confirmationMessage(card))
            }

            if let trip = lastTrip {
                undoRow(trip)
            }
        }
    }

    private var cardPicker: some View {
        Picker("Tarjeta", selection: Binding(
            get: { selectedCard?.id ?? cards.first?.id },
            set: { selectedCardID = $0 }
        )) {
            ForEach(cards) { card in
                Text(card.name).tag(Optional(card.id))
            }
        }
        .pickerStyle(.menu)
    }

    private func remainingText(_ card: Account) -> String {
        guard let viajes = card.remainingTrips else { return "Sin precio por viaje configurado" }
        return viajes == 1 ? "Queda 1 viaje" : "Quedan \(viajes) viajes"
    }

    /// El aviso de saldo insuficiente va aqui y no en el servicio: registrar el
    /// viaje en negativo es legitimo (se apuntan los viajes antes que la
    /// recarga), lo que hace falta es que se vea antes de confirmar.
    private func confirmationMessage(_ card: Account) -> String {
        let despues = TransportService.balanceAfterTrip(card: card)
        if despues < 0 {
            return "Te quedarías en \(Money.formatted(despues)). Se registra igual: recarga cuando puedas."
        }
        return "Saldo tras el viaje: \(Money.formatted(despues))"
    }

    // MARK: - Deshacer

    private func undoRow(_ trip: Transaction) -> some View {
        HStack {
            Label("Viaje registrado", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.callout)
            Spacer()
            Button("Deshacer") { undo(trip) }
                .font(.callout)
        }
    }

    // MARK: - Historial

    @ViewBuilder
    private func tripSection(_ card: Account) -> some View {
        let period = DatePeriod.currentMonth
        let viajes = TransportService.trips(card: card, in: period.interval)

        Section {
            if viajes.isEmpty {
                Text("Sin viajes este mes")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viajes) { trip in
                    HStack {
                        Text(trip.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                        Spacer()
                        AmountText(transaction: trip, font: .callout)
                    }
                }
                .onDelete { offsets in
                    for index in offsets { undo(viajes[index]) }
                }
            }
        } header: {
            Text("Viajes de \(period.title)")
        } footer: {
            if !viajes.isEmpty {
                Text("\(viajes.count) viajes · \(Money.formatted(TransportService.spent(card: card, in: period.interval))) este mes")
            }
        }
    }

    // MARK: - Estado vacio

    @ViewBuilder
    private var emptyState: some View {
        if cards.isEmpty {
            ContentUnavailableView {
                Label("Sin tarjetas de transporte", systemImage: "bus")
            } description: {
                Text("Da de alta tu tarjeta del bus con su precio por viaje. Las recargas se apuntan como traspaso y cada viaje descuenta del saldo.")
            } actions: {
                Button("Nueva tarjeta") { creatingCard = true }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Acciones

    private func registerTrip(_ card: Account) {
        do {
            let trip = try TransportService.registerTrip(card: card, context: context)
            lastTrip = trip
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func undo(_ trip: Transaction) {
        do {
            try TransportService.undo(trip: trip, context: context)
            if trip.id == lastTrip?.id { lastTrip = nil }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
