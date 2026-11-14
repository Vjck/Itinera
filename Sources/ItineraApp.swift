import SwiftUI

@main
struct ItineraApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            TripListView()
                .environmentObject(store)
                .tint(Theme.accent)
        }
    }
}

struct TripListView: View {
    @EnvironmentObject var store: AppStore
    @State private var creating = false
    @State private var editing: Trip?
    @AppStorage(MapsApp.key) private var mapsApp = MapsApp.apple.rawValue

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.trips) { trip in
                    NavigationLink {
                        TripView(tripID: trip.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(trip.name).font(.headline)
                            Text(dateRange(trip))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .contextMenu {
                        Button("Modifica", systemImage: "pencil") { editing = trip }
                    }
                }
                .onDelete { store.trips.remove(atOffsets: $0) }
            }
            .overlay {
                if store.trips.isEmpty {
                    ContentUnavailableView("Nessun viaggio", systemImage: "airplane",
                                           description: Text("Tocca + per crearne uno."))
                }
            }
            .navigationTitle("Viaggi")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Apri le indicazioni con", selection: $mapsApp) {
                            ForEach(MapsApp.allCases) { Text($0.title).tag($0.rawValue) }
                        }
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { creating = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $creating) { TripEditor(original: nil) }
            .sheet(item: $editing) { TripEditor(original: $0) }
        }
    }

    private func dateRange(_ trip: Trip) -> String {
        let style = Date.FormatStyle().day().month(.abbreviated).year()
        return "\(trip.city) · \(trip.start.formatted(style)) – \(trip.end.formatted(style))"
    }
}

struct TripEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let original: Trip?

    @State private var name = ""
    @State private var city = ""
    @State private var start = Date()
    @State private var end = Date().addingTimeInterval(3 * 86_400)
    @State private var currency = "EUR"
    @State private var budget: Double?

    var body: some View {
        NavigationStack {
            Form {
                Section("Viaggio") {
                    TextField("Nome", text: $name)
                    TextField("Città", text: $city)
                    DatePicker("Dal", selection: $start, displayedComponents: .date)
                    DatePicker("Al", selection: $end, in: start..., displayedComponents: .date)
                }
                Section("Soldi") {
                    Picker("Valuta locale", selection: $currency) {
                        ForEach(currencyCodes, id: \.self) { Text($0).tag($0) }
                    }
                    TextField("Budget in euro", value: $budget, format: .number)
                        .keyboardType(.decimalPad)
                }
            }
            .navigationTitle(original == nil ? "Nuovo viaggio" : "Modifica viaggio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva", action: save)
                        .disabled(city.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                guard let original else { return }
                name = original.name
                city = original.city
                start = original.start
                end = original.end
                currency = original.currency
                budget = original.budgetEUR > 0 ? original.budgetEUR : nil
            }
        }
    }

    private func save() {
        let cleanCity = city.trimmingCharacters(in: .whitespaces)
        let cleanName = name.trimmingCharacters(in: .whitespaces)
        let id: UUID
        var cityChanged = true
        var currencyChanged = true
        if let original {
            id = original.id
            cityChanged = original.city != cleanCity
            currencyChanged = original.currency != currency
            store.update(id) {
                $0.name = cleanName.isEmpty ? cleanCity : cleanName
                $0.city = cleanCity
                $0.start = start
                $0.end = max(start, end)
                $0.budgetEUR = budget ?? 0
                if currencyChanged {
                    $0.currency = currency
                    $0.rate = 1
                    $0.rateDate = nil
                }
            }
        } else {
            let trip = Trip(name: cleanName.isEmpty ? cleanCity : cleanName, city: cleanCity,
                            start: start, end: max(start, end), currency: currency,
                            budgetEUR: budget ?? 0)
            id = trip.id
            store.trips.append(trip)
        }
        let store = store
        Task {
            if cityChanged { await store.locateCity(id) }
            if currencyChanged { await store.refreshRate(id) }
        }
        dismiss()
    }
}

struct TripView: View {
    @EnvironmentObject var store: AppStore
    let tripID: UUID
    @State private var pane: Pane = .itinerary

    enum Pane: String, CaseIterable, Identifiable {
        case itinerary = "Giorni", map = "Mappa", places = "Luoghi", expenses = "Spese", exchange = "Cambio"
        var id: String { rawValue }
    }

    var body: some View {
        if let trip = store.trip(tripID) {
            VStack(spacing: 0) {
                Picker("Sezione", selection: $pane) {
                    ForEach(Pane.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                switch pane {
                case .itinerary: ItineraryView(trip: trip)
                case .map: TripMapView(trip: trip)
                case .places: PlacesView(trip: trip)
                case .expenses: ExpensesView(trip: trip)
                case .exchange: ExchangeView(trip: trip)
                }
            }
            .navigationTitle(trip.name)
            .navigationBarTitleDisplayMode(.inline)
            .task { await store.refreshRate(tripID) }
        } else {
            ContentUnavailableView("Viaggio non trovato", systemImage: "airplane")
        }
    }
}
