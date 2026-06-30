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
  let summaryTitle: String
  let contextLabel: String
  let todayCount: Int
  let liveCount: Int
  let secondaryTitle: String
  let secondaryStatus: String
  let secondaryScore: String
  let summaryLines: [String]
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
      launchUri: "kboFans://game?gameId=preview&tab=relay&homeWidget",
      summaryTitle: "LIVE 2경기",
      contextLabel: "마이팀",
      todayCount: 5,
      liveCount: 2,
      secondaryTitle: "삼성 vs SSG",
      secondaryStatus: "18:30 예정",
      secondaryScore: "vs",
      summaryLines: [
        "LG 6:2 KT · 4회초",
        "삼성 vs SSG · 18:30 예정",
        "KIA 1:0 두산 · 2회말",
      ]
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
      launchUri: data?.string(forKey: "widget_launch_uri") ?? "kboFans://home?homeWidget",
      summaryTitle: data?.string(forKey: "widget_summary_title") ?? "오늘 경기 없음",
      contextLabel: data?.string(forKey: "widget_context_label") ?? "오늘 경기",
      todayCount: Int(data?.string(forKey: "widget_today_count") ?? "0") ?? 0,
      liveCount: Int(data?.string(forKey: "widget_live_count") ?? "0") ?? 0,
      secondaryTitle: data?.string(forKey: "widget_secondary_title") ?? "",
      secondaryStatus: data?.string(forKey: "widget_secondary_status") ?? "",
      secondaryScore: data?.string(forKey: "widget_secondary_score") ?? "",
      summaryLines: (1...4).compactMap { index in
        let line = data?.string(forKey: "widget_summary_line_\(index)") ?? ""
        return line.isEmpty ? nil : line
      }
    )
  }
}

struct KboFansWidgetEntryView: View {
  @Environment(\.widgetFamily) private var family
  let entry: KboFansWidgetProvider.Entry

  var body: some View {
    let content = widgetContent
      .widgetURL(URL(string: entry.launchUri))

    if #available(iOS 17.0, *) {
      content.containerBackground(for: .widget) {
        kboBackground
      }
    } else {
      content.background(kboBackground)
    }
  }

  @ViewBuilder
  private var widgetContent: some View {
    if #available(iOSApplicationExtension 16.0, *) {
      switch family {
      case .accessoryInline:
        accessoryInlineWidget
      case .accessoryCircular:
        accessoryCircularWidget
      case .accessoryRectangular:
        accessoryRectangularWidget
      default:
        systemWidget
      }
    } else {
      systemWidget
    }
  }

  @ViewBuilder
  private var systemWidget: some View {
    switch family {
    case .systemLarge:
      largeSlateWidget
    case .systemMedium:
      mediumScoreWidget
    default:
      smallScoreWidget
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

  private var smallScoreWidget: some View {
    VStack(alignment: .leading, spacing: 7) {
      headerRow
      Spacer(minLength: 4)
      HStack(alignment: .center, spacing: 8) {
        TeamLogoView(teamId: entry.awayTeamId, fallback: "A", size: 24)
        scoreText(entry.score, size: 27)
        TeamLogoView(teamId: entry.homeTeamId, fallback: "H", size: 24)
      }
      Text(statusOrSubtitle)
        .font(.system(size: 14, weight: .bold, design: .rounded))
        .foregroundStyle(statusColor)
        .lineLimit(1)
        .minimumScaleFactor(0.72)
      footerFreshness
    }
    .padding(14)
  }

  private var mediumScoreWidget: some View {
    HStack(alignment: .top, spacing: 14) {
      VStack(alignment: .leading, spacing: 7) {
        headerRow
        Spacer(minLength: 2)
        HStack(spacing: 9) {
          TeamLogoView(teamId: entry.awayTeamId, fallback: "A", size: 26)
          scoreText(entry.score, size: 30)
          TeamLogoView(teamId: entry.homeTeamId, fallback: "H", size: 26)
        }
        Text(statusOrSubtitle)
          .font(.system(size: 13, weight: .bold, design: .rounded))
          .foregroundStyle(statusColor)
          .lineLimit(1)
          .minimumScaleFactor(0.72)
        footerFreshness
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      Divider()
        .overlay(kboDivider)

      VStack(alignment: .leading, spacing: 7) {
        Text("다음 보기")
          .font(.system(size: 11, weight: .bold, design: .rounded))
          .foregroundStyle(kboTextSecondary)
        if entry.secondaryTitle.isEmpty {
          summaryRows(limit: 2)
        } else {
          Text(entry.secondaryTitle)
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.66)
          Text(entry.secondaryScore)
            .font(.system(size: 22, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.62)
          Text(entry.secondaryStatus)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(kboTextSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.66)
        }
        Spacer(minLength: 0)
      }
      .frame(width: 128, alignment: .leading)
    }
    .padding(14)
  }

  private var largeSlateWidget: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 3) {
          Text(entry.summaryTitle)
            .font(.system(size: 20, weight: .black, design: .rounded))
            .foregroundStyle(.white)
          Text(entry.liveCount > 0 ? "라이브 \(entry.liveCount) · 전체 \(entry.todayCount)" : "전체 \(entry.todayCount)")
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(kboTextSecondary)
        }
        Spacer(minLength: 8)
        footerFreshness
      }

      HStack(spacing: 10) {
        TeamLogoView(teamId: entry.awayTeamId, fallback: "A", size: 30)
        VStack(alignment: .leading, spacing: 2) {
          Text(entry.title)
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.66)
          Text(statusOrSubtitle)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(kboTextSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.66)
        }
        Spacer(minLength: 6)
        scoreText(entry.score, size: 28)
        TeamLogoView(teamId: entry.homeTeamId, fallback: "H", size: 30)
      }
      .padding(10)
      .background(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(kboCard)
      )

      summaryRows(limit: 4)
      Spacer(minLength: 0)
    }
    .padding(14)
  }

  @available(iOSApplicationExtension 16.0, *)
  private var accessoryInlineWidget: some View {
    Text(accessoryLine)
      .font(.caption.weight(.bold))
      .lineLimit(1)
      .minimumScaleFactor(0.62)
      .widgetAccentable()
  }

  @available(iOSApplicationExtension 16.0, *)
  private var accessoryCircularWidget: some View {
    VStack(spacing: 1) {
      Text(entry.statusKind == "live" ? "LIVE" : "KBO")
        .font(.system(size: 10, weight: .black, design: .rounded))
      Text(entry.score.isEmpty ? "vs" : entry.score.replacingOccurrences(of: " ", with: ""))
        .font(.system(size: 12, weight: .black, design: .rounded))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.5)
    }
    .widgetAccentable()
  }

  @available(iOSApplicationExtension 16.0, *)
  private var accessoryRectangularWidget: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(entry.title)
        .font(.system(size: 13, weight: .bold, design: .rounded))
        .lineLimit(1)
        .minimumScaleFactor(0.62)
      Text("\(entry.score.isEmpty ? entry.contextLabel : entry.score) · \(statusOrSubtitle)")
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .lineLimit(1)
        .minimumScaleFactor(0.58)
    }
    .widgetAccentable()
  }

  private var headerRow: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(entry.contextLabel)
        .font(.system(size: 11, weight: .bold, design: .rounded))
        .foregroundStyle(kboTextSecondary)
      Text(entry.title)
        .font(.system(size: 17, weight: .black, design: .rounded))
        .foregroundStyle(.white)
        .lineLimit(1)
        .minimumScaleFactor(0.62)
    }
  }

  private var footerFreshness: some View {
    Text(
      freshnessText(
        updatedAt: entry.updatedAt,
        updatedAtEpoch: entry.updatedAtEpoch,
        statusKind: entry.statusKind
      )
    )
    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
    .foregroundStyle(Color.white.opacity(0.46))
    .lineLimit(1)
    .minimumScaleFactor(0.7)
  }

  private var statusOrSubtitle: String {
    if !entry.status.isEmpty {
      return entry.status
    }
    return entry.subtitle.isEmpty ? entry.summaryTitle : entry.subtitle
  }

  private var statusColor: Color {
    entry.statusKind == "live" ? kboLive : kboTextSecondary
  }

  private var accessoryLine: String {
    let score = entry.score.isEmpty ? "" : "\(entry.score) · "
    return "\(entry.title) \(score)\(statusOrSubtitle)"
  }

  private func scoreText(_ text: String, size: CGFloat) -> some View {
    Text(text.isEmpty ? "vs" : text)
      .font(.system(size: text.count > 5 ? size - 4 : size, weight: .black, design: .rounded))
      .foregroundStyle(.white)
      .monospacedDigit()
      .lineLimit(1)
      .minimumScaleFactor(0.56)
      .allowsTightening(true)
      .layoutPriority(2)
  }

  private func summaryRows(limit: Int) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      ForEach(Array(entry.summaryLines.prefix(limit).enumerated()), id: \.offset) { index, line in
        HStack(spacing: 7) {
          Text("\(index + 1)")
            .font(.system(size: 10, weight: .black, design: .rounded))
            .foregroundStyle(kboTextSecondary)
            .frame(width: 14)
          Text(line)
            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
            .foregroundStyle(index == 0 ? .white : kboTextSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.62)
        }
      }
      if entry.summaryLines.isEmpty {
        Text("오늘 표시할 경기가 없습니다")
          .font(.system(size: 12.5, weight: .semibold, design: .rounded))
          .foregroundStyle(kboTextSecondary)
          .lineLimit(1)
          .minimumScaleFactor(0.62)
      }
    }
  }
}

struct KboFansWidget: Widget {
  let kind: String = "KboFansWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: KboFansWidgetProvider()) { entry in
      KboFansWidgetEntryView(entry: entry)
    }
    .configurationDisplayName("KBO Fans 경기판")
    .description("마이팀, 현재 경기, 오늘 경기 목록을 크기별로 확인합니다.")
    .supportedFamilies(kboSupportedWidgetFamilies())
  }
}

private func kboSupportedWidgetFamilies() -> [WidgetFamily] {
  if #available(iOSApplicationExtension 16.0, *) {
    return [
      .systemSmall,
      .systemMedium,
      .systemLarge,
      .accessoryInline,
      .accessoryCircular,
      .accessoryRectangular,
    ]
  }
  return [.systemSmall, .systemMedium, .systemLarge]
}

@available(iOS 16.1, *)
struct KboFansLiveActivityView: View {
  let context: ActivityViewContext<KboFansScoreAttributes>

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 28, style: .continuous)
        .fill(cardGradient)
      RoundedRectangle(cornerRadius: 28, style: .continuous)
        .stroke(Color.white.opacity(0.12), lineWidth: 1)

      VStack(spacing: 7) {
        HStack(alignment: .center, spacing: 8) {
          LiveActivityTeamPanel(
            team: displayTeamName(
              teamId: context.state.awayTeamId,
              team: context.state.awayTeam
            ),
            alignment: .trailing,
            frameAlignment: .trailing
          )
          .frame(width: 60, alignment: .trailing)

          VStack(spacing: 5) {
            HStack(alignment: .center, spacing: 8) {
              if isPregame {
                rankView(rankText(context.state.awayRankText))
                Text("VS")
                  .font(.system(size: 17, weight: .black, design: .rounded))
                  .foregroundStyle(.white.opacity(0.66))
                  .frame(width: 68, height: 46)
                rankView(rankText(context.state.homeRankText))
              } else {
                scoreView(context.state.awayScore)
                BaseballDiamondView(occupiedBases: occupiedBases)
                  .frame(width: 68, height: 46)
                scoreView(context.state.homeScore)
              }
            }

            HStack(spacing: 8) {
              Text(statusText)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                  Capsule()
                    .fill(Color.white.opacity(0.22))
                )

              if hasAtBatContext {
                CountDotsRow(
                  balls: context.state.balls,
                  strikes: context.state.strikes,
                  outs: context.state.outs
                )
                .scaleEffect(0.88)
              }
            }
            .frame(maxWidth: .infinity)
          }
          .frame(minWidth: 166, maxWidth: 184)
          .padding(.top, 3)

          LiveActivityTeamPanel(
            team: displayTeamName(
              teamId: context.state.homeTeamId,
              team: context.state.homeTeam
            ),
            alignment: .leading,
            frameAlignment: .leading
          )
          .frame(width: 60, alignment: .leading)
        }

        if !isPregame && hasMatchupContext {
          LiveActivityMatchupRow(
            batter: batterName,
            batterDetail: batterDetailText,
            pitcher: pitcherName,
            pitcherDetail: pitcherDetailText,
            isHomeBatting: isHomeBatting
          )
        }

        if !bottomSituationText.isEmpty {
          Text(bottomSituationText)
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.9))
            .lineLimit(2)
            .minimumScaleFactor(0.68)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
            .background(
              Capsule()
                .fill(Color.white.opacity(0.11))
            )
        }
      }
      .padding(.horizontal, 14)
      .padding(.top, 15)
      .padding(.bottom, 9)
    }
    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    .activityBackgroundTint(Color.clear)
    .activitySystemActionForegroundColor(.white)
    .widgetURL(
      launchURL(
        gameId: context.attributes.gameId,
        tab: isPregame ? "lineup" : "relay"
      )
    )
  }

  private var statusText: String {
    if isPregame {
      return "경기전"
    }
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
    let scoreText = "\(score)"
    let fontSize: CGFloat = scoreText.count > 1 ? 34 : 38
    return Text(scoreText)
      .font(.system(size: fontSize, weight: .black, design: .rounded))
      .foregroundStyle(.white)
      .monospacedDigit()
      .lineLimit(1)
      .minimumScaleFactor(0.58)
      .allowsTightening(true)
      .frame(width: 46, alignment: .center)
      .layoutPriority(2)
  }

  private func rankView(_ text: String) -> some View {
    Text(text)
      .font(.system(size: 27, weight: .black, design: .rounded))
      .foregroundStyle(.white)
      .lineLimit(1)
      .minimumScaleFactor(0.68)
      .frame(width: 46)
  }

  private var batterName: String {
    let batter = trimmed(context.state.batter)
    return batter.isEmpty ? "타자" : batter
  }

  private var batterDetailText: String {
    let average = trimmed(context.state.batterAverage)
    return average.isEmpty ? "" : "타율 \(average)"
  }

  private var pitcherName: String {
    let pitcher = trimmed(context.state.pitcher)
    return pitcher.isEmpty ? "투수" : pitcher
  }

  private var pitcherDetailText: String {
    let era = trimmed(context.state.pitcherEra)
    if context.state.pitchCount > 0 {
      if !era.isEmpty {
        return "ERA \(era) · \(context.state.pitchCount)구"
      }
      return "\(context.state.pitchCount)구"
    }
    return era.isEmpty ? "" : "ERA \(era)"
  }

  private var bottomSituationText: String {
    if isPregame {
      let stadium = trimmed(context.state.stadium)
      return stadium.isEmpty ? "라인업 공개" : "\(stadium) · 라인업 공개"
    }
    let play = cleanedPlayText(context.state.playText)
    if !play.isEmpty {
      return play
    }
    let situation = trimmed(context.state.situationText)
    if !situation.isEmpty {
      return situation
    }
    let stadium = trimmed(context.state.stadium)
    if hasMatchupContext {
      return stadium
    }
    let batter = trimmed(context.state.batter)
    if !batter.isEmpty {
      return "\(batter) 타석"
    }
    return stadium.isEmpty ? "KBO 경기" : stadium
  }

  private var occupiedBases: Set<Int> {
    occupiedBasesFromText(context.state.situationText)
  }

  private var isHomeBatting: Bool {
    inningHalf(context.state.inning) == .bottom
  }

  private var hasMatchupContext: Bool {
    !context.state.batter.isEmpty ||
      !context.state.pitcher.isEmpty
  }

  private var hasAtBatContext: Bool {
    !isPregame && (
      hasMatchupContext ||
      context.state.pitchCount > 0 ||
      context.state.balls > 0 ||
      context.state.strikes > 0 ||
      context.state.outs > 0
    )
  }

  private var isPregame: Bool {
    context.state.isPregame == true
  }
}

private struct LiveActivityTeamPanel: View {
  let team: String
  let alignment: HorizontalAlignment
  let frameAlignment: Alignment

  var body: some View {
    VStack(alignment: alignment, spacing: 2) {
      Text(team)
        .font(.system(size: 23, weight: .black, design: .rounded))
        .foregroundStyle(.white)
        .lineLimit(1)
        .minimumScaleFactor(0.58)
    }
    .frame(maxWidth: .infinity, alignment: frameAlignment)
  }
}

private struct LiveActivityMatchupRow: View {
  let batter: String
  let batterDetail: String
  let pitcher: String
  let pitcherDetail: String
  let isHomeBatting: Bool

  var body: some View {
    HStack(spacing: 7) {
      if isHomeBatting {
        pitcherChip(alignment: .trailing)
      } else {
        batterChip(alignment: .trailing)
      }

      Rectangle()
        .fill(Color.white.opacity(0.18))
        .frame(width: 1, height: 20)

      if isHomeBatting {
        batterChip(alignment: .leading)
      } else {
        pitcherChip(alignment: .leading)
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.horizontal, 9)
    .padding(.vertical, 5)
    .background(
      Capsule()
        .fill(Color.black.opacity(0.18))
    )
  }

  private func batterChip(alignment: Alignment) -> some View {
    MatchupPlayerChip(
      role: "타자",
      name: batter,
      detail: batterDetail,
      alignment: alignment
    )
  }

  private func pitcherChip(alignment: Alignment) -> some View {
    MatchupPlayerChip(
      role: "투수",
      name: pitcher,
      detail: pitcherDetail,
      alignment: alignment
    )
  }
}

private struct MatchupPlayerChip: View {
  let role: String
  let name: String
  let detail: String
  let alignment: Alignment

  var body: some View {
    VStack(spacing: 1) {
      HStack(spacing: 4) {
        Text(role)
          .font(.system(size: 10, weight: .bold, design: .rounded))
          .foregroundStyle(.white.opacity(0.54))
          .fixedSize(horizontal: true, vertical: false)
        Text(name)
          .font(.system(size: 14, weight: .semibold, design: .rounded))
          .foregroundStyle(.white.opacity(0.94))
          .lineLimit(1)
          .minimumScaleFactor(0.62)
          .allowsTightening(true)
      }
      .frame(maxWidth: .infinity, alignment: alignment)

      if !detail.isEmpty {
        Text(detail)
          .font(.system(size: 10.5, weight: .medium, design: .rounded))
          .foregroundStyle(.white.opacity(0.72))
          .monospacedDigit()
          .lineLimit(1)
          .minimumScaleFactor(0.58)
          .allowsTightening(true)
          .frame(maxWidth: .infinity, alignment: alignment)
      }
    }
    .frame(maxWidth: .infinity, minHeight: detail.isEmpty ? 18 : 31, alignment: alignment)
    .layoutPriority(2)
  }
}

private struct BaseballDiamondView: View {
  let occupiedBases: Set<Int>

  var body: some View {
    ZStack {
      base(index: 2)
        .offset(x: 0, y: -7)
      base(index: 3)
        .offset(x: -20, y: 6)
      base(index: 1)
        .offset(x: 20, y: 6)
    }
  }

  private func base(index: Int) -> some View {
    RoundedRectangle(cornerRadius: 5, style: .continuous)
      .fill(occupiedBases.contains(index) ? Color.white : Color.clear)
      .overlay(
        RoundedRectangle(cornerRadius: 5, style: .continuous)
          .stroke(Color.white, lineWidth: 2)
      )
      .frame(width: 25, height: 25)
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
    HStack(spacing: 9) {
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
    HStack(spacing: 4) {
      Text(label)
        .font(.system(size: 14, weight: .black, design: .rounded))
        .foregroundStyle(.white)
      ForEach(0..<max, id: \.self) { index in
        Circle()
          .fill(index < clampedValue ? color : Color.white.opacity(0.38))
          .frame(width: 7, height: 7)
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
  let metric: String
  let alignEnd: Bool

  var body: some View {
    VStack(alignment: alignEnd ? .trailing : .leading, spacing: 2) {
      teamName
      Text(metric)
        .font(
          .system(
            size: metric.count > 2 ? 20 : 24,
            weight: .black,
            design: .rounded
          )
        )
        .foregroundStyle(.white)
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.58)
        .allowsTightening(true)
        .frame(minWidth: 28, maxWidth: 48, alignment: alignEnd ? .trailing : .leading)
        .layoutPriority(2)
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
  if state.isPregame == true {
    let stadium = trimmed(state.stadium)
    return stadium.isEmpty ? "라인업 공개" : "\(stadium) · 라인업 공개"
  }
  let play = cleanedPlayText(state.playText)
  if !play.isEmpty {
    return play
  }
  let situation = trimmed(state.situationText)
  if !situation.isEmpty {
    return situation
  }
  let stadium = trimmed(state.stadium)
  if hasMatchupContext(state) {
    return stadium
  }
  let batter = trimmed(state.batter)
  if !batter.isEmpty {
    return "\(batter) 타석"
  }
  return stadium.isEmpty ? "KBO 경기" : stadium
}

private func dynamicIslandMatchupText(_ state: KboFansScoreAttributes.ContentState) -> String {
  let batter = trimmed(state.batter)
  let pitcher = trimmed(state.pitcher)
  let pitcherText: String
  if pitcher.isEmpty {
    pitcherText = ""
  } else if state.pitchCount > 0 {
    pitcherText = "투수 \(pitcher) \(state.pitchCount)구"
  } else {
    pitcherText = "투수 \(pitcher)"
  }

  let batterText = batter.isEmpty ? "" : "타자 \(batter)"
  let ordered = inningHalf(state.inning) == .bottom
    ? [pitcherText, batterText]
    : [batterText, pitcherText]

  return ordered.filter { !$0.isEmpty }.joined(separator: " · ")
}

private func hasMatchupContext(_ state: KboFansScoreAttributes.ContentState) -> Bool {
  if state.isPregame == true {
    return false
  }
  return !state.batter.isEmpty || !state.pitcher.isEmpty
}

private enum InningHalf {
  case top
  case bottom
  case unknown
}

private func inningHalf(_ text: String?) -> InningHalf {
  let source = trimmed(text).lowercased()
  if source.contains("말") || source.contains("bottom") {
    return .bottom
  }
  if source.contains("초") || source.contains("top") {
    return .top
  }
  return .unknown
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
  let normalized = source.replacingOccurrences(of: " ", with: "")
  if normalized.isEmpty || normalized.contains("주자없음") {
    return []
  }
  if normalized.contains("만루") {
    return [1, 2, 3]
  }

  var bases = Set<Int>()
  if normalized.contains("1루") || normalized.contains("1,") {
    bases.insert(1)
  }
  if normalized.contains("2루") || normalized.contains(",2") || normalized.contains("2,") {
    bases.insert(2)
  }
  if normalized.contains("3루") || normalized.contains(",3") {
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

private func rankText(_ text: String?) -> String {
  let value = trimmed(text)
  return value.isEmpty ? "-" : value
}

private func teamMetricText(score: Int, rankText text: String?, isPregame: Bool) -> String {
  return isPregame ? rankText(text) : "\(score)"
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
            metric: teamMetricText(
              score: context.state.awayScore,
              rankText: context.state.awayRankText,
              isPregame: context.state.isPregame == true
            ),
            alignEnd: false
          )
        }
        DynamicIslandExpandedRegion(.center) {
          VStack(spacing: 3) {
            if context.state.isPregame != true {
              BaseballDiamondView(
                occupiedBases: occupiedBasesFromText(context.state.situationText)
              )
              .frame(width: 46, height: 30)
              .scaleEffect(0.58)
            }
            Text(context.state.isPregame == true ? "경기전" : context.state.inning)
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
            metric: teamMetricText(
              score: context.state.homeScore,
              rankText: context.state.homeRankText,
              isPregame: context.state.isPregame == true
            ),
            alignEnd: true
          )
        }
        DynamicIslandExpandedRegion(.bottom) {
          VStack(spacing: 5) {
            if context.state.isPregame != true && hasAtBatContext(context.state) {
              CountDotsRow(
                balls: context.state.balls,
                strikes: context.state.strikes,
                outs: context.state.outs
              )
              .scaleEffect(0.92)
            }

            if hasMatchupContext(context.state) {
              Text(dynamicIslandMatchupText(context.state))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(2)
                .minimumScaleFactor(0.62)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .padding(.horizontal, 10)
                .background(
                  Capsule()
                    .fill(Color.white.opacity(0.12))
                )
            }

            if !dynamicIslandSituationText(context.state).isEmpty {
              Text(dynamicIslandSituationText(context.state))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(kboTextSecondary)
                .lineLimit(2)
                .minimumScaleFactor(0.66)
                .multilineTextAlignment(.center)
            }
          }
        }
      } compactLeading: {
        compactMetricView(
          teamMetricText(
            score: context.state.awayScore,
            rankText: context.state.awayRankText,
            isPregame: context.state.isPregame == true
          ),
          alignment: .leading
        )
      } compactTrailing: {
        compactMetricView(
          teamMetricText(
            score: context.state.homeScore,
            rankText: context.state.homeRankText,
            isPregame: context.state.isPregame == true
          ),
          alignment: .trailing
        )
      } minimal: {
        Text(
          context.state.isPregame == true
            ? "경기전"
            : "\(context.state.awayScore):\(context.state.homeScore)"
        )
          .font(.system(size: 11, weight: .bold, design: .rounded))
          .foregroundStyle(.white)
          .monospacedDigit()
          .lineLimit(1)
          .minimumScaleFactor(0.55)
          .allowsTightening(true)
      }
      .keylineTint(teamAccentColor(teamId: context.state.homeTeamId))
      .widgetURL(
        launchURL(
          gameId: context.attributes.gameId,
          tab: context.state.isPregame == true ? "lineup" : "relay"
        )
      )
    }
  }

  private func hasAtBatContext(_ state: KboFansScoreAttributes.ContentState) -> Bool {
    if state.isPregame == true {
      return false
    }
    return hasMatchupContext(state) ||
      state.pitchCount > 0 ||
      state.balls > 0 ||
      state.strikes > 0 ||
      state.outs > 0
  }

  private func compactMetricView(_ text: String, alignment: Alignment) -> some View {
    Text(text)
      .font(
        .system(
          size: text.count > 2 ? 15 : 17,
          weight: .black,
          design: .rounded
        )
      )
      .foregroundStyle(.white)
      .monospacedDigit()
      .lineLimit(1)
      .minimumScaleFactor(0.58)
      .allowsTightening(true)
      .frame(minWidth: 22, maxWidth: 34, alignment: alignment)
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
