import WidgetKit
import SwiftUI

struct AgendaEvent: Codable, Identifiable {
    var id: String { title + date }
    let title: String
    let date: String
    let category: String
}

struct AgendaProvider: TimelineProvider {
    func placeholder(in context: Context) -> AgendaEntry {
        AgendaEntry(date: Date(), events: getPlaceholderEvents())
    }

    func getSnapshot(in context: Context, completion: @escaping (AgendaEntry) -> ()) {
        let entry = AgendaEntry(date: Date(), events: fetchEvents())
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        let entries = [AgendaEntry(date: Date(), events: fetchEvents())]
        let timeline = Timeline(entries: entries, policy: .atEnd)
        completion(timeline)
    }

    private func fetchEvents() -> [AgendaEvent] {
        let defaults = UserDefaults(suiteName: "group.com.example.second_brain")
        guard let jsonString = defaults?.string(forKey: "agenda_data") else {
            return []
        }
        
        guard let data = jsonString.data(using: .utf8) else {
            return []
        }
        
        do {
            let events = try JSONDecoder().decode([AgendaEvent].self, from: data)
            return events
        } catch {
            return []
        }
    }

    private func getPlaceholderEvents() -> [AgendaEvent] {
        return [
            AgendaEvent(title: "AI RAG Workshop", date: "2026-05-28", category: "WORK"),
            AgendaEvent(title: "Product Strategy Sync", date: "2026-05-29", category: "MEETING")
        ]
    }
}

struct AgendaEntry: TimelineEntry {
    let date: Date
    let events: [AgendaEvent]
}

struct CortexAgendaWidgetEntryView : View {
    var entry: AgendaProvider.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text("📅 CORTEX_AGENDA")
                    .font(.system(.caption, design: .monospaced))
                    .bold()
                    .foregroundColor(Color("WidgetAccent"))
                Spacer()
            }
            
            if entry.events.isEmpty {
                Spacer()
                HStack {
                    Spacer()
                    Text("No upcoming events")
                        .font(.footnote)
                        .foregroundColor(Color("WidgetTextSecondary"))
                    Spacer()
                }
                Spacer()
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(entry.events.prefix(3)) { event in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(event.title)
                                    .font(.system(.footnote, design: .default))
                                    .bold()
                                    .foregroundColor(Color("WidgetTextPrimary"))
                                    .lineLimit(1)
                                Spacer()
                                Text(event.category.uppercased())
                                    .font(.system(size: 8, weight: .black, design: .monospaced))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(Color("WidgetSurfaceSecondary"))
                                    .foregroundColor(Color("WidgetAccent"))
                            }
                            Text(event.date)
                                .font(.system(size: 9))
                                .foregroundColor(Color("WidgetTextSecondary"))
                        }
                        .padding(.vertical, 2)
                    }
                }
                Spacer()
            }
        }
        .padding()
        .background(Color("WidgetBackground"))
    }
}

struct CortexAgendaWidget: Widget {
    let kind: String = "CortexAgendaWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AgendaProvider()) { entry in
            CortexAgendaWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Cortex Agenda")
        .description("View your upcoming schedule dynamically on your home screen.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
