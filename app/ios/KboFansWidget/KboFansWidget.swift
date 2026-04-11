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
  let awayTeamId: String
  let homeTeamId: String
  let batter: String
  let pitcher: String
  let pitchCount: Int
  let balls: Int
  let strikes: Int
  let outs: Int
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
      awayTeamId: "LG",
      homeTeamId: "KT",
      batter: "박해민",
      pitcher: "켈리",
      pitchCount: 37,
      balls: 2,
      strikes: 1,
      outs: 1,
      updatedAt: "14:32"
    )
  }

  func getSnapshot(in context: Context, completion: @escaping (KboFansWidgetEntry) -> Void) {
    completion(loadEntry())
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<KboFansWidgetEntry>) -> Void) {
    let entry = loadEntry()
    let nextRefresh = Calendar.current.date(byAdding: .minute, value: 1, to: Date()) ?? Date().addingTimeInterval(60)
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
      awayTeamId: data?.string(forKey: "widget_away_team_id") ?? "",
      homeTeamId: data?.string(forKey: "widget_home_team_id") ?? "",
      batter: data?.string(forKey: "widget_batter") ?? "",
      pitcher: data?.string(forKey: "widget_pitcher") ?? "",
      pitchCount: Int(data?.string(forKey: "widget_pitch_count") ?? "0") ?? 0,
      balls: Int(data?.string(forKey: "widget_balls") ?? "0") ?? 0,
      strikes: Int(data?.string(forKey: "widget_strikes") ?? "0") ?? 0,
      outs: Int(data?.string(forKey: "widget_outs") ?? "0") ?? 0,
      updatedAt: data?.string(forKey: "widget_updated_at") ?? "--:--"
    )
  }
}

struct KboFansWidgetEntryView: View {
  let entry: KboFansWidgetProvider.Entry

  var body: some View {
    let content = VStack(alignment: .leading, spacing: 6) {
      Text(entry.title)
        .font(.headline)
        .foregroundStyle(.white)
      Text(entry.subtitle)
        .font(.caption)
        .foregroundStyle(.gray)
      Spacer(minLength: 6)
      HStack(alignment: .center) {
        TeamLogoView(teamId: entry.awayTeamId, fallback: "A", size: 22)
        Text(entry.score)
          .font(.title2)
          .bold()
          .foregroundStyle(.white)
        TeamLogoView(teamId: entry.homeTeamId, fallback: "H", size: 22)
        Spacer(minLength: 10)
        _countBadges(balls: entry.balls, strikes: entry.strikes, outs: entry.outs)
      }
      Text(entry.status)
        .font(.subheadline)
        .foregroundStyle(Color(red: 1.0, green: 0.27, blue: 0.27))
      if !entry.batter.isEmpty {
        Text("타석 \(entry.batter)")
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      if !entry.pitcher.isEmpty {
        Text(pitcherLine(name: entry.pitcher, pitchCount: entry.pitchCount))
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      Text("업데이트 \(entry.updatedAt)")
        .font(.caption2)
        .foregroundStyle(.gray)
    }
    .padding()

    if #available(iOS 17.0, *) {
      content.containerBackground(for: .widget) {
        Color(red: 0.06, green: 0.06, blue: 0.06)
      }
    } else {
      content.background(Color(red: 0.06, green: 0.06, blue: 0.06))
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
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}

@available(iOS 16.1, *)
struct KboFansLiveActivityView: View {
  let context: ActivityViewContext<KboFansScoreAttributes>

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Spacer(minLength: 0)
        HStack(alignment: .center, spacing: 14) {
          scoreColumn(
            teamId: context.state.awayTeamId,
            team: context.state.awayTeam,
            score: context.state.awayScore
          )
            .frame(width: 64, alignment: .trailing)
          inningBadge
          scoreColumn(
            teamId: context.state.homeTeamId,
            team: context.state.homeTeam,
            score: context.state.homeScore,
            trailing: true
          )
            .frame(width: 64, alignment: .leading)
        }
        Spacer(minLength: 0)
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
      HStack(alignment: .top, spacing: 12) {
        VStack(alignment: .leading, spacing: 2) {
          if !context.state.batter.isEmpty {
            Text("타석 \(context.state.batter)")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          if !context.state.pitcher.isEmpty {
            Text(
              pitcherLine(
                name: context.state.pitcher,
                pitchCount: context.state.pitchCount
              )
            )
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        Spacer(minLength: 8)
        _countBadges(
          balls: context.state.balls,
          strikes: context.state.strikes,
          outs: context.state.outs
        )
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 14)
    .activityBackgroundTint(Color.black.opacity(0.94))
    .activitySystemActionForegroundColor(.white)
  }

  private func scoreColumn(
    teamId: String,
    team: String,
    score: Int,
    trailing: Bool = false
  ) -> some View {
    VStack(alignment: trailing ? .trailing : .leading, spacing: 4) {
      HStack(spacing: 6) {
        if trailing {
          Text(team)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
          TeamLogoView(teamId: teamId, fallback: team, size: 20)
        } else {
          TeamLogoView(teamId: teamId, fallback: team, size: 20)
          Text(team)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
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

private func pitcherLine(name: String, pitchCount: Int) -> String {
  guard !name.isEmpty else { return "" }
  if pitchCount > 0 {
    return "투수 \(name) · \(pitchCount)구"
  }
  return "투수 \(name)"
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
            HStack(spacing: 4) {
              TeamLogoView(teamId: context.state.awayTeamId, fallback: context.state.awayTeam, size: 16)
              Text(context.state.awayTeam)
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
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
            HStack(spacing: 4) {
              Text(context.state.homeTeam)
                .font(.caption2)
                .foregroundStyle(.secondary)
              TeamLogoView(teamId: context.state.homeTeamId, fallback: context.state.homeTeam, size: 16)
            }
            Text("\(context.state.homeScore)")
              .font(.title3.weight(.bold))
              .foregroundStyle(.white)
          }
        }
        DynamicIslandExpandedRegion(.bottom) {
          VStack(alignment: .leading, spacing: 4) {
            HStack {
              Label(context.state.stadium, systemImage: "baseball")
                .font(.caption)
                .foregroundStyle(.secondary)
              Spacer()
              _countBadges(
                balls: context.state.balls,
                strikes: context.state.strikes,
                outs: context.state.outs
              )
            }
            if !context.state.batter.isEmpty {
              Text("타석 \(context.state.batter)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            if !context.state.pitcher.isEmpty {
              Text("투수 \(context.state.pitcher)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
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

private struct TeamLogoView: View {
  let teamId: String
  let fallback: String
  let size: CGFloat

  var body: some View {
    if let assetName = teamLogoAssetName(teamId: teamId) {
      Image(assetName)
        .resizable()
        .scaledToFit()
        .frame(width: size, height: size)
    } else if let url = teamLogoURL(teamId: teamId) {
      AsyncImage(url: url) { phase in
        switch phase {
        case .success(let image):
          image
            .resizable()
            .scaledToFit()
        default:
          fallbackView
        }
      }
      .frame(width: size, height: size)
    } else {
      fallbackView
    }
  }

  private var fallbackView: some View {
    ZStack {
      RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
        .fill(Color.white.opacity(0.12))
      Text(String(fallback.prefix(1)))
        .font(.system(size: size * 0.45, weight: .bold, design: .rounded))
        .foregroundStyle(.white)
    }
    .frame(width: size, height: size)
  }
}

private func teamLogoAssetName(teamId: String) -> String? {
  let trimmed = teamId.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !trimmed.isEmpty else { return nil }
  return "TeamLogo_\(trimmed)"
}

private func teamLogoURL(teamId: String) -> URL? {
  let trimmed = teamId.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !trimmed.isEmpty else { return nil }
  let year = Calendar.current.component(.year, from: Date())
  return URL(
    string: "https://6ptotvmi5753.edge.naverncp.com/KBO_IMAGE/emblem/regular/\(year)/initial_\(trimmed)_s.png"
  )
}

@ViewBuilder
private func _countBadges(balls: Int, strikes: Int, outs: Int) -> some View {
  HStack(spacing: 6) {
    _countBadge(label: "B", value: balls, tint: Color(red: 1.0, green: 0.84, blue: 0.0))
    _countBadge(label: "S", value: strikes, tint: Color(red: 1.0, green: 0.27, blue: 0.27))
    _countBadge(label: "O", value: outs, tint: .white)
  }
}

private func _countBadge(label: String, value: Int, tint: Color) -> some View {
  VStack(spacing: 1) {
    Text(label)
      .font(.system(size: 9, weight: .bold))
      .foregroundStyle(tint.opacity(0.85))
    Text("\(value)")
      .font(.system(size: 13, weight: .bold, design: .rounded))
      .foregroundStyle(.white)
  }
  .padding(.horizontal, 7)
  .padding(.vertical, 4)
  .background(
    RoundedRectangle(cornerRadius: 10, style: .continuous)
      .fill(tint.opacity(0.14))
  )
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
