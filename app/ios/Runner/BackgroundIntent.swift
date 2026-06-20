import ActivityKit
import Foundation

struct KboFansScoreAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable {
    var awayTeamId: String
    var awayTeam: String
    var homeTeamId: String
    var homeTeam: String
    var awayScore: Int
    var homeScore: Int
    var inning: String
    var batter: String
    var batterAverage: String?
    var pitcher: String
    var pitcherEra: String?
    var pitchCount: Int
    var balls: Int
    var strikes: Int
    var outs: Int
    var stadium: String
    var updatedAt: String
    var situationText: String?
    var playText: String?
  }

  var gameId: String
}
