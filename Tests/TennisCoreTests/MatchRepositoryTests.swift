import XCTest
@testable import TennisCore

private final class MemoryStorage: MatchStorage {
    var data: Data?
    var failsReading = false
    var failsWriting = false

    func load() throws -> Data? {
        if failsReading { throw CocoaError(.fileReadNoPermission) }
        return data
    }

    func save(_ data: Data) throws {
        if failsWriting { throw CocoaError(.fileWriteOutOfSpace) }
        self.data = data
    }
}

final class MatchRepositoryTests: XCTestCase {
    private func finish(_ repository: MatchRepository) throws {
        for _ in 0..<24 { try repository.awardPoint(to: .me) }
    }

    func testNewLibraryAndResumeExactMatchAfterReload() throws {
        let storage = MemoryStorage()
        let repository = try MatchRepository(storage: storage)
        XCTAssertNil(repository.library.currentMatch)
        let id = try repository.start(firstServer: .opponent)
        for player in [Player.me, .opponent, .me, .me] { try repository.awardPoint(to: player) }
        let reloaded = try MatchRepository(storage: storage)
        XCTAssertEqual(reloaded.library.currentMatch?.id, id)
        XCTAssertEqual(try reloaded.library.currentMatch?.state(), try repository.library.currentMatch?.state())
        XCTAssertEqual(reloaded.library.currentMatch?.points, [.me, .opponent, .me, .me])
    }

    func testCannotStartSecondActiveMatch() throws {
        let repository = try MatchRepository(storage: MemoryStorage())
        let first = try repository.start()
        XCTAssertThrowsError(try repository.start()) {
            XCTAssertEqual($0 as? MatchError, .currentMatchExists)
        }
        XCTAssertEqual(repository.library.currentMatch?.id, first)
    }

    func testUndoIsPersistedAndEmptyUndoDoesNotChangeState() throws {
        let storage = MemoryStorage()
        let repository = try MatchRepository(storage: storage)
        try repository.start()
        let initialData = storage.data
        XCTAssertThrowsError(try repository.undoCurrentPoint())
        XCTAssertEqual(initialData, storage.data)
        for _ in 0..<4 { try repository.awardPoint(to: .me) }
        try repository.undoCurrentPoint()
        let reloaded = try MatchRepository(storage: storage)
        let state = try XCTUnwrap(reloaded.library.currentMatch).state()
        XCTAssertEqual(state.games.me, 0)
        XCTAssertEqual(state.pointLabel(for: .me), "40")
        XCTAssertEqual(state.server, .me)
    }

    func testFinishUndoAndFinishAgainNeverDuplicatesHistory() throws {
        let storage = MemoryStorage()
        var repository = try MatchRepository(storage: storage)
        let id = try repository.start(rules: MatchRules(setsToWin: .one))
        try finish(repository)
        XCTAssertNil(repository.library.currentMatch)
        XCTAssertEqual(repository.library.history.count, 1)
        repository = try MatchRepository(storage: storage)
        try repository.undoCompletedMatch(id: id)
        XCTAssertEqual(repository.library.currentMatch?.id, id)
        XCTAssertTrue(repository.library.history.isEmpty)
        XCTAssertNil(repository.library.currentMatch?.completedAt)
        repository = try MatchRepository(storage: storage)
        try repository.awardPoint(to: .me)
        XCTAssertEqual(repository.library.history.map(\.id), [id])
    }

    func testInterruptedMatchRetainsScoreAndCannotBeReopened() throws {
        let storage = MemoryStorage()
        let repository = try MatchRepository(storage: storage)
        let id = try repository.start()
        try repository.awardPoint(to: .opponent)
        try repository.interruptCurrentMatch()
        let record = try XCTUnwrap(try MatchRepository(storage: storage).library.history.first)
        XCTAssertNil(repository.library.currentMatch)
        XCTAssertEqual(record.points, [.opponent])
        XCTAssertNotNil(record.interruptedAt)
        XCTAssertNil(record.completedAt)
        XCTAssertThrowsError(try repository.undoCompletedMatch(id: id))
    }

    func testReopeningCannotReplaceAnotherActiveMatch() throws {
        let repository = try MatchRepository(storage: MemoryStorage())
        let id = try repository.start(rules: MatchRules(setsToWin: .one))
        try finish(repository)
        let activeID = try repository.start()
        XCTAssertThrowsError(try repository.undoCompletedMatch(id: id))
        XCTAssertEqual(repository.library.currentMatch?.id, activeID)
        XCTAssertEqual(repository.library.history.count, 1)
    }

    func testHistorySortedNewestFirstAndDeletePersists() throws {
        let storage = MemoryStorage()
        let repository = try MatchRepository(storage: storage)
        let early = Date(timeIntervalSince1970: 100)
        let later = Date(timeIntervalSince1970: 200)
        let oldID = try repository.start(at: early)
        try repository.interruptCurrentMatch(at: early)
        let newID = try repository.start(at: later)
        try repository.interruptCurrentMatch(at: later)
        XCTAssertEqual(repository.library.sortedHistory.map(\.id), [newID, oldID])
        try repository.deleteHistory(id: newID)
        XCTAssertEqual(try MatchRepository(storage: storage).library.history.map(\.id), [oldID])
    }

    func testWriteFailureDoesNotAcceptPointOrChangeDisk() throws {
        let storage = MemoryStorage()
        let repository = try MatchRepository(storage: storage)
        try repository.start()
        let before = repository.library
        let disk = storage.data
        storage.failsWriting = true
        XCTAssertThrowsError(try repository.awardPoint(to: .me))
        XCTAssertEqual(repository.library, before)
        XCTAssertEqual(storage.data, disk)
        storage.failsWriting = false
        try repository.awardPoint(to: .me)
        XCTAssertEqual(repository.library.currentMatch?.points, [.me])
    }

    func testFailedFinalPointAndUndoAreAtomic() throws {
        let storage = MemoryStorage()
        let repository = try MatchRepository(storage: storage)
        let id = try repository.start(rules: MatchRules(setsToWin: .one))
        for _ in 0..<23 { try repository.awardPoint(to: .me) }
        storage.failsWriting = true
        XCTAssertThrowsError(try repository.awardPoint(to: .me))
        XCTAssertNotNil(repository.library.currentMatch)
        XCTAssertTrue(repository.library.history.isEmpty)
        storage.failsWriting = false
        try repository.awardPoint(to: .me)
        storage.failsWriting = true
        XCTAssertThrowsError(try repository.undoCompletedMatch(id: id))
        XCTAssertNil(repository.library.currentMatch)
        XCTAssertEqual(repository.library.history.map(\.id), [id])
    }

    func testFailedStartInterruptAndDeleteLeaveLibraryIntact() throws {
        let storage = MemoryStorage()
        let repository = try MatchRepository(storage: storage)
        storage.failsWriting = true
        XCTAssertThrowsError(try repository.start())
        XCTAssertNil(repository.library.currentMatch)
        storage.failsWriting = false
        let id = try repository.start()
        storage.failsWriting = true
        XCTAssertThrowsError(try repository.interruptCurrentMatch())
        XCTAssertEqual(repository.library.currentMatch?.id, id)
        XCTAssertTrue(repository.library.history.isEmpty)
        storage.failsWriting = false
        try repository.interruptCurrentMatch()
        storage.failsWriting = true
        XCTAssertThrowsError(try repository.deleteHistory(id: id))
        XCTAssertEqual(repository.library.history.map(\.id), [id])
    }

    func testUnreadableOrCorruptDataIsNotSilentlyReplaced() throws {
        let storage = MemoryStorage()
        storage.failsReading = true
        XCTAssertThrowsError(try MatchRepository(storage: storage))
        storage.failsReading = false
        let corrupt = Data("{invalid".utf8)
        storage.data = corrupt
        XCTAssertThrowsError(try MatchRepository(storage: storage))
        XCTAssertEqual(storage.data, corrupt)
    }

    func testFutureSchemaIsReportedBeforeDecodingItsContents() throws {
        let storage = MemoryStorage()
        storage.data = Data(#"{"schemaVersion":2,"futureFormat":true}"#.utf8)
        XCTAssertThrowsError(try MatchRepository(storage: storage)) {
            XCTAssertEqual($0 as? MatchError, .unsupportedVersion(2))
        }
    }

    func testInvalidRecordsAndDuplicateIDsAreRejected() throws {
        let storage = MemoryStorage()
        var library = MatchLibrary()
        let unfinished = MatchRecord()
        library.history = [unfinished]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        storage.data = try encoder.encode(library)
        XCTAssertThrowsError(try MatchRepository(storage: storage)) {
            XCTAssertEqual($0 as? MatchError, .invalidArchive)
        }

        var interrupted = unfinished
        interrupted.interruptedAt = Date()
        library.history = [interrupted, interrupted]
        storage.data = try encoder.encode(library)
        XCTAssertThrowsError(try MatchRepository(storage: storage)) {
            XCTAssertEqual($0 as? MatchError, .invalidArchive)
        }
    }

    func testUndoWinningSuperTieBreakPointRestoresItsScoreAndServer() throws {
        let storage = MemoryStorage()
        var repository = try MatchRepository(storage: storage)
        let id = try repository.start(rules: MatchRules(decidingSet: .superTieBreak), firstServer: .opponent)
        for _ in 0..<24 { try repository.awardPoint(to: .me) }
        for _ in 0..<24 { try repository.awardPoint(to: .opponent) }
        for _ in 0..<9 { try repository.awardPoint(to: .me) }
        let beforeMatchPoint = try repository.library.currentMatch?.state()
        try repository.awardPoint(to: .me)
        XCTAssertNil(repository.library.currentMatch)
        repository = try MatchRepository(storage: storage)
        try repository.undoCompletedMatch(id: id)
        XCTAssertEqual(try repository.library.currentMatch?.state(), beforeMatchPoint)
        XCTAssertEqual(try repository.library.currentMatch?.state().points.me, 9)
        XCTAssertTrue(repository.library.history.isEmpty)
    }

    func testUndoNormalSetWinningPointRestoresPreviousSet() throws {
        let repository = try MatchRepository(storage: MemoryStorage())
        try repository.start(firstServer: .opponent)
        for _ in 0..<23 { try repository.awardPoint(to: .me) }
        let beforeSetPoint = try repository.library.currentMatch?.state()
        try repository.awardPoint(to: .me)
        XCTAssertEqual(try repository.library.currentMatch?.state().sets.me, 1)
        try repository.undoCurrentPoint()
        XCTAssertEqual(try repository.library.currentMatch?.state(), beforeSetPoint)
    }

    func testActualFileStorageCreatesDirectoryAndSurvivesReload() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = FileMatchStorage(url: directory.appendingPathComponent("nested/matches.json"))
        XCTAssertNil(try storage.load())
        let repository = try MatchRepository(storage: storage)
        let id = try repository.start()
        try repository.awardPoint(to: .opponent)
        XCTAssertEqual(try MatchRepository(storage: storage).library.currentMatch?.id, id)
        try repository.undoCurrentPoint()
        XCTAssertEqual(try MatchRepository(storage: storage).library.currentMatch?.points, [])
    }
}
