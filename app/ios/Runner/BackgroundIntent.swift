import ActivityKit
import Foundation

struct KboFansScoreAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable {
    var awayTeam: String
    var homeTeam: String
    var awayScore: Int
    var homeScore: Int
    var inning: String
    var batter: String
    var pitcher: String
    var balls: Int
    var strikes: Int
    var outs: Int
    var stadium: String
    var updatedAt: String
  }

  var gameId: String
}
