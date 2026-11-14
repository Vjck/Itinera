import SwiftUI
import MapKit

enum LocationAccess {
    static let manager = CLLocationManager()
}

struct TripMapView: View {
    let trip: Trip
    @State private var position: MapCameraPosition = .automatic
    @State private var selected: UUID?
    @State private var filter: PlaceCategory?

    private var shown: [Place] {
        trip.places.filter { filter == nil || $0.category == filter }
    }

    var body: some View {
        Map(position: $position, selection: $selected) {
            UserAnnotation()
            ForEach(shown) { place in
                Marker(place.name, systemImage: place.category.icon, coordinate: place.coordinate)
                    .tint(place.visited ? Color.gray : place.category.color)
                    .tag(place.id)
            }
        }
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapScaleView()
        }
        .safeAreaInset(edge: .top) { filterBar }
        .safeAreaInset(edge: .bottom) {
            if let place = trip.place(selected) { card(place) }
        }
        .onAppear {
            LocationAccess.manager.requestWhenInUseAuthorization()
            if trip.places.isEmpty, let center = trip.center {
                position = .region(MKCoordinateRegion(center: center, latitudinalMeters: 8000, longitudinalMeters: 8000))
            }
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("Tutti", nil)
                ForEach(PlaceCategory.allCases) { chip($0.title, $0) }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
    }

    private func chip(_ title: String, _ category: PlaceCategory?) -> some View {
        Button { filter = category } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .foregroundStyle(filter == category ? Color.white : Color.primary)
                .background(filter == category ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.regularMaterial),
                            in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func card(_ place: Place) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.name).font(.headline)
                    Text(place.address.isEmpty ? place.category.title : place.address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let price = place.priceLocal, price > 0 {
                    DualPrice(local: price, trip: trip)
                }
            }
            if !place.note.isEmpty {
                Text(place.note).font(.caption)
            }
            HStack {
                Button("A piedi", systemImage: "figure.walk") {
                    openDirections(from: nil, to: place, transit: false)
                }
                Button("Mezzi", systemImage: "tram.fill") {
                    openDirections(from: nil, to: place, transit: true)
                }
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
}

struct PlacesView: View {
    @EnvironmentObject var store: AppStore
    let trip: Trip
    @State private var searching = false
    @State private var editing: Place?

    var body: some View {
        List {
            if trip.places.isEmpty {
                ContentUnavailableView("Nessun luogo", systemImage: "mappin.and.ellipse",
                                       description: Text("Tocca + per cercare attrazioni, musei e ristoranti."))
                    .listRowSeparator(.hidden)
            }
            ForEach(PlaceCategory.allCases) { category in
                let items = trip.places.filter { $0.category == category }
                if !items.isEmpty {
                    Section(category.title) {
                        ForEach(items) { place in
                            row(place)
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { searching = true } label: { Image(systemName: "plus") }
                    .accessibilityIdentifier("add")
                    .accessibilityLabel("Aggiungi")
            }
        }
        .sheet(isPresented: $searching) { PlaceSearchView(trip: trip) }
        .sheet(item: $editing) { PlaceEditor(trip: trip, original: $0) }
    }

    private func row(_ place: Place) -> some View {
        HStack(spacing: 12) {
            Image(systemName: place.visited ? "checkmark.circle.fill" : place.category.icon)
                .foregroundStyle(place.visited ? Color.secondary : place.category.color)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name).strikethrough(place.visited)
                if !place.address.isEmpty {
                    Text(place.address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let price = place.priceLocal, price > 0 {
                DualPrice(local: price, trip: trip)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { editing = place }
        .swipeActions {
            Button("Elimina", role: .destructive) {
                store.update(trip.id) { trip in
                    trip.places.removeAll { $0.id == place.id }
                    for i in trip.steps.indices where trip.steps[i].placeID == place.id {
                        trip.steps[i].placeID = nil
                    }
                }
            }
        }
    }
}

struct PlaceEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let trip: Trip
    @State private var draft: Place

    init(trip: Trip, original: Place) {
        self.trip = trip
        _draft = State(initialValue: original)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nome", text: $draft.name)
                    Picker("Categoria", selection: $draft.category) {
                        ForEach(PlaceCategory.allCases) { Text($0.title).tag($0) }
                    }
                    Toggle("Già visitato", isOn: $draft.visited)
                }
                Section("Prezzo in \(trip.currency)") {
                    TextField("Ingresso o spesa media", value: $draft.priceLocal, format: .number)
                        .keyboardType(.decimalPad)
                    if !trip.usesEuro, let price = draft.priceLocal, price > 0 {
                        Text("≈ " + money(trip.toEUR(price), "EUR")).foregroundStyle(.secondary)
                    }
                }
                Section("Note") {
                    TextField("Orari, prenotazione, cosa ordinare…", text: $draft.note, axis: .vertical)
                }
                Section {
                    Button("Indicazioni con i mezzi", systemImage: "tram.fill") {
                        openDirections(from: nil, to: draft, transit: true)
                    }
                }
            }
            .navigationTitle("Luogo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        let place = draft
                        store.update(trip.id) { trip in
                            if let i = trip.places.firstIndex(where: { $0.id == place.id }) { trip.places[i] = place }
                        }
                        dismiss()
                    }
                }
            }
        }
    }
}

struct PlaceSearchView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let trip: Trip
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var loading = false
    @State private var searched = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        quick("Attrazioni", "attrazioni turistiche")
                        quick("Musei", "musei")
                        quick("Ristoranti", "ristoranti")
                    }
                    .listRowSeparator(.hidden)
                }
                if loading {
                    ProgressView().frame(maxWidth: .infinity)
                } else if searched && results.isEmpty {
                    Text("Nessun risultato.").foregroundStyle(.secondary)
                }
                ForEach(results, id: \.self) { item in
                    resultRow(item)
                }
            }
            .listStyle(.plain)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Cerca a \(trip.city)")
            .onSubmit(of: .search) { run(query) }
            .navigationTitle("Aggiungi luogo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fine") { dismiss() } }
            }
        }
    }

    private func quick(_ title: String, _ text: String) -> some View {
        Button(title) {
            query = title
            run(text)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func resultRow(_ item: MKMapItem) -> some View {
        let name = item.name ?? "Senza nome"
        let coordinate = item.placemark.coordinate
        let added = (store.trip(trip.id)?.places ?? []).contains {
            $0.name == name && abs($0.latitude - coordinate.latitude) < 0.0005
                && abs($0.longitude - coordinate.longitude) < 0.0005
        }
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                Text(item.placemark.title ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if added {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
            } else {
                Button("Aggiungi") {
                    let place = Place(name: name, category: category(of: item),
                                      latitude: coordinate.latitude, longitude: coordinate.longitude,
                                      address: item.placemark.title ?? "")
                    store.update(trip.id) { $0.places.append(place) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private func category(of item: MKMapItem) -> PlaceCategory {
        guard let kind = item.pointOfInterestCategory else { return .other }
        switch kind {
        case .museum: return .museum
        case .restaurant, .cafe, .bakery, .brewery, .winery, .foodMarket: return .restaurant
        case .hotel: return .lodging
        default: return .attraction
        }
    }

    private func run(_ text: String) {
        let cleaned = text.trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty else { return }
        let request = MKLocalSearch.Request()
        if let center = trip.center {
            request.naturalLanguageQuery = cleaned
            request.region = MKCoordinateRegion(center: center, latitudinalMeters: 15_000, longitudinalMeters: 15_000)
        } else {
            request.naturalLanguageQuery = "\(cleaned) \(trip.city)"
        }
        request.resultTypes = .pointOfInterest
        loading = true
        Task {
            let response = try? await MKLocalSearch(request: request).start()
            results = response?.mapItems ?? []
            loading = false
            searched = true
        }
    }
}
