import Testing
import SwiftUI
import AppKit
@testable import Speek

/// Renders the dashboard hero to a PNG in /tmp so the design can be reviewed
/// as an image without running the app.
@Suite(.serialized)
@MainActor
struct DashboardHeroSnapshotTests {

    @Test func renderChartVariants() throws {
        let defaults = UserDefaults.standard
        let key = "dashboardHeroChartVariant"
        let savedVariant = defaults.string(forKey: key)
        let rangeKey = "dashboardWordsRange"
        let savedRange = defaults.string(forKey: rangeKey)
        defer {
            if let savedVariant {
                defaults.set(savedVariant, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
            if let savedRange {
                defaults.set(savedRange, forKey: rangeKey)
            } else {
                defaults.removeObject(forKey: rangeKey)
            }
        }

        for variant in ["calendar", "bars", "growth"] {
            defaults.set(variant, forKey: key)
            defaults.set("total", forKey: rangeKey)
            try render(to: "/tmp/dashboard-hero-\(variant).png")
        }
    }

    /// Week + Month renders — the ranges whose x-axis carries weekday names.
    /// Flips the same UserDefaults key the card's @AppStorage reads, restoring
    /// the user's value afterwards.
    @Test func renderWeekAndMonth() throws {
        let defaults = UserDefaults.standard
        let savedRange = defaults.string(forKey: "dashboardWordsRange")
        defer {
            if let savedRange {
                defaults.set(savedRange, forKey: "dashboardWordsRange")
            } else {
                defaults.removeObject(forKey: "dashboardWordsRange")
            }
        }

        for range in ["week", "month"] {
            defaults.set(range, forKey: "dashboardWordsRange")
            try render(to: "/tmp/dashboard-hero-\(range).png")
        }
    }

    /// Range picker only shows Week/Month/All now — a legacy stored value from
    /// before (today/6M/year) must fall back to the "All" pill, not render blank.
    @Test func renderLegacyRangeFallsBackToTotal() throws {
        let defaults = UserDefaults.standard
        let savedRange = defaults.string(forKey: "dashboardWordsRange")
        defer {
            if let savedRange {
                defaults.set(savedRange, forKey: "dashboardWordsRange")
            } else {
                defaults.removeObject(forKey: "dashboardWordsRange")
            }
        }

        for legacyRange in ["today", "sixMonths", "year"] {
            defaults.set(legacyRange, forKey: "dashboardWordsRange")
            try render(to: "/tmp/dashboard-hero-legacy-\(legacyRange).png")
        }
    }

    private func render(to path: String) throws {
        let hosted = DashboardHeroSection(stats: .sample, insightsData: .sample, animate: false)
            .environmentObject(ThemeManager())
            .environment(\.colorScheme, .dark)
            .frame(width: 900)
            .padding(28)
            .background(Color(red: 0.075, green: 0.08, blue: 0.09))
        let renderer = ImageRenderer(content: hosted)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "snapshot", code: 1)
        }
        try png.write(to: URL(fileURLWithPath: path))
    }
}
