import SwiftUI
import WidgetKit

struct CaptureEntry: TimelineEntry { let date: Date }
struct CaptureProvider: TimelineProvider {
    func placeholder(in context: Context) -> CaptureEntry { CaptureEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (CaptureEntry) -> Void) { completion(CaptureEntry(date: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<CaptureEntry>) -> Void) { completion(Timeline(entries: [CaptureEntry(date: .now)], policy: .never)) }
}

struct CaptureWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var body: some View {
        Group {
            switch family {
            case .accessoryCircular: Image(systemName: "document.viewfinder").font(.title2)
            case .accessoryInline: Label("Scan note", systemImage: "document.viewfinder")
            case .accessoryRectangular:
                Label { VStack(alignment: .leading) { Text("Folio").font(.headline); Text("Scan a note").font(.caption) } } icon: { Image(systemName: "document.viewfinder") }
            default:
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "document.viewfinder").font(.system(size: 32, weight: .light)).widgetAccentable()
                    Spacer(minLength: 0)
                    Text("Scan a note").font(.system(.headline, design: .serif))
                    if family == .systemMedium {
                        Link(destination: URL(string: "folio://inbox")!) { Label("Unfiled", systemImage: "tray").font(.caption).foregroundStyle(.secondary) }
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "folio://scan"))
    }
}

@main struct FolioCaptureWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FolioCapture", provider: CaptureProvider()) { _ in CaptureWidgetView() }
            .configurationDisplayName("Quick scan").description("Capture handwritten pages into Unfiled.")
            .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
