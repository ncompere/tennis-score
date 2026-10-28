import XCTest
@testable import TennisCore

final class MatchEngineTests: XCTestCase {
    private func winGame(_ player: Player, in state: inout MatchState) throws {
        for _ in 0..<4 { try state.awardPoint(to: player) }
    }

    private func reachTieBreak(in state: inout MatchState) throws {
        for _ in 0..<6 {
            try winGame(.me, in: &state)
            try winGame(.opponent, in: &state)
        }
    }

    func testPointLabelsGameAndServer() throws {
        var state = MatchState(firstServer: .opponent)
        for expected in ["15", "30", "40"] {
            try state.awardPoint(to: .me)
            XCTAssertEqual(state.pointLabel(for: .me), expected)
            XCTAssertEqual(state.server, .opponent)
        }
        try state.awardPoint(to: .me)
        XCTAssertEqual(state.games, ScorePair(me: 1))
        XCTAssertEqual(state.pointLabel(for: .me), "0")
        XCTAssertEqual(state.server, .me)
    }

    func testRepeatedDeuceAndAdvantages() throws {
        var state = MatchState()
        for _ in 0..<3 {
            try state.awardPoint(to: .me)
            try state.awardPoint(to: .opponent)
        }
        for _ in 0..<10 {
            try state.awardPoint(to: .me)
            XCTAssertEqual(state.pointLabel(for: .me), "AV")
            XCTAssertEqual(state.pointLabel(for: .opponent), "40")
            try state.awardPoint(to: .opponent)
            XCTAssertEqual(state.pointLabel(for: .me), "40")
            XCTAssertEqual(state.games, ScorePair())
        }
        try state.awardPoint(to: .opponent)
        try state.awardPoint(to: .opponent)
        XCTAssertEqual(state.games.opponent, 1)
    }

    func testNoAdEndsOnSeventhPoint() throws {
        var state = MatchState(rules: MatchRules(usesAdvantages: false))
        for _ in 0..<3 {
            try state.awardPoint(to: .me)
            try state.awardPoint(to: .opponent)
        }
        XCTAssertEqual(state.pointLabel(for: .me), "40")
        try state.awardPoint(to: .opponent)
        XCTAssertEqual(state.games.opponent, 1)
        XCTAssertEqual(state.points, ScorePair())
    }

    func testSixLoveCompletesOneSetMatchAndRejectsExtraPoint() throws {
        var state = MatchState(rules: MatchRules(setsToWin: .one))
        for _ in 0..<6 { try winGame(.me, in: &state) }
        XCTAssertEqual(state.completedSets.first?.score, ScorePair(me: 6))
        XCTAssertEqual(state.winner, .me)
        let finished = state
        XCTAssertThrowsError(try state.awardPoint(to: .opponent)) {
            XCTAssertEqual($0 as? MatchError, .matchFinished)
        }
        XCTAssertEqual(state, finished)
    }

    func testSevenFiveAndServiceAcrossOddLengthSet() throws {
        var state = MatchState(firstServer: .opponent)
        for _ in 0..<5 {
            try winGame(.me, in: &state)
            try winGame(.opponent, in: &state)
        }
        try winGame(.me, in: &state)
        XCTAssertTrue(state.completedSets.isEmpty)
        try winGame(.me, in: &state)
        XCTAssertEqual(state.completedSets.first?.score, ScorePair(me: 7, opponent: 5))
        XCTAssertEqual(state.server, .opponent)

        var odd = MatchState(firstServer: .me)
        try winGame(.opponent, in: &odd)
        for _ in 0..<6 { try winGame(.me, in: &odd) }
        XCTAssertEqual(odd.completedSets.first?.score, ScorePair(me: 6, opponent: 1))
        XCTAssertEqual(odd.server, .opponent)
    }

    func testTieBreakServiceSequenceAndSevenSixSet() throws {
        for initialServer in Player.allCases {
            var state = MatchState(firstServer: initialServer)
            try reachTieBreak(in: &state)
            XCTAssertTrue(state.isTieBreak)
            let expectedServers: [Player] = [
                initialServer, initialServer.other, initialServer.other,
                initialServer, initialServer, initialServer.other, initialServer.other
            ]
            for expected in expectedServers {
                XCTAssertEqual(state.server, expected)
                try state.awardPoint(to: .me)
            }
            XCTAssertEqual(state.completedSets.first?.score, ScorePair(me: 7, opponent: 6))
            XCTAssertEqual(state.completedSets.first?.tieBreakPoints, ScorePair(me: 7))
            XCTAssertEqual(state.server, initialServer.other)
            XCTAssertFalse(state.isTieBreak)
        }
    }

    func testExtendedTieBreakRequiresTwoPointMargin() throws {
        var state = MatchState()
        try reachTieBreak(in: &state)
        for _ in 0..<12 {
            try state.awardPoint(to: .me)
            try state.awardPoint(to: .opponent)
        }
        try state.awardPoint(to: .opponent)
        XCTAssertEqual(state.pointLabel(for: .opponent), "13")
        XCTAssertTrue(state.completedSets.isEmpty)
        try state.awardPoint(to: .opponent)
        XCTAssertEqual(state.completedSets.first?.tieBreakPoints, ScorePair(me: 12, opponent: 14))
    }

    func testSuperTieBreakOnlyReplacesDecidingSetAndKeepsServiceOrder() throws {
        for target in [SetsToWin.two, .three] {
            var state = MatchState(rules: MatchRules(setsToWin: target, decidingSet: .superTieBreak))
            XCTAssertFalse(state.isSuperTieBreak)
            for _ in 0..<(target.rawValue - 1) {
                for _ in 0..<6 { try winGame(.me, in: &state) }
                XCTAssertFalse(state.isSuperTieBreak)
                for _ in 0..<6 { try winGame(.opponent, in: &state) }
            }
            XCTAssertTrue(state.isSuperTieBreak)
            XCTAssertEqual(state.server, .me)
            try state.awardPoint(to: .opponent)
            XCTAssertEqual(state.server, .opponent)
            for _ in 0..<9 { try state.awardPoint(to: .me) }
            for _ in 0..<8 { try state.awardPoint(to: .opponent) }
            try state.awardPoint(to: .me) // 10–9: not finished
            XCTAssertNil(state.winner)
            try state.awardPoint(to: .me)
            XCTAssertEqual(state.winner, .me)
            XCTAssertEqual(state.completedSets.last?.score, ScorePair(me: 11, opponent: 9))
            XCTAssertEqual(state.completedSets.last?.isSuperTieBreak, true)
        }
    }

    func testStraightSetsDoesNotStartSuperTieBreak() throws {
        var state = MatchState(rules: MatchRules(decidingSet: .superTieBreak))
        for _ in 0..<12 { try winGame(.opponent, in: &state) }
        XCTAssertEqual(state.winner, .opponent)
        XCTAssertFalse(state.isSuperTieBreak)
        XCTAssertEqual(state.completedSets.count, 2)
    }

    func testSingleSetDisablesSuperTieBreak() {
        let rules = MatchRules(setsToWin: .one, decidingSet: .superTieBreak)
        XCTAssertEqual(rules.decidingSet, .standard)
        XCTAssertFalse(MatchState(rules: rules).isSuperTieBreak)
    }

    func testReplayAfterUndoAtGameSetAndMatchBoundaries() throws {
        let rules = MatchRules(setsToWin: .one)
        for count in [4, 24] {
            let points = Array(repeating: Player.me, count: count)
            let full = try MatchEngine.replay(rules: rules, firstServer: .opponent, points: points)
            var undone = try MatchEngine.replay(rules: rules, firstServer: .opponent, points: Array(points.dropLast()))
            XCTAssertNil(undone.winner)
            XCTAssertEqual(undone.pointLabel(for: .me), "40")
            try undone.awardPoint(to: .me)
            XCTAssertEqual(undone, full)
        }
    }

    func testReplayUndoTieBreakWinningPointRestoresServerAndPoints() throws {
        var points: [Player] = []
        for _ in 0..<6 {
            points += Array(repeating: .me, count: 4)
            points += Array(repeating: .opponent, count: 4)
        }
        points += Array(repeating: .opponent, count: 7)
        let full = try MatchEngine.replay(rules: MatchRules(), firstServer: .me, points: points)
        var undone = try MatchEngine.replay(rules: MatchRules(), firstServer: .me, points: Array(points.dropLast()))
        XCTAssertTrue(undone.isTieBreak)
        XCTAssertEqual(undone.points.opponent, 6)
        XCTAssertEqual(undone.server, .opponent)
        try undone.awardPoint(to: .opponent)
        XCTAssertEqual(undone, full)
    }
}
