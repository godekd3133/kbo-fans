import ActivityKit
import Foundation
import SwiftUI
import WidgetKit

private let widgetGroupId = "group.com.kbofans.kbo_fans"
private let kboBackground = Color(red: 0.05, green: 0.05, blue: 0.05)
private let kboCard = Color(red: 0.13, green: 0.14, blue: 0.14)
private let kboDivider = Color(red: 0.22, green: 0.23, blue: 0.24)
private let kboTextSecondary = Color(red: 0.68, green: 0.70, blue: 0.72)
private let kboLive = Color(red: 1.0, green: 0.27, blue: 0.27)

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
  let updatedAtEpoch: Int64
  let statusKind: String
  let launchUri: String
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
      updatedAt: "14:32",
      updatedAtEpoch: Int64(Date().timeIntervalSince1970 * 1000),
      statusKind: "live",
      launchUri: "kboFans://game?gameId=preview&tab=relay&homeWidget"
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
      updatedAt: data?.string(forKey: "widget_updated_at") ?? "--:--",
      updatedAtEpoch: Int64(data?.string(forKey: "widget_updated_at_epoch") ?? "0") ?? 0,
      statusKind: data?.string(forKey: "widget_status_kind") ?? "none",
      launchUri: data?.string(forKey: "widget_launch_uri") ?? "kboFans://home?homeWidget"
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
        if hasAtBatContext {
          _countBadges(balls: entry.balls, strikes: entry.strikes, outs: entry.outs)
        }
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
      Text(
        freshnessText(
          updatedAt: entry.updatedAt,
          updatedAtEpoch: entry.updatedAtEpoch,
          statusKind: entry.statusKind
        )
      )
        .font(.caption2)
        .foregroundStyle(.gray)
    }
    .padding()
    .widgetURL(URL(string: entry.launchUri))

    if #available(iOS 17.0, *) {
      content.containerBackground(for: .widget) {
        Color(red: 0.06, green: 0.06, blue: 0.06)
      }
    } else {
      content.background(Color(red: 0.06, green: 0.06, blue: 0.06))
    }
  }

  private var hasAtBatContext: Bool {
    !entry.batter.isEmpty ||
      !entry.pitcher.isEmpty ||
      entry.pitchCount > 0 ||
      entry.balls > 0 ||
      entry.strikes > 0 ||
      entry.outs > 0
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
      HStack(spacing: 8) {
        liveStatusPill
        if !context.state.stadium.isEmpty {
          Text(context.state.stadium)
            .font(.caption.weight(.semibold))
            .foregroundStyle(kboTextSecondary)
            .lineLimit(1)
        }
        Spacer(minLength: 8)
        Text("갱신 \(context.state.updatedAt)")
          .font(.caption2)
          .foregroundStyle(kboTextSecondary)
      }

      HStack(alignment: .center, spacing: 12) {
        liveTeamBlock(
          teamId: context.state.awayTeamId,
          team: context.state.awayTeam,
          alignEnd: false
        )
        VStack(spacing: 4) {
          Text(scoreText)
            .font(.system(size: 34, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .monospacedDigit()
            .minimumScaleFactor(0.72)
            .lineLimit(1)
          Text(statusText)
            .font(.caption2.weight(.bold))
            .foregroundStyle(kboLive)
            .lineLimit(1)
        }
        .frame(width: 112)
        liveTeamBlock(
          teamId: context.state.homeTeamId,
          team: context.state.homeTeam,
          alignEnd: true
        )
      }

      if hasAtBatContext {
        HStack(alignment: .center, spacing: 12) {
          Text(atBatLine)
            .font(.caption)
            .foregroundStyle(kboTextSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
          Spacer(minLength: 6)
          _countBadges(
            balls: context.state.balls,
            strikes: context.state.strikes,
            outs: context.state.outs
          )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(kboCard)
            .overlay(
              RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(kboDivider, lineWidth: 1)
            )
        )
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 14)
    .activityBackgroundTint(kboBackground.opacity(0.96))
    .activitySystemActionForegroundColor(.white)
    .widgetURL(launchURL(gameId: context.attributes.gameId, tab: "relay"))
  }

  private var statusText: String {
    let text = context.state.inning.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    return text.isEmpty ? "경기 중" : text
  }

  private var scoreText: String {
    "\(context.state.awayScore):\(context.state.homeScore)"
  }

  private var atBatLine: String {
    var parts: [String] = []
    if !context.state.batter.isEmpty {
      parts.append("타석 \(context.state.batter)")
    }
    let pitcher = pitcherLine(
      name: context.state.pitcher,
      pitchCount: context.state.pitchCount
    )
    if !pitcher.isEmpty {
      parts.append(pitcher)
    }
    return parts.joined(separator: " / ")
  }

  private var liveStatusPill: some View {
    HStack(spacing: 6) {
      Circle()
        .fill(kboLive)
        .frame(width: 6, height: 6)
      Text("경기 중")
        .font(.caption2.weight(.bold))
        .foregroundStyle(.white)
    }
    .padding(.horizontal, 9)
    .padding(.vertical, 5)
    .background(
      Capsule()
        .fill(kboLive.opacity(0.16))
        .overlay(
          Capsule()
            .stroke(kboLive.opacity(0.42), lineWidth: 1)
        )
    )
  }

  private func liveTeamBlock(
    teamId: String,
    team: String,
    alignEnd: Bool
  ) -> some View {
    VStack(alignment: alignEnd ? .trailing : .leading, spacing: 6) {
      TeamLogoView(teamId: teamId, fallback: team, size: 30)
      Text(team)
        .font(.caption.weight(.bold))
        .foregroundStyle(.white.opacity(0.82))
        .lineLimit(1)
        .minimumScaleFactor(0.72)
    }
    .frame(maxWidth: .infinity, alignment: alignEnd ? .trailing : .leading)
  }

  private var hasAtBatContext: Bool {
    !context.state.batter.isEmpty ||
      !context.state.pitcher.isEmpty ||
      context.state.pitchCount > 0 ||
      context.state.balls > 0 ||
      context.state.strikes > 0 ||
      context.state.outs > 0
  }
}

private struct DynamicIslandTeamScore: View {
  let teamId: String
  let team: String
  let score: Int
  let alignEnd: Bool

  var body: some View {
    VStack(alignment: alignEnd ? .trailing : .leading, spacing: 3) {
      HStack(spacing: 4) {
        if alignEnd {
          teamName
          TeamLogoView(teamId: teamId, fallback: team, size: 16)
        } else {
          TeamLogoView(teamId: teamId, fallback: team, size: 16)
          teamName
        }
      }
      Text("\(score)")
        .font(.title3.weight(.black))
        .foregroundStyle(.white)
        .monospacedDigit()
    }
  }

  private var teamName: some View {
    Text(team)
      .font(.caption.weight(.semibold))
      .foregroundStyle(kboTextSecondary)
      .lineLimit(1)
      .minimumScaleFactor(0.72)
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
          DynamicIslandTeamScore(
            teamId: context.state.awayTeamId,
            team: context.state.awayTeam,
            score: context.state.awayScore,
            alignEnd: false
          )
        }
        DynamicIslandExpandedRegion(.center) {
          Text(context.state.inning)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
              Capsule()
                .fill(kboLive)
            )
        }
        DynamicIslandExpandedRegion(.trailing) {
          DynamicIslandTeamScore(
            teamId: context.state.homeTeamId,
            team: context.state.homeTeam,
            score: context.state.homeScore,
            alignEnd: true
          )
        }
        DynamicIslandExpandedRegion(.bottom) {
          VStack(alignment: .leading, spacing: 4) {
            HStack {
              Text(
                context.state.stadium.isEmpty ? "KBO" : context.state.stadium
              )
                .font(.caption)
                .foregroundStyle(kboTextSecondary)
              Spacer()
              if hasAtBatContext(context.state) {
                _countBadges(
                  balls: context.state.balls,
                  strikes: context.state.strikes,
                  outs: context.state.outs
                )
              }
            }
            if !context.state.batter.isEmpty {
              Text("타석 \(context.state.batter)")
                .font(.caption2)
                .foregroundStyle(kboTextSecondary)
            }
            if !context.state.pitcher.isEmpty {
              Text(
                pitcherLine(
                  name: context.state.pitcher,
                  pitchCount: context.state.pitchCount
                )
              )
                .font(.caption2)
                .foregroundStyle(kboTextSecondary)
            }
            Text("갱신 \(context.state.updatedAt)")
              .font(.caption2)
              .foregroundStyle(kboTextSecondary)
          }
        }
      } compactLeading: {
        Text("\(context.state.awayScore)")
          .font(.headline.weight(.black))
          .foregroundStyle(.white)
          .monospacedDigit()
      } compactTrailing: {
        Text("\(context.state.homeScore)")
          .font(.headline.weight(.black))
          .foregroundStyle(.white)
          .monospacedDigit()
      } minimal: {
        Text("\(context.state.awayScore):\(context.state.homeScore)")
          .font(.caption2.weight(.bold))
          .foregroundStyle(.white)
          .monospacedDigit()
      }
      .keylineTint(kboLive)
      .widgetURL(launchURL(gameId: context.attributes.gameId, tab: "relay"))
    }
  }

  private func hasAtBatContext(_ state: KboFansScoreAttributes.ContentState) -> Bool {
    !state.batter.isEmpty ||
      !state.pitcher.isEmpty ||
      state.pitchCount > 0 ||
      state.balls > 0 ||
      state.strikes > 0 ||
      state.outs > 0
  }
}

private func freshnessText(
  updatedAt: String,
  updatedAtEpoch: Int64,
  statusKind: String
) -> String {
  guard updatedAtEpoch > 0 else {
    return "업데이트 \(updatedAt)"
  }
  let ageMs = Int64(Date().timeIntervalSince1970 * 1000) - updatedAtEpoch
  let thresholdMs: Int64 = statusKind == "live" ? 2 * 60 * 1000 : 15 * 60 * 1000
  if ageMs > thresholdMs {
    return "업데이트 지연 \(updatedAt)"
  }
  return "업데이트 \(updatedAt)"
}

private func launchURL(gameId: String, tab: String) -> URL? {
  var components = URLComponents()
  components.scheme = "kboFans"
  components.host = "game"
  components.queryItems = [
    URLQueryItem(name: "gameId", value: gameId),
    URLQueryItem(name: "tab", value: tab),
    URLQueryItem(name: "homeWidget", value: ""),
  ]
  return components.url
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
