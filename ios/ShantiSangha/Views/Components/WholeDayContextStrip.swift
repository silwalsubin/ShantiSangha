import SwiftUI

/// Thin, muted row under the home greeting showing any "whole day context"
/// the user has enabled — sleep, steps, weather. Stays silent (empty view)
/// when nothing is available, so Home remains uncluttered for users who
/// haven't turned on Health or Weather in Settings.
struct WholeDayContextStrip: View {
    @ObservedObject var health: HealthKitService
    @ObservedObject var weather: WeatherService

    var body: some View {
        let items = buildItems()
        if items.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: 10) {
                ForEach(items.indices, id: \.self) { i in
                    if i > 0 {
                        Circle()
                            .fill(Color.sacredMuted.opacity(0.4))
                            .frame(width: 2, height: 2)
                    }
                    HStack(spacing: 5) {
                        Image(systemName: items[i].symbol)
                            .font(.system(size: 11))
                            .foregroundColor(.sacredMuted)
                        Text(items[i].label)
                            .font(.sacredSmall)
                            .foregroundColor(.sacredTextSecondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private struct Item {
        let symbol: String
        let label: String
    }

    private func buildItems() -> [Item] {
        var items: [Item] = []

        if weather.isEnabled, let snap = weather.snapshot {
            items.append(Item(symbol: snap.conditionSymbol, label: snap.temperatureLabel))
        }

        if health.isEnabled {
            if let hours = health.sleepHoursLastNight, hours > 0 {
                let rounded = (hours * 10).rounded() / 10
                let label = rounded.truncatingRemainder(dividingBy: 1) == 0
                    ? "\(Int(rounded))h"
                    : String(format: "%.1fh", rounded)
                items.append(Item(symbol: "moon.zzz", label: label))
            }
            if let steps = health.stepsToday, steps > 0 {
                items.append(Item(symbol: "figure.walk", label: stepsLabel(steps)))
            }
        }

        return items
    }

    private func stepsLabel(_ steps: Int) -> String {
        if steps >= 1000 {
            let k = Double(steps) / 1000.0
            return String(format: "%.1fk", k)
        }
        return "\(steps)"
    }
}
