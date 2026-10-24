import Foundation
import SwiftUI
import WidgetKit

private func text(_ de: String, _ it: String, _ en: String) -> String {
  switch Locale.current.languageCode {
  case "it": return it
  case "en": return en
  default: return de
  }
}

struct PlanningRow: Decodable {
  let subject: String
  let title: String
  let subtitle: String
  let warning: Bool
}

struct PlanningSection: Decodable {
  let title: String
  let subtitle: String
  let emptyMessage: String
  let items: [PlanningRow]
}

struct PlanningSnapshot: Decodable {
  let planningValidOn: String
  let schoolBag: PlanningSection
  let preparation: PlanningSection

  static func load(at date: Date) -> PlanningSnapshot? {
    guard let directory = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: "group.it.bucci.digitalesregister.planning"),
      let data = try? Data(contentsOf: directory.appendingPathComponent("planning.json")),
      let snapshot = try? JSONDecoder().decode(PlanningSnapshot.self, from: data) else { return nil }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    guard snapshot.planningValidOn == formatter.string(from: date) else { return nil }
    return snapshot
  }
}

struct PlanningEntry: TimelineEntry {
  let date: Date
  let section: PlanningSection?
}

struct PlanningProvider: TimelineProvider {
  let schoolBag: Bool
  func placeholder(in context: Context) -> PlanningEntry {
    PlanningEntry(date: Date(), section: nil)
  }
  func entry(at date: Date) -> PlanningEntry {
    let snapshot = PlanningSnapshot.load(at: date)
    return PlanningEntry(date: date, section: schoolBag ? snapshot?.schoolBag : snapshot?.preparation)
  }
  func getSnapshot(in context: Context, completion: @escaping (PlanningEntry) -> Void) {
    completion(context.isPreview ? placeholder(in: context) : entry(at: Date()))
  }
  func getTimeline(in context: Context, completion: @escaping (Timeline<PlanningEntry>) -> Void) {
    let date = Date()
    let midnight = Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: 1, to: date)!)
    // Schedule a content-free entry at midnight even if the app stays closed.
    completion(Timeline(entries: [entry(at: date), PlanningEntry(date: midnight, section: nil)],
      policy: .after(date.addingTimeInterval(30 * 60))))
  }
}

private struct PlanningBackground: ViewModifier {
  @ViewBuilder func body(content: Content) -> some View {
    if #available(iOS 17.0, *) {
      content.containerBackground(for: .widget) { Color(.systemBackground) }
    } else {
      content.padding().background(Color(.systemBackground))
    }
  }
}

struct PlanningView: View {
  let entry: PlanningEntry
  let title: String
  @Environment(\.widgetFamily) var family
  private var limit: Int { family == .systemLarge ? 7 : (family == .systemMedium ? 3 : 2) }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Label(entry.section?.title ?? title, systemImage: title == text("Schultasche", "Zaino", "School bag") ? "backpack" : "checklist")
        .font(.headline).lineLimit(1)
      if let section = entry.section {
        Text(section.subtitle).font(.caption2).foregroundColor(.secondary).lineLimit(1)
        if section.items.isEmpty {
          Text(section.emptyMessage).font(.caption)
        } else {
          ForEach(Array(section.items.prefix(limit).enumerated()), id: \.offset) { _, row in
            VStack(alignment: .leading, spacing: 1) {
              Text(row.subject + " · " + row.title).font(.caption).fontWeight(.semibold)
                .foregroundColor(row.warning ? .orange : .primary).lineLimit(2)
              if family != .systemSmall && !row.subtitle.isEmpty {
                Text(row.subtitle).font(.caption2).foregroundColor(.secondary).lineLimit(1)
              }
            }
          }
          if section.items.count > limit {
            Text("+\(section.items.count - limit) " + text("weitere in der App", "altri nell’app", "more in the app"))
              .font(.caption2).foregroundColor(.secondary)
          }
        }
      } else {
        Text(text("App öffnen, um aktuelle Daten zu laden. Bei App-Sperre sind Widgets ausgeblendet.",
          "Apri l’app per caricare dati aggiornati. I widget sono nascosti con il blocco app.",
          "Open the app to load current data. Widgets are hidden when app lock is enabled."))
          .font(.caption).foregroundColor(.secondary)
      }
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .privacySensitive()
    .widgetURL(URL(string: "register-planning://homework"))
    .modifier(PlanningBackground())
  }
}

struct PlanningWidget: Widget {
  let schoolBag: Bool
  var body: some WidgetConfiguration {
    let title = schoolBag ? text("Schultasche", "Zaino", "School bag") : text("Hausaufgaben", "Compiti", "Homework")
    return StaticConfiguration(kind: schoolBag ? "SchoolBagWidget" : "PreparationWidget",
      provider: PlanningProvider(schoolBag: schoolBag)) { entry in
      PlanningView(entry: entry, title: title)
    }
    .configurationDisplayName(Text(title))
    .description(Text(text("Vorbereitung auf den nächsten Schultag", "Preparazione per il prossimo giorno di scuola", "Prepare for the next school day")))
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}

@main
struct PlanningWidgets: WidgetBundle {
  var body: some Widget {
    PlanningWidget(schoolBag: true)
    PlanningWidget(schoolBag: false)
  }
}
