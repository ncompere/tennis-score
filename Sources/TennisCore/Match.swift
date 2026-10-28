import Foundation

public enum Player: String, Codable, CaseIterable, Sendable {
    case me, opponent

    public var other: Player { self == .me ? .opponent : .me }
}

public enum SetsToWin: Int, Codable, CaseIterable, Sendable {
    case one = 1, two, three
}

public enum DecidingSet: String, Codable, CaseIterable, Sendable {
    case standard, superTieBreak
}

public struct MatchRules: Codable, Equatable, Sendable {
    public let setsToWin: SetsToWin
    public let usesAdvantages: Bool
    public let decidingSet: DecidingSet

    public init(
        setsToWin: SetsToWin = .two,
        usesAdvantages: Bool = true,
        decidingSet: DecidingSet = .standard
    ) {
        self.setsToWin = setsToWin
        self.usesAdvantages = usesAdvantages
        self.decidingSet = setsToWin == .one ? .standard : decidingSet
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        setsToWin = try container.decode(SetsToWin.self, forKey: .setsToWin)
        usesAdvantages = try container.decode(Bool.self, forKey: .usesAdvantages)
        decidingSet = try container.decode(DecidingSet.self, forKey: .decidingSet)
        guard setsToWin != .one || decidingSet == .standard else {
            throw DecodingError.dataCorruptedError(
                forKey: .decidingSet, in: container,
                debugDescription: "A single-set match cannot use a deciding match tie-break."
            )
        }
    }
}

public struct ScorePair: Equatable, Sendable {
    public internal(set) var me: Int = 0
    public internal(set) var opponent: Int = 0

    public init(me: Int = 0, opponent: Int = 0) {
        self.me = me
        self.opponent = opponent
    }

    public internal(set) subscript(player: Player) -> Int {
        get { player == .me ? me : opponent }
        set {
            if player == .me { me = newValue } else { opponent = newValue }
        }
    }
}

public struct SetResult: Equatable, Sendable {
    /// Games in a normal set; points in a deciding match tie-break.
    public let score: ScorePair
    /// Full tie-break points, retained even when the set ends 7–6.
    public let tieBreakPoints: ScorePair?
    public let isSuperTieBreak: Bool

    public var winner: Player { score.me > score.opponent ? .me : .opponent }
}

public enum MatchError: Error, LocalizedError, Equatable {
    case matchFinished, noCurrentMatch, currentMatchExists, nothingToUndo
    case matchNotFound, cannotReopen, invalidArchive, unsupportedVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .matchFinished: return "Ce match est déjà terminé."
        case .noCurrentMatch: return "Aucun match en cours."
        case .currentMatchExists: return "Terminez ou interrompez le match en cours avant d’en démarrer un autre."
        case .nothingToUndo: return "Aucun point à annuler."
        case .matchNotFound: return "Ce match est introuvable."
        case .cannotReopen: return "Ce match ne peut pas être repris."
        case .invalidArchive: return "Les données enregistrées sont incohérentes. Elles ont été conservées sans modification."
        case .unsupportedVersion: return "Cette sauvegarde provient d’une version plus récente de l’application."
        }
    }
}

public struct MatchRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let rules: MatchRules
    public let firstServer: Player
    public let startedAt: Date
    public internal(set) var points: [Player]
    public internal(set) var completedAt: Date?
    public internal(set) var interruptedAt: Date?

    public init(
        id: UUID = UUID(), rules: MatchRules = MatchRules(),
        firstServer: Player = .me, startedAt: Date = Date()
    ) {
        self.id = id
        self.rules = rules
        self.firstServer = firstServer
        self.startedAt = startedAt
        points = []
    }

    public func state() throws -> MatchState {
        try MatchEngine.replay(rules: rules, firstServer: firstServer, points: points)
    }
}
