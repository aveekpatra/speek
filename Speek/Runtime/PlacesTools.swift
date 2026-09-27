import Foundation
import CoreLocation
import MapKit

/// Where the user is (CoreLocation), the weather there or anywhere (Open-Meteo: free, no key),
/// and places nearby (MapKit local search). Built only on what macOS ships plus one keyless API,
/// so there is nothing to maintain. Results also come back as cards shown in the notch.
@MainActor
enum PlacesTools {
    static let catalog: [RuntimeTool] = [
        RuntimeTool(id: "location.current", title: "Current location",
                    summary: "The user's current location from this Mac (Location Services): place name and coordinates. Use it for anything \"near me\", \"here\", or local.",
                    schema: ActionRuntime.schema([:], required: []), requiresReview: false),
        RuntimeTool(id: "weather.forecast", title: "Weather forecast",
                    summary: "Current weather, the next hours, and five days, for the user's location or a named place. The user sees an interactive weather card; answer in one or two sentences without repeating every number.",
                    schema: ActionRuntime.schema(["place": ["type": "string", "description": "A city or address; leave out for the user's location."]], required: []), requiresReview: false),
        RuntimeTool(id: "places.search", title: "Find places",
                    summary: "Search Apple Maps for places near the user or near a named place (restaurants, cafes, pharmacies, an address). The user sees a map card with the results.",
                    schema: ActionRuntime.schema(["query": ["type": "string"], "near": ["type": "string", "description": "A place to search around; leave out for the user's location."]], required: ["query"]), requiresReview: false)
    ]

    static func isTool(_ id: String) -> Bool { catalog.contains { $0.id == id } }

    /// Text for the model, and a card for the user.
    static func execute(_ call: RuntimeCall) async throws -> (String, ResultCard?) {
        switch call.tool {
        case "location.current":
            let (location, name) = try await here()
            let map = MapCardData(title: name, center: location.coordinate, places: [], showsUser: true)
            return ("The user is in \(name) (latitude \(String(format: "%.4f", location.coordinate.latitude)), longitude \(String(format: "%.4f", location.coordinate.longitude)), accurate to about \(Int(location.horizontalAccuracy)) m).", .map(map))
        case "weather.forecast":
            let (coordinate, name) = try await place(call.arguments["place"]?.string)
            let report = try await WeatherService.forecast(at: coordinate, name: name)
            return (report.summary, .weather(report))
        case "places.search":
            guard let query = call.arguments["query"]?.string, !query.isEmpty else { throw ActionClientError.requestFailed("Say what to look for.") }
            let (coordinate, name) = try await place(call.arguments["near"]?.string)
            let places = try await search(query, around: coordinate)
            guard !places.isEmpty else { return ("Apple Maps found no \(query) near \(name).", nil) }
            let lines = places.enumerated().map { index, item in
                "\(index + 1). \(item.name)" + (item.address.isEmpty ? "" : ", \(item.address)") + (item.distance.map { ", \(Self.distance($0)) away" } ?? "")
            }
            let map = MapCardData(title: query.capitalized + " near " + name, center: coordinate, places: places, showsUser: call.arguments["near"] == nil)
            return ("Apple Maps results for \(query) near \(name) (the user sees them on a map card):\n" + lines.joined(separator: "\n"), .map(map))
        default:
            throw ActionClientError.requestFailed("Unknown places tool.")
        }
    }

    // MARK: Location

    private static func here() async throws -> (CLLocation, String) {
        let location = try await LocationProvider.shared.current()
        return (location, await name(of: location) ?? "your area")
    }

    /// A named place, or the user's location when none is given.
    private static func place(_ query: String?) async throws -> (CLLocationCoordinate2D, String) {
        guard let query, !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            let (location, name) = try await here()
            return (location.coordinate, name)
        }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.address, .pointOfInterest]
        guard let item = try await MKLocalSearch(request: request).start().mapItems.first else {
            throw ActionClientError.requestFailed("Apple Maps could not find \(query).")
        }
        return (item.location.coordinate, item.name ?? query)
    }

    private static func name(of location: CLLocation) async -> String? {
        guard let request = MKReverseGeocodingRequest(location: location),
              let item = try? await request.mapItems.first else { return nil }
        return item.addressRepresentations?.cityWithContext ?? item.name
    }

    private static func search(_ query: String, around center: CLLocationCoordinate2D) async throws -> [MapPlace] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(center: center, latitudinalMeters: 5000, longitudinalMeters: 5000)
        request.resultTypes = [.pointOfInterest, .address]
        let origin = CLLocation(latitude: center.latitude, longitude: center.longitude)
        let items = try await MKLocalSearch(request: request).start().mapItems
        return items.prefix(8).map { item in
            MapPlace(name: item.name ?? query, address: item.address?.shortAddress ?? "",
                     coordinate: item.location.coordinate, distance: item.location.distance(from: origin), item: item)
        }.sorted { ($0.distance ?? 0) < ($1.distance ?? 0) }
    }

    static func distance(_ meters: CLLocationDistance) -> String {
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .naturalScale
        formatter.numberFormatter.maximumFractionDigits = meters < 1000 ? 0 : 1
        return formatter.string(from: Measurement(value: meters, unit: UnitLength.meters))
    }
}

/// One-shot location with the system's permission prompt the first time.
@MainActor
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    static let shared = LocationProvider()
    private let manager = CLLocationManager()
    private var waiting: [CheckedContinuation<CLLocation, Error>] = []

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func current() async throws -> CLLocation {
        switch manager.authorizationStatus {
        case .denied, .restricted:
            throw ActionClientError.requestFailed("Location is off for Speek. Turn it on in System Settings > Privacy & Security > Location Services.")
        default: break
        }
        if let recent = manager.location, -recent.timestamp.timeIntervalSinceNow < 300, recent.horizontalAccuracy < 2000 { return recent }
        return try await withThrowingTaskGroup(of: CLLocation.self) { group in
            group.addTask { @MainActor in
                try await withCheckedThrowingContinuation { continuation in
                    self.waiting.append(continuation)
                    if self.manager.authorizationStatus == .notDetermined { self.manager.requestWhenInUseAuthorization() }
                    else { self.manager.requestLocation() }
                }
            }
            group.addTask {
                try await Task.sleep(for: .seconds(15))
                throw ActionClientError.requestFailed("Your location did not arrive in time. Check Location Services and try again.")
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }

    private func finish(_ result: Result<CLLocation, Error>) {
        let pending = waiting
        waiting = []
        pending.forEach { $0.resume(with: result) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch self.manager.authorizationStatus {
            case .authorized, .authorizedAlways: if !self.waiting.isEmpty { self.manager.requestLocation() }
            case .denied, .restricted: self.finish(.failure(ActionClientError.requestFailed("Location is off for Speek. Turn it on in System Settings > Privacy & Security > Location Services.")))
            default: break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in self.finish(.success(location)) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(.failure(ActionClientError.requestFailed("Your location could not be found: " + error.localizedDescription))) }
    }
}

// MARK: Weather

/// Open-Meteo forecasts (CC BY 4.0, attribution shown on the card).
enum WeatherService {
    static func forecast(at coordinate: CLLocationCoordinate2D, name: String) async throws -> WeatherReport {
        let fahrenheit = Locale.current.measurementSystem == .us
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(coordinate.latitude)), URLQueryItem(name: "longitude", value: String(coordinate.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,weather_code,wind_speed_10m,is_day,relative_humidity_2m"),
            URLQueryItem(name: "hourly", value: "temperature_2m,weather_code,precipitation_probability,is_day"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset"),
            URLQueryItem(name: "timezone", value: "auto"), URLQueryItem(name: "forecast_days", value: "5"),
            URLQueryItem(name: "temperature_unit", value: fahrenheit ? "fahrenheit" : "celsius"),
            URLQueryItem(name: "wind_speed_unit", value: fahrenheit ? "mph" : "kmh")
        ]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ActionClientError.requestFailed("The weather service did not answer. Try again in a moment.")
        }
        return try WeatherReport(json: json, place: name, fahrenheit: fahrenheit)
    }
}

struct WeatherReport: Equatable {
    struct Hour: Equatable, Identifiable { let time: Date; let temperature: Double; let code: Int; let rain: Int; let day: Bool; var id: Date { time } }
    struct Day: Equatable, Identifiable { let date: Date; let high: Double; let low: Double; let code: Int; let rain: Int; let sunrise: Date?; let sunset: Date?; var id: Date { date } }

    let place: String
    let temperature: Double
    let feelsLike: Double
    let code: Int
    let isDay: Bool
    let wind: Double
    let humidity: Int
    let hours: [Hour]
    let days: [Day]
    let fahrenheit: Bool
    let timeZone: TimeZone

    init(json: [String: Any], place: String, fahrenheit: Bool) throws {
        guard let current = json["current"] as? [String: Any], let hourly = json["hourly"] as? [String: Any], let daily = json["daily"] as? [String: Any] else {
            throw ActionClientError.requestFailed("The weather service returned an unexpected answer.")
        }
        self.place = place
        self.fahrenheit = fahrenheit
        timeZone = (json["timezone"] as? String).flatMap(TimeZone.init(identifier:)) ?? .current
        func number(_ value: Any?) -> Double { (value as? NSNumber)?.doubleValue ?? 0 }
        temperature = number(current["temperature_2m"]); feelsLike = number(current["apparent_temperature"])
        code = Int(number(current["weather_code"])); isDay = number(current["is_day"]) == 1
        wind = number(current["wind_speed_10m"]); humidity = Int(number(current["relative_humidity_2m"]))
        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX"); local.timeZone = timeZone
        func date(_ text: Any?, _ format: String) -> Date? { local.dateFormat = format; return (text as? String).flatMap(local.date(from:)) }
        let times = hourly["time"] as? [Any] ?? []
        hours = times.indices.compactMap { index in
            guard let time = date(times[index], "yyyy-MM-dd'T'HH:mm") else { return nil }
            func value(_ key: String) -> Double { number((hourly[key] as? [Any]).flatMap { index < $0.count ? $0[index] : nil }) }
            return Hour(time: time, temperature: value("temperature_2m"), code: Int(value("weather_code")), rain: Int(value("precipitation_probability")), day: value("is_day") == 1)
        }
        let dates = daily["time"] as? [Any] ?? []
        days = dates.indices.compactMap { index in
            guard let day = date(dates[index], "yyyy-MM-dd") else { return nil }
            func value(_ key: String) -> Any? { (daily[key] as? [Any]).flatMap { index < $0.count ? $0[index] : nil } }
            return Day(date: day, high: number(value("temperature_2m_max")), low: number(value("temperature_2m_min")), code: Int(number(value("weather_code"))),
                       rain: Int(number(value("precipitation_probability_max"))), sunrise: date(value("sunrise"), "yyyy-MM-dd'T'HH:mm"), sunset: date(value("sunset"), "yyyy-MM-dd'T'HH:mm"))
        }
    }

    var unit: String { fahrenheit ? "F" : "C" }

    /// For the model: the facts, so it can answer briefly.
    var summary: String {
        var text = "Weather in \(place): now \(Int(temperature.rounded())) \(unit), feels like \(Int(feelsLike.rounded())), \(Self.describe(code).lowercased()), wind \(Int(wind.rounded())) \(fahrenheit ? "mph" : "km/h")."
        for (index, day) in days.prefix(3).enumerated() {
            let label = index == 0 ? "Today" : index == 1 ? "Tomorrow" : day.date.formatted(.dateTime.weekday(.wide))
            text += " \(label): \(Self.describe(day.code).lowercased()), high \(Int(day.high.rounded())), low \(Int(day.low.rounded())), rain chance \(day.rain)%."
        }
        return text + " The user sees a weather card with the full forecast."
    }

    static func describe(_ code: Int) -> String {
        switch code {
        case 0: return "Clear"
        case 1: return "Mostly clear"
        case 2: return "Partly cloudy"
        case 3: return "Cloudy"
        case 45, 48: return "Fog"
        case 51, 53, 55, 56, 57: return "Drizzle"
        case 61, 63, 66: return "Rain"
        case 65, 67: return "Heavy rain"
        case 71, 73, 75, 77: return "Snow"
        case 80, 81, 82: return "Showers"
        case 85, 86: return "Snow showers"
        case 95, 96, 99: return "Thunderstorms"
        default: return "Unknown"
        }
    }

    static func symbol(_ code: Int, day: Bool = true) -> String {
        switch code {
        case 0: return day ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: return day ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55, 56, 57: return "cloud.drizzle.fill"
        case 61, 63, 66, 80, 81: return "cloud.rain.fill"
        case 65, 67, 82: return "cloud.heavyrain.fill"
        case 71, 73, 75, 77, 85, 86: return "cloud.snow.fill"
        case 95, 96, 99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }
}

// MARK: Maps

struct MapPlace: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let address: String
    let coordinate: CLLocationCoordinate2D
    let distance: CLLocationDistance?
    let item: MKMapItem?
    static func == (a: MapPlace, b: MapPlace) -> Bool { a.id == b.id }
}

struct MapCardData: Equatable {
    let title: String
    let center: CLLocationCoordinate2D
    let places: [MapPlace]
    let showsUser: Bool
    static func == (a: MapCardData, b: MapCardData) -> Bool { a.title == b.title && a.places == b.places }
}

/// A card shown with an answer.
enum ResultCard: Identifiable, Equatable {
    case weather(WeatherReport)
    case map(MapCardData)
    var id: String {
        switch self {
        case .weather(let report): return "weather-" + report.place
        case .map(let map): return "map-" + map.title
        }
    }
}
