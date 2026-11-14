import Foundation
import CoreLocation
import SwiftUI

enum PlaceCategory: String, Codable, CaseIterable, Identifiable {
    case attraction, museum, restaurant, lodging, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .attraction: return "Attrazioni"
        case .museum: return "Musei"
        case .restaurant: return "Ristoranti"
        case .lodging: return "Alloggio"
        case .other: return "Altro"
        }
    }

    var icon: String {
        switch self {
        case .attraction: return "star.fill"
        case .museum: return "building.columns.fill"
        case .restaurant: return "fork.knife"
        case .lodging: return "bed.double.fill"
        case .other: return "mappin"
        }
    }

    var color: Color {
        switch self {
        case .attraction: return .orange
        case .museum: return .purple
        case .restaurant: return .red
        case .lodging: return .blue
        case .other: return .gray
        }
    }
}

struct Place: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var category: PlaceCategory = .attraction
    var latitude: Double
    var longitude: Double
    var address: String = ""
    var priceLocal: Double?
    var note: String = ""
    var visited: Bool = false

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// One entry of the day's programme.
struct Step: Codable, Identifiable, Equatable {
    var id = UUID()
    var time: Date
    var title: String
    var placeID: UUID?
    var costLocal: Double?
    var note: String = ""
    var done: Bool = false
}

enum ExpenseCategory: String, Codable, CaseIterable, Identifiable {
    case food, transport, tickets, lodging, shopping, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .food: return "Cibo"
        case .transport: return "Trasporti"
        case .tickets: return "Ingressi"
        case .lodging: return "Alloggio"
        case .shopping: return "Acquisti"
        case .other: return "Altro"
        }
    }

    var icon: String {
        switch self {
        case .food: return "fork.knife"
        case .transport: return "tram.fill"
        case .tickets: return "ticket.fill"
        case .lodging: return "bed.double.fill"
        case .shopping: return "bag.fill"
        case .other: return "ellipsis.circle.fill"
        }
    }
}

struct Expense: Codable, Identifiable, Equatable {
    var id = UUID()
    var date: Date
    var title: String
    var category: ExpenseCategory
    var amountLocal: Double
    var amountEUR: Double
}

struct Trip: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var city: String
    var start: Date
    var end: Date
    /// ISO code of the local currency, e.g. "CZK".
    var currency: String = "EUR"
    var budgetEUR: Double = 0
    /// Units of local currency for one euro.
    var rate: Double = 1
    /// Day the rate refers to, as given by the rate service. Nil when never updated.
    var rateDate: String?
    var latitude: Double?
    var longitude: Double?
    var places: [Place] = []
    var steps: [Step] = []
    var expenses: [Expense] = []

    var usesEuro: Bool { currency == "EUR" }

    var center: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    func toEUR(_ local: Double) -> Double {
        usesEuro || rate <= 0 ? local : local / rate
    }

    func toLocal(_ eur: Double) -> Double {
        usesEuro ? eur : eur * rate
    }

    var days: [Date] {
        let cal = Calendar.current
        var out: [Date] = []
        var day = cal.startOfDay(for: start)
        let last = cal.startOfDay(for: end)
        while day <= last && out.count < 120 {
            out.append(day)
            day = cal.date(byAdding: .day, value: 1, to: day) ?? last.addingTimeInterval(86_400)
        }
        return out
    }

    var spentEUR: Double {
        expenses.reduce(0) { $0 + $1.amountEUR }
    }

    var spentLocal: Double {
        expenses.reduce(0) { $0 + $1.amountLocal }
    }

    func place(_ id: UUID?) -> Place? {
        guard let id else { return nil }
        return places.first { $0.id == id }
    }
}

let currencyCodes = [
    "EUR", "CZK", "USD", "GBP", "CHF", "JPY", "KRW", "PLN", "HUF", "RON",
    "SEK", "NOK", "DKK", "ISK", "TRY", "THB", "CNY", "HKD", "SGD", "AUD",
    "CAD", "NZD", "MXN", "BRL", "INR", "IDR", "MYR", "PHP", "ZAR", "ILS",
]

/// Formats an amount with its currency the Italian way, e.g. "250,00 CZK".
func money(_ value: Double, _ code: String) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.locale = Locale(identifier: "it_IT")
    formatter.currencyCode = code
    formatter.usesGroupingSeparator = true
    formatter.minimumGroupingDigits = 1
    return formatter.string(from: NSNumber(value: value)) ?? "\(value) \(code)"
}

/// Shows a local price and, underneath, the same price in euro.
struct DualPrice: View {
    let local: Double
    let trip: Trip
    /// Exact euro amount, when known; otherwise it is converted at the current rate.
    var euro: Double?
    var alignment: HorizontalAlignment = .trailing

    var body: some View {
        VStack(alignment: alignment, spacing: 1) {
            Text(money(local, trip.currency))
                .font(.subheadline.weight(.semibold))
            if !trip.usesEuro {
                Text(euro.map { money($0, "EUR") } ?? "≈ " + money(trip.toEUR(local), "EUR"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

enum Theme {
    static let accent = Color(red: 0.0, green: 0.44, blue: 0.50)
}
