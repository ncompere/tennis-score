import Foundation

public protocol MatchStorage {
    func load() throws -> Data?
    /// Must replace the previous data atomically, or throw without replacing it.
    func save(_ data: Data) throws
}

public struct FileMatchStorage: MatchStorage {
    public let url: URL

    public init(url: URL) { self.url = url }

    public func load() throws -> Data? {
        do { return try Data(contentsOf: url) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return nil }
    }

    public func save(_ data: Data) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }
}

public struct MatchLibrary: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public internal(set) var currentMatch: MatchRecord?
    public internal(set) var history: [MatchRecord]

    public init() {
        schemaVersion = 1
        currentMatch = nil
        history = []
    }

    public var sortedHistory: [MatchRecord] {
        history.sorted {
            let left = $0.completedAt ?? $0.interruptedAt ?? $0.startedAt
            let right = $1.completedAt ?? $1.interruptedAt ?? $1.startedAt
            if left == right { return $0.id.uuidString < $1.id.uuidString }
            return left > right
        }
    }

    func validate() throws {
        guard schemaVersion == 1 else { throw MatchError.unsupportedVersion(schemaVersion) }
        let records = history + (currentMatch.map { [$0] } ?? [])
        guard Set(records.map(\.id)).count == records.count else { throw MatchError.invalidArchive }
        if let currentMatch {
            guard try currentMatch.state().winner == nil,
                  currentMatch.completedAt == nil, currentMatch.interruptedAt == nil else {
                throw MatchError.invalidArchive
            }
        }
        for record in history {
            let state = try record.state()
            let finished = state.winner != nil && record.completedAt != nil && record.interruptedAt == nil
            let interrupted = state.winner == nil && record.interruptedAt != nil && record.completedAt == nil
            guard finished || interrupted else { throw MatchError.invalidArchive }
        }
    }
}

/// Call from a single executor (the watch app uses the main actor).
/// A transaction reaches memory only after its atomic disk write succeeds.
public final class MatchRepository {
    public private(set) var library: MatchLibrary
    private let storage: any MatchStorage
    private let encoder = JSONEncoder()

    public init(storage: any MatchStorage) throws {
        self.storage = storage
        encoder.dateEncodingStrategy = .iso8601
        if let data = try storage.load() {
            // Inspect the version before interpreting the rest of a future schema.
            struct Header: Decodable { let schemaVersion: Int }
            let version = try JSONDecoder().decode(Header.self, from: data).schemaVersion
            guard version == 1 else { throw MatchError.unsupportedVersion(version) }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            library = try decoder.decode(MatchLibrary.self, from: data)
            try library.validate()
        } else {
            library = MatchLibrary()
        }
    }

    @discardableResult
    public func start(
        rules: MatchRules = MatchRules(), firstServer: Player = .me, at date: Date = Date()
    ) throws -> UUID {
        guard library.currentMatch == nil else { throw MatchError.currentMatchExists }
        let record = MatchRecord(rules: rules, firstServer: firstServer, startedAt: date)
        try commit { $0.currentMatch = record }
        return record.id
    }

    public func awardPoint(to player: Player, at date: Date = Date()) throws {
        guard var record = library.currentMatch else { throw MatchError.noCurrentMatch }
        var state = try record.state()
        try state.awardPoint(to: player)
        record.points.append(player)
        if state.winner != nil { record.completedAt = date }
        try commit {
            if state.winner != nil {
                $0.currentMatch = nil
                $0.history.append(record)
            } else {
                $0.currentMatch = record
            }
        }
    }

    public func undoCurrentPoint() throws {
        guard var record = library.currentMatch else { throw MatchError.noCurrentMatch }
        guard !record.points.isEmpty else { throw MatchError.nothingToUndo }
        record.points.removeLast()
        try commit { $0.currentMatch = record }
    }

    public func undoCompletedMatch(id: UUID) throws {
        guard library.currentMatch == nil else { throw MatchError.currentMatchExists }
        guard var record = library.history.first(where: { $0.id == id }) else { throw MatchError.matchNotFound }
        guard record.completedAt != nil, record.interruptedAt == nil,
              !record.points.isEmpty else { throw MatchError.cannotReopen }
        record.points.removeLast()
        record.completedAt = nil
        try commit {
            $0.history.removeAll { $0.id == id }
            $0.currentMatch = record
        }
    }

    public func interruptCurrentMatch(at date: Date = Date()) throws {
        guard var record = library.currentMatch else { throw MatchError.noCurrentMatch }
        record.interruptedAt = date
        try commit {
            $0.currentMatch = nil
            $0.history.append(record)
        }
    }

    public func deleteHistory(id: UUID) throws {
        guard library.history.contains(where: { $0.id == id }) else { throw MatchError.matchNotFound }
        try commit { $0.history.removeAll { $0.id == id } }
    }

    private func commit(_ change: (inout MatchLibrary) -> Void) throws {
        var draft = library
        change(&draft)
        try draft.validate()
        let data = try encoder.encode(draft)
        try storage.save(data)
        library = draft
    }
}
