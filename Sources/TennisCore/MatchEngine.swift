import Foundation

public struct MatchState: Equatable, Sendable {
    public let rules: MatchRules
    public private(set) var completedSets: [SetResult] = []
    public private(set) var games = ScorePair()
    public private(set) var points = ScorePair()
    private var gameServer: Player

    public init(rules: MatchRules = MatchRules(), firstServer: Player = .me) {
        self.rules = rules
        gameServer = firstServer
    }

    public var sets: ScorePair {
        ScorePair(
            me: completedSets.filter { $0.winner == .me }.count,
            opponent: completedSets.filter { $0.winner == .opponent }.count
        )
    }

    public var winner: Player? {
        if sets.me == rules.setsToWin.rawValue { return .me }
        if sets.opponent == rules.setsToWin.rawValue { return .opponent }
        return nil
    }

    public var isSuperTieBreak: Bool {
        winner == nil && rules.decidingSet == .superTieBreak &&
        sets.me == rules.setsToWin.rawValue - 1 &&
        sets.opponent == rules.setsToWin.rawValue - 1
    }

    public var isTieBreak: Bool {
        winner == nil && (isSuperTieBreak || (games.me == 6 && games.opponent == 6))
    }

    public var server: Player {
        guard isTieBreak else { return gameServer }
        // First server: one point, then two points per player, alternating.
        return ((points.me + points.opponent + 1) / 2).isMultiple(of: 2)
            ? gameServer : gameServer.other
    }

    public func pointLabel(for player: Player) -> String {
        if isTieBreak { return String(points[player]) }
        if points[player] >= 3 && points[player.other] >= 3 {
            return points[player] > points[player.other] ? "AV" : "40"
        }
        return ["0", "15", "30", "40"][min(points[player], 3)]
    }

    public mutating func awardPoint(to player: Player) throws {
        guard winner == nil else { throw MatchError.matchFinished }
        let wasTieBreak = isTieBreak
        let wasSuperTieBreak = isSuperTieBreak
        points[player] += 1

        if wasTieBreak {
            let target = wasSuperTieBreak ? 10 : 7
            guard points[player] >= target && points[player] - points[player.other] >= 2 else { return }
            let result = SetResult(
                score: wasSuperTieBreak ? points : ScorePair(
                    me: player == .me ? 7 : 6, opponent: player == .opponent ? 7 : 6
                ),
                tieBreakPoints: points, isSuperTieBreak: wasSuperTieBreak
            )
            completedSets.append(result)
            // The player who served first in this tie-break receives next set.
            gameServer = gameServer.other
            games = ScorePair()
            points = ScorePair()
            return
        }

        let wonGame = points[player] >= 4 &&
            (!rules.usesAdvantages || points[player] - points[player.other] >= 2)
        guard wonGame else { return }
        games[player] += 1
        points = ScorePair()
        gameServer = gameServer.other
        if games[player] >= 6 && games[player] - games[player.other] >= 2 {
            completedSets.append(SetResult(score: games, tieBreakPoints: nil, isSuperTieBreak: false))
            games = ScorePair()
        }
    }
}

public enum MatchEngine {
    public static func replay(
        rules: MatchRules, firstServer: Player, points: [Player]
    ) throws -> MatchState {
        var state = MatchState(rules: rules, firstServer: firstServer)
        for point in points { try state.awardPoint(to: point) }
        return state
    }
}
