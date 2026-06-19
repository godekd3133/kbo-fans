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
    ZStack {
      RoundedRectangle(cornerRadius: 32, style: .continuous)
        .fill(cardGradient)
      RoundedRectangle(cornerRadius: 32, style: .continuous)
        .stroke(Color.white.opacity(0.12), lineWidth: 1)

      VStack(spacing: 14) {
        HStack(alignment: .top, spacing: 12) {
          LiveActivitySidePanel(
            team: displayTeamName(
              teamId: context.state.awayTeamId,
              team: context.state.awayTeam
            ),
            primary: leftDetailPrimary,
            secondary: leftDetailSecondary,
            alignment: .leading,
            frameAlignment: .leading
          )
          .frame(width: 78, alignment: .leading)

          VStack(spacing: 8) {
            HStack(alignment: .center, spacing: 14) {
              scoreView(context.state.awayScore)
              BaseballDiamondView(occupiedBases: occupiedBases)
                .frame(width: 90, height: 58)
              scoreView(context.state.homeScore)
            }

            Text(statusText)
              .font(.system(size: 16, weight: .bold, design: .rounded))
              .foregroundStyle(.white)
              .lineLimit(1)
              .minimumScaleFactor(0.76)
              .padding(.horizontal, 14)
              .padding(.vertical, 6)
              .background(
                Capsule()
                  .fill(Color.white.opacity(0.22))
              )

            CountDotsRow(
              balls: context.state.balls,
              strikes: context.state.strikes,
              outs: context.state.outs
            )
          }
          .frame(maxWidth: .infinity)

          LiveActivitySidePanel(
            team: displayTeamName(
              teamId: context.state.homeTeamId,
              team: context.state.homeTeam
            ),
            primary: rightDetailPrimary,
            secondary: rightDetailSecondary,
            alignment: .trailing,
            frameAlignment: .trailing
          )
          .frame(width: 78, alignment: .trailing)
        }

        Text(bottomSituationText)
          .font(.system(size: 17, weight: .semibold, design: .rounded))
          .foregroundStyle(.white.opacity(0.92))
          .lineLimit(1)
          .minimumScaleFactor(0.72)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 8)
          .padding(.horizontal, 12)
          .background(
            Capsule()
              .fill(Color.white.opacity(0.13))
          )
      }
      .padding(.horizontal, 22)
      .padding(.vertical, 19)
    }
    .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
    .activityBackgroundTint(Color.clear)
    .activitySystemActionForegroundColor(.white)
    .widgetURL(launchURL(gameId: context.attributes.gameId, tab: "relay"))
  }

  private var statusText: String {
    let text = context.state.inning.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    return text.isEmpty ? "경기 중" : text
  }

  private var cardGradient: LinearGradient {
    LinearGradient(
      colors: [
        teamAccentColor(teamId: context.state.awayTeamId).opacity(0.66),
        Color(red: 0.08, green: 0.08, blue: 0.09).opacity(0.98),
        teamAccentColor(teamId: context.state.homeTeamId).opacity(0.72),
      ],
      startPoint: .leading,
      endPoint: .trailing
    )
  }

  private func scoreView(_ score: Int) -> some View {
    Text("\(score)")
      .font(.system(size: 46, weight: .black, design: .rounded))
      .foregroundStyle(.white)
      .monospacedDigit()
      .lineLimit(1)
      .minimumScaleFactor(0.72)
      .frame(width: 45)
  }

  private var leftDetailPrimary: String {
    let batter = trimmed(context.state.batter)
    return batter.isEmpty ? "타자" : batter
  }

  private var leftDetailSecondary: String {
    let situation = trimmed(context.state.situationText)
    return situation.isEmpty ? "타석" : situation
  }

  private var rightDetailPrimary: String {
    let pitcher = trimmed(context.state.pitcher)
    return pitcher.isEmpty ? "투수" : pitcher
  }

  private var rightDetailSecondary: String {
    if context.state.pitchCount > 0 {
      return "\(context.state.pitchCount)구"
    }
    return trimmed(context.state.stadium).isEmpty ? "KBO" : trimmed(context.state.stadium)
  }

  private var bottomSituationText: String {
    let play = cleanedPlayText(context.state.playText)
    if !play.isEmpty {
      return play
    }
    let situation = trimmed(context.state.situationText)
    if !situation.isEmpty {
      return situation
    }
    let batter = trimmed(context.state.batter)
    if !batter.isEmpty {
      return "\(batter) 타석"
    }
    return trimmed(context.state.stadium).isEmpty ? "KBO 경기" : context.state.stadium
  }

  private var occupiedBases: Set<Int> {
    occupiedBasesFromText(context.state.situationText)
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

private struct LiveActivitySidePanel: View {
  let team: String
  let primary: String
  let secondary: String
  let alignment: HorizontalAlignment
  let frameAlignment: Alignment

  var body: some View {
    VStack(alignment: alignment, spacing: 10) {
      Text(team)
        .font(.system(size: 28, weight: .black, design: .rounded))
        .foregroundStyle(.white)
        .lineLimit(1)
        .minimumScaleFactor(0.58)

      VStack(alignment: alignment, spacing: 4) {
        Text(primary)
          .font(.system(size: 18, weight: .medium, design: .rounded))
          .foregroundStyle(.white.opacity(0.9))
          .lineLimit(1)
          .minimumScaleFactor(0.62)
        Text(secondary)
          .font(.system(size: 15, weight: .regular, design: .rounded))
          .foregroundStyle(.white.opacity(0.62))
          .lineLimit(1)
          .minimumScaleFactor(0.62)
      }
    }
    .frame(maxWidth: .infinity, alignment: frameAlignment)
  }
}

private struct BaseballDiamondView: View {
  let occupiedBases: Set<Int>

  var body: some View {
    ZStack {
      base(index: 2)
        .offset(x: 0, y: -18)
      base(index: 3)
        .offset(x: -28, y: 8)
      base(index: 1)
        .offset(x: 28, y: 8)
    }
  }

  private func base(index: Int) -> some View {
    RoundedRectangle(cornerRadius: 5, style: .continuous)
      .fill(occupiedBases.contains(index) ? Color.white : Color.clear)
      .overlay(
        RoundedRectangle(cornerRadius: 5, style: .continuous)
          .stroke(Color.white, lineWidth: 2)
      )
      .frame(width: 35, height: 35)
      .rotationEffect(.degrees(45))
      .shadow(
        color: occupiedBases.contains(index) ? Color.white.opacity(0.18) : .clear,
        radius: 5,
        x: 0,
        y: 2
      )
  }
}

private struct CountDotsRow: View {
  let balls: Int
  let strikes: Int
  let outs: Int

  var body: some View {
    HStack(spacing: 12) {
      CountDotsGroup(label: "B", value: balls, max: 3, color: Color(red: 0.18, green: 0.82, blue: 0.36))
      CountDotsGroup(label: "S", value: strikes, max: 2, color: Color(red: 1.0, green: 0.78, blue: 0.10))
      CountDotsGroup(label: "OUT", value: outs, max: 2, color: Color(red: 1.0, green: 0.24, blue: 0.25))
    }
    .lineLimit(1)
    .minimumScaleFactor(0.72)
  }
}

private struct CountDotsGroup: View {
  let label: String
  let value: Int
  let max: Int
  let color: Color

  var body: some View {
    HStack(spacing: 5) {
      Text(label)
        .font(.system(size: 16, weight: .black, design: .rounded))
        .foregroundStyle(.white)
      ForEach(0..<max, id: \.self) { index in
        Circle()
          .fill(index < clampedValue ? color : Color.white.opacity(0.38))
          .frame(width: 8, height: 8)
      }
    }
  }

  private var clampedValue: Int {
    Swift.max(0, Swift.min(value, max))
  }
}

private struct DynamicIslandTeamScore: View {
  let teamId: String
  let team: String
  let score: Int
  let alignEnd: Bool

  var body: some View {
    VStack(alignment: alignEnd ? .trailing : .leading, spacing: 2) {
      teamName
      Text("\(score)")
        .font(.system(size: 24, weight: .black, design: .rounded))
        .foregroundStyle(.white)
        .monospacedDigit()
    }
    .padding(.horizontal, 2)
  }

  private var teamName: some View {
    Text(displayTeamName(teamId: teamId, team: team))
      .font(.caption.weight(.bold))
      .foregroundStyle(.white.opacity(0.74))
      .lineLimit(1)
      .minimumScaleFactor(0.58)
  }
}

private func pitcherLine(name: String, pitchCount: Int) -> String {
  guard !name.isEmpty else { return "" }
  if pitchCount > 0 {
    return "투수 \(name) · \(pitchCount)구"
  }
  return "투수 \(name)"
}

private func dynamicIslandSituationText(_ state: KboFansScoreAttributes.ContentState) -> String {
  let play = cleanedPlayText(state.playText)
  if !play.isEmpty {
    return play
  }
  let situation = trimmed(state.situationText)
  if !situation.isEmpty {
    return situation
  }
  let batter = trimmed(state.batter)
  if !batter.isEmpty {
    return "\(batter) 타석"
  }
  return trimmed(state.stadium).isEmpty ? "KBO 경기" : state.stadium
}

private func displayTeamName(teamId: String, team: String) -> String {
  let direct = trimmed(team)
  if !direct.isEmpty && direct.count > 2 {
    return direct
  }
  let id = trimmed(teamId).uppercased()
  let names = [
    "LG": "LG",
    "KT": "KT",
    "SK": "SSG",
    "SSG": "SSG",
    "SS": "삼성",
    "NC": "NC",
    "HH": "한화",
    "LT": "롯데",
    "HT": "KIA",
    "OB": "두산",
    "WO": "키움",
  ]
  return names[id] ?? (direct.isEmpty ? id : direct)
}

private func teamAccentColor(teamId: String) -> Color {
  let id = trimmed(teamId).uppercased()
  switch id {
  case "LG":
    return Color(red: 0.72, green: 0.02, blue: 0.22)
  case "KT":
    return Color(red: 0.15, green: 0.15, blue: 0.16)
  case "SK", "SSG":
    return Color(red: 0.82, green: 0.03, blue: 0.10)
  case "SS":
    return Color(red: 0.02, green: 0.24, blue: 0.58)
  case "NC":
    return Color(red: 0.05, green: 0.22, blue: 0.45)
  case "HH":
    return Color(red: 0.90, green: 0.28, blue: 0.05)
  case "LT":
    return Color(red: 0.01, green: 0.17, blue: 0.38)
  case "HT":
    return Color(red: 0.77, green: 0.02, blue: 0.08)
  case "OB":
    return Color(red: 0.06, green: 0.11, blue: 0.28)
  case "WO":
    return Color(red: 0.45, green: 0.05, blue: 0.18)
  default:
    return Color(red: 0.20, green: 0.24, blue: 0.30)
  }
}

private func occupiedBasesFromText(_ text: String?) -> Set<Int> {
  let source = trimmed(text)
  if source.contains("만루") {
    return [1, 2, 3]
  }

  var bases = Set<Int>()
  if source.contains("1루") || source.contains("1,") {
    bases.insert(1)
  }
  if source.contains("2루") || source.contains(",2") || source.contains("2,") {
    bases.insert(2)
  }
  if source.contains("3루") || source.contains(",3") {
    bases.insert(3)
  }
  return bases
}

private func cleanedPlayText(_ text: String?) -> String {
  let source = trimmed(text)
  guard !source.isEmpty else { return "" }
  if let range = source.range(of: " : ") {
    return trimmed(String(source[range.upperBound...]))
  }
  if let range = source.range(of: ":") {
    return trimmed(String(source[range.upperBound...]))
  }
  if let range = source.range(of: "：") {
    return trimmed(String(source[range.upperBound...]))
  }
  return source
}

private func trimmed(_ text: String?) -> String {
  (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
}

private func trimmed(_ text: String) -> String {
  text.trimmingCharacters(in: .whitespacesAndNewlines)
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
          VStack(spacing: 3) {
            BaseballDiamondView(
              occupiedBases: occupiedBasesFromText(context.state.situationText)
            )
            .frame(width: 46, height: 30)
            .scaleEffect(0.58)
            Text(context.state.inning)
              .font(.caption2.weight(.bold))
              .foregroundStyle(.white)
              .lineLimit(1)
              .minimumScaleFactor(0.7)
              .padding(.horizontal, 8)
              .padding(.vertical, 4)
              .background(
                Capsule()
                  .fill(Color.white.opacity(0.18))
              )
          }
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
          VStack(spacing: 6) {
            CountDotsRow(
              balls: context.state.balls,
              strikes: context.state.strikes,
              outs: context.state.outs
            )
            Text(dynamicIslandSituationText(context.state))
              .font(.caption.weight(.semibold))
              .foregroundStyle(.white.opacity(0.9))
              .lineLimit(1)
              .minimumScaleFactor(0.7)
              .frame(maxWidth: .infinity)
              .padding(.vertical, 5)
              .padding(.horizontal, 10)
              .background(
                Capsule()
                  .fill(Color.white.opacity(0.12))
              )
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
      .keylineTint(teamAccentColor(teamId: context.state.homeTeamId))
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
