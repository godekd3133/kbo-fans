import ActivityKit
import SwiftUI
import WidgetKit

private let widgetGroupId = "group.com.kbofans.kbo_fans"

struct KboFansWidgetEntry: TimelineEntry {
  let date: Date
  let title: String
  let subtitle: String
  let status: String
  let score: String
  let updatedAt: String
}

struct KboFansWidgetProvider: TimelineProvider {
  func placeholder(in context: Context) -> KboFansWidgetEntry {
    KboFansWidgetEntry(
      date: Date(),
      title: "LG vs KT",
      subtitle: "잠실",
      status: "4회초",
      score: "6 : 2",
      updatedAt: "14:32"
    )
  }

  func getSnapshot(in context: Context, completion: @escaping (KboFansWidgetEntry) -> Void) {
    completion(loadEntry())
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<KboFansWidgetEntry>) -> Void) {
    let entry = loadEntry()
    let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
    completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
  }

  private func loadEntry() -> KboFansWidgetEntry {
    let data = UserDefaults(suiteName: widgetGroupId)
    return KboFansWidgetEntry(
      date: Date(),
      title: data?.string(forKey: "widget_title") ?? "오늘 경기 없음",
      subtitle: data?.string(forKey: "widget_subtitle") ?? "KBO Fans",
      status: data?.string(forKey: "widget_status") ?? "",
      score: data?.string(forKey: "widget_score") ?? "",
      updatedAt: data?.string(forKey: "widget_updated_at") ?? "--:--"
    )
  }
}

struct KboFansWidgetEntryView: View {
  let entry: KboFansWidgetProvider.Entry

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(entry.title)
        .font(.headline)
        .foregroundStyle(.white)
      Text(entry.subtitle)
        .font(.caption)
        .foregroundStyle(.gray)
      Spacer(minLength: 6)
      Text(entry.status)
        .font(.subheadline)
        .foregroundStyle(Color(red: 1.0, green: 0.27, blue: 0.27))
      Text(entry.score)
        .font(.title2)
        .bold()
        .foregroundStyle(.white)
      Text("업데이트 \(entry.updatedAt)")
        .font(.caption2)
        .foregroundStyle(.gray)
    }
    .padding()
    .containerBackground(for: .widget) {
      Color(red: 0.06, green: 0.06, blue: 0.06)
    }
  }
}

struct KboFansWidget: Widget {
  let kind: String = "KboFansWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: KboFansWidgetProvider()) { entry in
      KboFansWidgetEntryView(entry: entry)
    }
    .configurationDisplayName("KBO Fans")
    .description("마이팀 혹은 현재 경기 점수를 빠르게 확인합니다.")
    .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
  }
}

@available(iOS 16.1, *)
struct KboFansLiveActivityView: View {
  let context: ActivityViewContext<KboFansScoreAttributes>

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .center, spacing: 12) {
        scoreColumn(team: context.state.awayTeam, score: context.state.awayScore)
        Spacer(minLength: 8)
        inningBadge
        Spacer(minLength: 8)
        scoreColumn(team: context.state.homeTeam, score: context.state.homeScore, trailing: true)
      }

      HStack {
        Label(context.state.stadium, systemImage: "mappin.and.ellipse")
          .font(.caption)
          .foregroundStyle(.secondary)
        Spacer()
        Text("업데이트 \(context.state.updatedAt)")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 14)
    .activityBackgroundTint(Color.black.opacity(0.94))
    .activitySystemActionForegroundColor(.white)
  }

  private func scoreColumn(team: String, score: Int, trailing: Bool = false) -> some View {
    VStack(alignment: trailing ? .trailing : .leading, spacing: 4) {
      Text(team)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
      Text("\(score)")
        .font(.system(size: 30, weight: .bold, design: .rounded))
        .foregroundStyle(.white)
    }
  }

  private var inningBadge: some View {
    Text(context.state.inning)
      .font(.caption.weight(.semibold))
      .foregroundStyle(.white)
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .background(
        Capsule()
          .fill(Color(red: 1.0, green: 0.27, blue: 0.27))
      )
  }
}

@available(iOS 16.1, *)
struct KboFansLiveActivityWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: KboFansScoreAttributes.self) { context in
      KboFansLiveActivityView(context: context)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          VStack(alignment: .leading, spacing: 2) {
            Text(context.state.awayTeam)
              .font(.caption2)
              .foregroundStyle(.secondary)
            Text("\(context.state.awayScore)")
              .font(.title3.weight(.bold))
              .foregroundStyle(.white)
          }
        }
        DynamicIslandExpandedRegion(.center) {
          Text(context.state.inning)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
              Capsule()
                .fill(Color(red: 1.0, green: 0.27, blue: 0.27))
            )
        }
        DynamicIslandExpandedRegion(.trailing) {
          VStack(alignment: .trailing, spacing: 2) {
            Text(context.state.homeTeam)
              .font(.caption2)
              .foregroundStyle(.secondary)
            Text("\(context.state.homeScore)")
              .font(.title3.weight(.bold))
              .foregroundStyle(.white)
          }
        }
        DynamicIslandExpandedRegion(.bottom) {
          HStack {
            Label(context.state.stadium, systemImage: "baseball")
              .font(.caption)
              .foregroundStyle(.secondary)
            Spacer()
            Text("업데이트 \(context.state.updatedAt)")
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
        }
      } compactLeading: {
        Text("\(context.state.awayScore)")
          .font(.headline.weight(.bold))
          .foregroundStyle(.white)
      } compactTrailing: {
        Text("\(context.state.homeScore)")
          .font(.headline.weight(.bold))
          .foregroundStyle(.white)
      } minimal: {
        Text("\(context.state.awayScore):\(context.state.homeScore)")
          .font(.caption2.weight(.bold))
          .foregroundStyle(.white)
      }
      .keylineTint(Color(red: 1.0, green: 0.27, blue: 0.27))
    }
  }
}

@main
struct KboFansWidgetBundle: WidgetBundle {
  @WidgetBundleBuilder
  var body: some Widget {
    KboFansWidget()
    if #available(iOS 16.1, *) {
      KboFansLiveActivityWidget()
    }
  }
}
