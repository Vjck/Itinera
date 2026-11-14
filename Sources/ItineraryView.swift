import SwiftUI
import MapKit

/// App used for directions, chosen in the trip list menu.
enum MapsApp: String, CaseIterable, Identifiable {
    case apple, google

    static let key = "mapsApp"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .apple: return "Mappe di Apple"
        case .google: return "Google Maps"
        }
    }

    static var current: MapsApp {
        MapsApp(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .apple
    }
}

/// Opens the chosen maps app with directions to `to`, starting from `from` or from the current position.
func openDirections(from: Place?, to: Place, transit: Bool) {
    switch MapsApp.current {
    case .apple:
        var items: [MKMapItem] = []
        if let from {
            let source = MKMapItem(placemark: MKPlacemark(coordinate: from.coordinate))
            source.name = from.name
            items.append(source)
        }
        let destination = MKMapItem(placemark: MKPlacemark(coordinate: to.coordinate))
        destination.name = to.name
        items.append(destination)
        let mode = transit ? MKLaunchOptionsDirectionsModeTransit : MKLaunchOptionsDirectionsModeWalking
        MKMapItem.openMaps(with: items, launchOptions: [MKLaunchOptionsDirectionsModeKey: mode])
    case .google:
        // Universal link: opens the Google Maps app when installed, otherwise the browser.
        var components = URLComponents(string: "https://www.google.com/maps/dir/")
        var query = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "destination", value: "\(to.latitude),\(to.longitude)"),
            URLQueryItem(name: "travelmode", value: transit ? "transit" : "walking"),
        ]
        if let from {
            query.append(URLQueryItem(name: "origin", value: "\(from.latitude),\(from.longitude)"))
        }
        components?.queryItems = query
        if let url = components?.url {
            UIApplication.shared.open(url)
        }
    }
}

struct ItineraryView: View {
    @EnvironmentObject var store: AppStore
    let trip: Trip
    @State private var day: Date?
    @State private var editing: Step?

    private var selectedDay: Date {
        day ?? trip.days.first ?? Calendar.current.startOfDay(for: trip.start)
    }

    private var steps: [Step] {
        trip.steps
            .filter { Calendar.current.isDate($0.time, inSameDayAs: selectedDay) }
            .sorted { $0.time < $1.time }
    }

    private var nextStepID: UUID? {
        guard Calendar.current.isDateInToday(selectedDay) else { return nil }
        return steps.first { !$0.done }?.id
    }

    var body: some View {
        VStack(spacing: 0) {
            dayPicker
            List {
                if steps.isEmpty {
                    ContentUnavailableView("Giornata libera", systemImage: "calendar",
                                           description: Text("Tocca + per aggiungere una tappa."))
                        .listRowSeparator(.hidden)
                }
                ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                    if index > 0, let from = trip.place(steps[index - 1].placeID),
                       let to = trip.place(step.placeID), from.id != to.id {
                        legRow(from: from, to: to)
                    }
                    stepRow(step)
                }
                if !steps.isEmpty {
                    let total = steps.compactMap(\.costLocal).reduce(0, +)
                    if total > 0 {
                        HStack {
                            Text("Totale previsto del giorno").foregroundStyle(.secondary)
                            Spacer()
                            DualPrice(local: total, trip: trip)
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { editing = Step(time: defaultTime(), title: "") } label: { Image(systemName: "plus") }
            }
        }
        .sheet(item: $editing) { StepEditor(trip: trip, original: $0) }
        .onAppear {
            guard day == nil else { return }
            let today = Calendar.current.startOfDay(for: Date())
            day = trip.days.contains(today) ? today : trip.days.first
        }
    }

    private var dayPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(trip.days.enumerated()), id: \.element) { index, date in
                    let selected = Calendar.current.isDate(date, inSameDayAs: selectedDay)
                    Button { day = date } label: {
                        VStack(spacing: 2) {
                            Text("Giorno \(index + 1)").font(.caption.weight(.semibold))
                            Text(date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                                .font(.caption2)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .foregroundStyle(selected ? Color.white : Color.primary)
                        .background(selected ? Theme.accent : Color(.secondarySystemBackground),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }

    private func stepRow(_ step: Step) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                store.update(trip.id) { trip in
                    if let i = trip.steps.firstIndex(where: { $0.id == step.id }) { trip.steps[i].done.toggle() }
                }
            } label: {
                Image(systemName: step.done ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(step.done ? Theme.accent : Color.secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(step.time.formatted(date: .omitted, time: .shortened))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if step.id == nextStepID {
                        Text("Prossima")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .foregroundStyle(.white)
                            .background(Theme.accent, in: Capsule())
                    }
                }
                Text(step.title.isEmpty ? (trip.place(step.placeID)?.name ?? "Tappa") : step.title)
                    .font(.headline)
                    .strikethrough(step.done)
                if let place = trip.place(step.placeID), !step.title.isEmpty {
                    Label(place.name, systemImage: place.category.icon)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !step.note.isEmpty {
                    Text(step.note).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if let cost = step.costLocal, cost > 0 {
                DualPrice(local: cost, trip: trip)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { editing = step }
        .swipeActions {
            Button("Elimina", role: .destructive) {
                store.update(trip.id) { $0.steps.removeAll { $0.id == step.id } }
            }
        }
    }

    private func legRow(from: Place, to: Place) -> some View {
        let metres = CLLocation(latitude: from.latitude, longitude: from.longitude)
            .distance(from: CLLocation(latitude: to.latitude, longitude: to.longitude))
        let distance = metres < 1000
            ? "\(Int(metres.rounded())) m"
            : String(format: "%.1f km", locale: Locale(identifier: "it_IT"), metres / 1000)
        return HStack(spacing: 10) {
            Image(systemName: "arrow.down").foregroundStyle(.secondary)
            Text("\(distance) in linea d'aria").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("A piedi") { openDirections(from: from, to: to, transit: false) }
                .buttonStyle(.bordered)
                .controlSize(.small)
            Button("Mezzi") { openDirections(from: from, to: to, transit: true) }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .listRowSeparator(.hidden)
    }

    private func defaultTime() -> Date {
        if let last = steps.last { return last.time.addingTimeInterval(3600) }
        return Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: selectedDay) ?? selectedDay
    }
}

struct StepEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let trip: Trip
    let original: Step
    @State private var draft: Step

    init(trip: Trip, original: Step) {
        self.trip = trip
        self.original = original
        _draft = State(initialValue: original)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Cosa fai", text: $draft.title)
                    DatePicker("Quando", selection: $draft.time)
                    Picker("Luogo", selection: $draft.placeID) {
                        Text("Nessuno").tag(UUID?.none)
                        ForEach(trip.places) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                }
                Section("Costo previsto in \(trip.currency)") {
                    TextField("Costo", value: $draft.costLocal, format: .number)
                        .keyboardType(.decimalPad)
                    if !trip.usesEuro, let cost = draft.costLocal, cost > 0 {
                        Text("≈ " + money(trip.toEUR(cost), "EUR")).foregroundStyle(.secondary)
                    }
                }
                Section("Note") {
                    TextField("Note", text: $draft.note, axis: .vertical)
                }
            }
            .navigationTitle("Tappa")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        let step = draft
                        store.update(trip.id) { trip in
                            if let i = trip.steps.firstIndex(where: { $0.id == step.id }) {
                                trip.steps[i] = step
                            } else {
                                trip.steps.append(step)
                            }
                        }
                        dismiss()
                    }
                    .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty && draft.placeID == nil)
                }
            }
        }
    }
}
