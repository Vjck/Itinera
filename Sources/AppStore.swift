import Foundation
import CoreLocation

private struct RateResponse: Decodable {
    let date: String
    let rates: [String: Double]
}

@MainActor
final class AppStore: ObservableObject {
    @Published var trips: [Trip] = [] {
        didSet { save() }
    }

    private let fileURL: URL

    init() {
        fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("trips.json")
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([Trip].self, from: data) {
            trips = saved
        } else {
            trips = [SampleData.prague()]
            save()
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(trips) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func trip(_ id: UUID) -> Trip? {
        trips.first { $0.id == id }
    }

    func update(_ id: UUID, _ change: (inout Trip) -> Void) {
        guard let index = trips.firstIndex(where: { $0.id == id }) else { return }
        var copy = trips[index]
        change(&copy)
        trips[index] = copy
    }

    /// Downloads the latest reference rate (European Central Bank, via Frankfurter).
    @discardableResult
    func refreshRate(_ id: UUID) async -> Bool {
        guard let trip = trip(id), !trip.usesEuro,
              let url = URL(string: "https://api.frankfurter.dev/v1/latest?base=EUR&symbols=\(trip.currency)")
        else { return false }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(RateResponse.self, from: data)
            guard let value = response.rates[trip.currency], value > 0 else { return false }
            update(id) {
                $0.rate = value
                $0.rateDate = response.date
            }
            return true
        } catch {
            return false
        }
    }

    /// Finds the coordinates of the trip's city, used to centre the map and the searches.
    func locateCity(_ id: UUID) async {
        guard let trip = trip(id), !trip.city.isEmpty else { return }
        guard let marks = try? await CLGeocoder().geocodeAddressString(trip.city),
              let coordinate = marks.first?.location?.coordinate else { return }
        update(id) {
            $0.latitude = coordinate.latitude
            $0.longitude = coordinate.longitude
        }
    }
}

enum SampleData {
    static func prague() -> Trip {
        let cal = Calendar.current
        let start = cal.date(from: DateComponents(year: 2026, month: 12, day: 7)) ?? Date()
        let end = cal.date(from: DateComponents(year: 2026, month: 12, day: 11)) ?? Date()
        func spot(_ name: String, _ lat: Double, _ lon: Double, _ category: PlaceCategory = .attraction) -> Place {
            Place(name: name, category: category, latitude: lat, longitude: lon)
        }
        return Trip(
            name: "Praga",
            city: "Praga",
            start: start,
            end: end,
            currency: "CZK",
            rate: 24.5,
            latitude: 50.0875,
            longitude: 14.4213,
            places: [
                spot("Piazza della Città Vecchia", 50.0875, 14.4213),
                spot("Orologio astronomico", 50.0870, 14.4208),
                spot("Ponte Carlo", 50.0865, 14.4114),
                spot("Castello di Praga", 50.0911, 14.4016),
                spot("Cattedrale di San Vito", 50.0909, 14.4005),
                spot("Muro di John Lennon", 50.0862, 14.4069),
                spot("Quartiere ebraico (Josefov)", 50.0903, 14.4180),
                spot("Piazza San Venceslao", 50.0812, 14.4280),
                spot("Casa Danzante", 50.0755, 14.4141),
                spot("Collina di Petřín", 50.0833, 14.3950),
                spot("Vyšehrad", 50.0644, 14.4200),
                spot("Klementinum", 50.0866, 14.4163, .museum),
            ]
        )
    }
}
