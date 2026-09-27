import SwiftUI
import MapKit

/// Cards shown with an answer in the notch.
struct ResultCardView: View {
    let card: ResultCard
    var body: some View {
        switch card {
        case .weather(let report): WeatherCardView(report: report)
        case .map(let map): MapCardView(map: map)
        }
    }

    static func height(_ card: ResultCard) -> Int {
        switch card {
        case .weather: return 214
        case .map(let map): return 196 + min(3, map.places.count) * 32
        }
    }
}

private let degree = "\u{00B0}"

/// Now, the day's range, and an hour-by-hour strip; pick a day to see its hours.
struct WeatherCardView: View {
    let report: WeatherReport
    @State private var selectedDay = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                // Today shows the weather right now; other days their overall weather.
                Image(systemName: selectedDay == 0 ? WeatherReport.symbol(report.code, day: report.isDay) : WeatherReport.symbol(selected.code))
                    .symbolRenderingMode(.multicolor).font(.system(size: 34)).frame(width: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedDay == 0 ? "\(Int(report.temperature.rounded()))\(degree)" : "\(Int(selected.high.rounded()))\(degree)")
                        .font(.system(size: 30, weight: .semibold)).monospacedDigit()
                    Text(WeatherReport.describe(selectedDay == 0 ? report.code : selected.code)).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 3) {
                    Label(report.place, systemImage: "location.fill").font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Text("H \(Int(selected.high.rounded()))\(degree)  L \(Int(selected.low.rounded()))\(degree)").font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit()
                    if selectedDay == 0 {
                        Text("Feels \(Int(report.feelsLike.rounded()))\(degree), wind \(Int(report.wind.rounded())) \(report.fahrenheit ? "mph" : "km/h")")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    } else if selected.rain > 0 {
                        Text("\(selected.rain)% chance of rain").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            }
            // Days: tap one to see its hours.
            HStack(spacing: 4) {
                ForEach(Array(report.days.prefix(5).enumerated()), id: \.offset) { index, day in
                    Button { withAnimation(.easeOut(duration: 0.15)) { selectedDay = index } } label: {
                        VStack(spacing: 3) {
                            Text(index == 0 ? "Today" : day.date.formatted(.dateTime.weekday(.abbreviated))).font(.system(size: 11, weight: .medium))
                            Image(systemName: WeatherReport.symbol(day.code)).symbolRenderingMode(.multicolor).font(.system(size: 14)).frame(height: 16)
                            Text("\(Int(day.high.rounded()))\(degree)").font(.system(size: 11)).monospacedDigit()
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                        .background(selectedDay == index ? Color.white.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
            ScrollView(.horizontal) {
                HStack(spacing: 14) {
                    ForEach(hours) { hour in
                        VStack(spacing: 4) {
                            Text(hour.time.formatted(.dateTime.hour())).font(.system(size: 10)).foregroundStyle(.secondary)
                            Image(systemName: WeatherReport.symbol(hour.code, day: hour.day)).symbolRenderingMode(.multicolor).font(.system(size: 13)).frame(height: 15)
                            Text("\(Int(hour.temperature.rounded()))\(degree)").font(.system(size: 11)).monospacedDigit()
                            Text(hour.rain >= 20 ? "\(hour.rain)%" : " ").font(.system(size: 9)).foregroundStyle(Color.cyan)
                        }
                    }
                }.padding(.horizontal, 2)
            }.scrollIndicators(.hidden)
            Link("Weather data by Open-Meteo.com", destination: URL(string: "https://open-meteo.com")!)
                .font(.system(size: 9)).foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .environment(\.timeZone, report.timeZone)
    }

    private var selected: WeatherReport.Day {
        report.days.indices.contains(selectedDay) ? report.days[selectedDay]
            : WeatherReport.Day(date: Date(), high: report.temperature, low: report.temperature, code: report.code, rain: 0, sunrise: nil, sunset: nil)
    }

    /// Today: from now on. Other days: that whole day, every two hours.
    private var hours: [WeatherReport.Hour] {
        var calendar = Calendar.current
        calendar.timeZone = report.timeZone
        guard let day = report.days.indices.contains(selectedDay) ? report.days[selectedDay].date : nil else { return [] }
        let inDay = report.hours.filter { calendar.isDate($0.time, inSameDayAs: day) }
        if selectedDay == 0 { return inDay.filter { $0.time > Date().addingTimeInterval(-3600) } }
        return inDay.enumerated().filter { $0.offset % 2 == 0 }.map(\.element)
    }
}

/// Apple's own map with the results; tap a row to open it in Maps.
struct MapCardView: View {
    let map: MapCardData
    @State private var position: MapCameraPosition = .automatic
    @State private var selected: MapPlace.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(map.title).font(.system(size: 12, weight: .semibold)).lineLimit(1).padding(.horizontal, 4)
            Map(position: $position, selection: $selected) {
                if map.showsUser { UserAnnotation() }
                if map.places.isEmpty {
                    Marker(map.title, systemImage: "location.fill", coordinate: map.center)
                }
                ForEach(map.places) { place in
                    Marker(place.name, coordinate: place.coordinate).tag(place.id)
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .frame(height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            ForEach(map.places.prefix(3)) { place in
                Button { selected = place.id; open(place) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "mappin.circle.fill").foregroundStyle(.red).font(.system(size: 14))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(place.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                            if !place.address.isEmpty { Text(place.address).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1) }
                        }
                        Spacer(minLength: 4)
                        if let distance = place.distance { Text(PlacesTools.distance(distance)).font(.system(size: 11)).foregroundStyle(.secondary) }
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).help("Open in Maps")
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onAppear {
            position = map.places.isEmpty ? .region(MKCoordinateRegion(center: map.center, latitudinalMeters: 2500, longitudinalMeters: 2500)) : .automatic
        }
    }

    private func open(_ place: MapPlace) {
        (place.item ?? MKMapItem(location: CLLocation(latitude: place.coordinate.latitude, longitude: place.coordinate.longitude), address: nil)).openInMaps()
    }
}
