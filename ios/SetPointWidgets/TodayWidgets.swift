import SwiftUI
import WidgetKit

struct TodayWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: TodaySnapshot
}

struct TodayWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayWidgetEntry {
        TodayWidgetEntry(date: .now, snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayWidgetEntry) -> Void) {
        completion(TodayWidgetEntry(date: .now, snapshot: context.isPreview ? .preview : .load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayWidgetEntry>) -> Void) {
        let entry = TodayWidgetEntry(date: .now, snapshot: .load())
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct SetPointTodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SetPointTodayWidget", provider: TodayWidgetProvider()) { entry in
            SetPointTodayWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetChrome.paper }
        }
        .configurationDisplayName("Today")
        .description("Calories left, the next check-in, and your usual meals.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct SetPointLockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SetPointLockWidget", provider: TodayWidgetProvider()) { entry in
            SetPointLockWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Check-in")
        .description("The next check-in on the Lock Screen.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

struct SetPointTodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayWidgetEntry

    var body: some View {
        switch family {
        case .systemMedium:
            TodayWidgetMediumView(snapshot: entry.snapshot)
        default:
            TodayWidgetSmallView(snapshot: entry.snapshot)
        }
    }
}

struct SetPointLockWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayWidgetEntry

    var body: some View {
        switch family {
        case .accessoryRectangular:
            TodayLockRectangularView(snapshot: entry.snapshot)
        default:
            TodayLockCircularView(snapshot: entry.snapshot)
        }
    }
}

#Preview("Small", as: .systemSmall) {
    SetPointTodayWidget()
} timeline: {
    TodayWidgetEntry(date: .now, snapshot: .preview)
}

#Preview("Medium", as: .systemMedium) {
    SetPointTodayWidget()
} timeline: {
    TodayWidgetEntry(date: .now, snapshot: .preview)
}

#Preview("Lock circular", as: .accessoryCircular) {
    SetPointLockWidget()
} timeline: {
    TodayWidgetEntry(date: .now, snapshot: .preview)
}

#Preview("Lock rectangular", as: .accessoryRectangular) {
    SetPointLockWidget()
} timeline: {
    TodayWidgetEntry(date: .now, snapshot: .preview)
}
