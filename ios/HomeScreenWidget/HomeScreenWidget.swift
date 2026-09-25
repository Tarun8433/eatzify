import SwiftUI
import WidgetKit

// MARK: - What the app published

/// Today, as the Flutter side wrote it.
///
/// **Every figure is optional and stays optional.** `UserDefaults.integer(forKey:)` returns 0 for a
/// key that was never written, which would turn "nobody measured" into "they drank nothing" — two
/// different sentences, and only one of them is ever true (D-80). So each is read through `object`
/// and rendered as an em dash when absent.
struct Today {
    let waterMl: Int?
    let waterTargetMl: Int?
    let steps: Int?
    let kcal: Int?
    let kcalTarget: Int?
    /// What they moved off, as the phone or the person reported it. Its own figure, never netted
    /// against what they ate — docs/05 §6 keeps "eaten minus burned" off every screen, because a
    /// single number invites somebody to earn their dinner back.
    let burnedKcal: Int?

    /// Must match `HomeScreenWidget.appGroupId` in Dart and the App Group in both entitlements
    /// files. A mismatch is silent: the container opens empty and the widget shows placeholders
    /// forever.
    static let appGroup = "group.com.tarun.Influnexa.liveactivities"

    static func load() -> Today {
        let store = UserDefaults(suiteName: appGroup)

        func read(_ key: String) -> Int? {
            store?.object(forKey: key) as? Int
        }

        return Today(
            waterMl: read("water_ml"),
            waterTargetMl: read("water_target_ml"),
            steps: read("steps"),
            kcal: read("kcal"),
            kcalTarget: read("kcal_target"),
            burnedKcal: read("burned_kcal")
        )
    }

    /// Nil when there is no plan — docs/04 §2: a plan that fired a blocking gate has no targets, and
    /// a bar against a target of nothing would be a comparison to zero.
    var caloriesProgress: Double? { Self.fraction(kcal, of: kcalTarget) }

    var waterProgress: Double? { Self.fraction(waterMl, of: waterTargetMl) }

    private static func fraction(_ value: Int?, of target: Int?) -> Double? {
        guard let target, target > 0 else { return nil }
        return min(Double(value ?? 0) / Double(target), 1)
    }

    static let placeholder = Today(
        waterMl: 1200, waterTargetMl: 2400, steps: 6480,
        kcal: 1240, kcalTarget: 1859, burnedKcal: 410
    )

    static let empty = Today(
        waterMl: nil, waterTargetMl: nil, steps: nil,
        kcal: nil, kcalTarget: nil, burnedKcal: nil
    )
}

/// Grouped for the reader's locale, and an em dash for anything nobody measured — never a zero.
private func show(_ value: Int?) -> String {
    guard let value else { return "—" }
    return value.formatted()
}

// MARK: - Palette

/// The app's colours, duplicated because a widget cannot read Dart. The Android widget draws the
/// same card (`widget_colors.xml`); if either moves, both have to.
private enum Ink {
    static let top = Color(red: 0.118, green: 0.275, blue: 0.216)
    static let surface = Color(red: 0.071, green: 0.212, blue: 0.165)
    static let onSurface = Color.white
    static let muted = Color.white.opacity(0.62)
    static let track = Color.white.opacity(0.22)
    static let tile = Color.white.opacity(0.10)
    static let accent = Color(red: 0.48, green: 0.77, blue: 0.50)

    static let background = LinearGradient(
        colors: [top, surface], startPoint: .top, endPoint: .bottom
    )
}

/// Where each tap goes. The `homeWidget` query is how `home_widget` tells a widget's URL from any
/// other the app is opened with; without it a tap opens the app and nothing is routed.
private enum Links {
    /// The "+". A widget can only open its app, so the app adds the glass when it arrives (D-219).
    static let addGlass = URL(string: "eatzify://water?homeWidget")!
    /// The water tile: the day, not a write.
    static let today = URL(string: "eatzify://today?homeWidget")!
    static let steps = URL(string: "eatzify://steps?homeWidget")!
    static let meal = URL(string: "eatzify://meal?homeWidget")!
}

// MARK: - Timeline

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry {
        Entry(date: Date(), today: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: Date(), today: context.isPreview ? .placeholder : Today.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        // One entry, and `.never`. The app pushes an update every time the diary changes, which is
        // the only moment these figures actually move — a schedule would just redraw stale numbers.
        completion(Timeline(entries: [Entry(date: Date(), today: Today.load())], policy: .never))
    }
}

struct Entry: TimelineEntry {
    let date: Date
    let today: Today
}

// MARK: - The widget

struct HomeScreenWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HomeScreenWidget", provider: Provider()) { entry in
            WidgetView(today: entry.today)
                .containerBackground(for: .widget) { Ink.background }
        }
        .configurationDisplayName("Eatzify")
        .description("Today's calories, water, steps and calories burned.")
        // Three sizes (D-219), each laid out for its own space rather than one layout stretched.
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct WidgetView: View {
    @Environment(\.widgetFamily) private var family
    let today: Today

    var body: some View {
        switch family {
        case .systemSmall: SmallWidget(today: today)
        case .systemLarge: LargeWidget(today: today)
        default: MediumWidget(today: today)
        }
    }
}

// MARK: - Small

/// Calories against the plan, with water, steps and burned around it.
///
/// A small widget is one tap target — iOS does not honour a `Link` inside it — so there is no glass
/// button here, just the figure; the whole card opens the app.
struct SmallWidget: View {
    let today: Today

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Ink.accent)
                    .widgetAccentable()
                Spacer(minLength: 4)
                Figure(icon: "drop.fill", value: show(today.waterMl), size: 13)
            }

            Spacer(minLength: 6)

            Text(show(today.kcal))
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(Ink.onSurface)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(caloriesCaption(today, unit: "kcal"))
                .font(.system(size: 12))
                .foregroundStyle(Ink.muted)
                .lineLimit(1)

            ProgressLine(fraction: today.caloriesProgress, height: 5)
                .padding(.top, 8)

            HStack(spacing: 10) {
                Figure(icon: "figure.walk", value: show(today.steps), size: 13)
                Figure(icon: "flame", value: show(today.burnedKcal), size: 13)
            }
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Medium

/// The headline, the one button that writes, and four tiles — the design the Android medium widget
/// copies.
struct MediumWidget: View {
    let today: Today

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                FlameTile(size: 52)
                CaloriesHeadline(today: today, numberSize: 26, captionSize: 13, unit: "calories")
                Spacer(minLength: 4)
                AddGlassButton(size: 46)
            }

            ProgressLine(fraction: today.caloriesProgress, height: 4)

            HStack(spacing: 8) {
                // Water carries its target because a plan sets one; steps and burned have none, so
                // neither is shown against a goal that was never set.
                QuickTile(icon: "drop.fill", value: waterReading, label: "Water", url: Links.today)
                QuickTile(icon: "figure.walk", value: show(today.steps), label: "Steps", url: Links.steps)
                QuickTile(icon: "flame", value: show(today.burnedKcal), label: "Burned", url: Links.steps)
                QuickTile(icon: "fork.knife", value: "Log", label: "Meal", url: Links.meal)
            }
        }
    }

    private var waterReading: String {
        guard let logged = today.waterMl else { return "—" }
        guard let target = today.waterTargetMl else { return show(logged) }
        return "\(show(logged))/\(show(target))"
    }
}

// MARK: - Large

/// Everything for today with room to read it: water gets its own bar against its own target.
struct LargeWidget: View {
    let today: Today

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                FlameTile(size: 60)
                CaloriesHeadline(today: today, numberSize: 34, captionSize: 15, unit: "calories")
                Spacer(minLength: 4)
                AddGlassButton(size: 54)
            }

            ProgressLine(fraction: today.caloriesProgress, height: 6)

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    BigTile(
                        icon: "drop.fill",
                        value: show(today.waterMl),
                        caption: today.waterTargetMl.map { "of \(show($0)) ml" } ?? "ml today",
                        url: Links.today,
                        progress: today.waterProgress
                    )
                    BigTile(
                        icon: "figure.walk",
                        value: show(today.steps),
                        caption: "steps today",
                        url: Links.steps,
                        // Held level with the water tile's bar, so the two figures share a line.
                        reservesBar: today.waterProgress != nil
                    )
                }
                HStack(spacing: 10) {
                    BigTile(
                        icon: "flame",
                        value: show(today.burnedKcal),
                        caption: "kcal while active",
                        url: Links.steps
                    )
                    BigTile(
                        icon: "fork.knife",
                        value: "Log a meal",
                        caption: "Search a food",
                        url: Links.meal
                    )
                }
            }
        }
    }
}

// MARK: - Pieces

private func caloriesCaption(_ today: Today, unit: String) -> String {
    // No plan yet. Said plainly rather than compared against nothing.
    guard let target = today.kcalTarget else { return "calories today" }
    return "of \(show(target)) \(unit)"
}

private struct FlameTile: View {
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(Ink.tile)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: "flame.fill")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(Ink.accent)
                    .widgetAccentable()
            )
    }
}

private struct CaloriesHeadline: View {
    let today: Today
    let numberSize: CGFloat
    let captionSize: CGFloat
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(show(today.kcal))
                .font(.system(size: numberSize, weight: .bold, design: .rounded))
                .foregroundStyle(Ink.onSurface)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(caloriesCaption(today, unit: unit))
                .font(.system(size: captionSize))
                .foregroundStyle(Ink.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

/// The only control that adds without choosing anything: a glass. It opens the app to do it.
private struct AddGlassButton: View {
    let size: CGFloat

    var body: some View {
        Link(destination: Links.addGlass) {
            ZStack {
                Circle().fill(Ink.accent).frame(width: size, height: size)
                Image(systemName: "plus")
                    .font(.system(size: size * 0.43, weight: .bold))
                    .foregroundStyle(Ink.surface)
            }
            .widgetAccentable()
        }
        .accessibilityLabel("Add a glass of water")
    }
}

private struct ProgressLine: View {
    let fraction: Double?
    let height: CGFloat

    var body: some View {
        GeometryReader { box in
            ZStack(alignment: .leading) {
                Capsule().fill(Ink.track)
                if let fraction {
                    Capsule()
                        .fill(Ink.accent)
                        .frame(width: max(box.size.width * fraction, height))
                        .widgetAccentable()
                }
            }
        }
        .frame(height: height)
    }
}

/// An icon beside a figure, for the small widget's corners.
private struct Figure: View {
    let icon: String
    let value: String
    let size: CGFloat

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: size - 1, weight: .semibold))
                .foregroundStyle(Ink.accent)
                .widgetAccentable()
            Text(value)
                .font(.system(size: size, weight: .bold, design: .rounded))
                .foregroundStyle(Ink.onSurface)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

/// One of the medium widget's four: each opens the app where that number is logged.
private struct QuickTile: View {
    let icon: String
    let value: String
    let label: String
    let url: URL

    var body: some View {
        Link(destination: url) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Ink.accent)
                    .widgetAccentable()
                Text(value)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Ink.onSurface)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(Ink.muted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Ink.tile))
        }
    }
}

/// One of the large widget's four: the figure low in the tile, where the eye lands after the icon.
private struct BigTile: View {
    let icon: String
    let value: String
    let caption: String
    let url: URL
    var progress: Double? = nil
    var reservesBar = false

    var body: some View {
        Link(destination: url) {
            VStack(alignment: .leading, spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Ink.accent)
                    .widgetAccentable()
                Spacer(minLength: 4)
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Ink.onSurface)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(caption)
                    .font(.system(size: 12))
                    .foregroundStyle(Ink.muted)
                    .lineLimit(1)
                if let progress {
                    ProgressLine(fraction: progress, height: 4).padding(.top, 6)
                } else if reservesBar {
                    Color.clear.frame(height: 4).padding(.top, 6)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Ink.tile))
        }
    }
}

// MARK: - Previews

#Preview(as: .systemSmall) {
    HomeScreenWidget()
} timeline: {
    Entry(date: .now, today: .placeholder)
    Entry(date: .now, today: .empty)
}

#Preview(as: .systemMedium) {
    HomeScreenWidget()
} timeline: {
    Entry(date: .now, today: .placeholder)
    // The state that matters most to get right: a brand-new account where nothing is measured yet.
    Entry(date: .now, today: .empty)
}

#Preview(as: .systemLarge) {
    HomeScreenWidget()
} timeline: {
    Entry(date: .now, today: .placeholder)
    Entry(date: .now, today: .empty)
}
