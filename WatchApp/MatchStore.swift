import Foundation
import Observation
import TennisCore

@MainActor
@Observable
final class MatchStore {
    private(set) var library = MatchLibrary()
    private(set) var loadingError: String?
    var actionError: String?
    @ObservationIgnored private var repository: MatchRepository?

    var isReady: Bool { repository != nil }

    init() { reload() }

    func reload() {
        do {
            let base = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: false
            )
            let storage = FileMatchStorage(url: base.appendingPathComponent("TennisScore/matches.json"))
            let loaded = try MatchRepository(storage: storage)
            repository = loaded
            library = loaded.library
            loadingError = nil
        } catch {
            repository = nil
            loadingError = "Impossible de lire les matchs. Vos données n’ont pas été modifiées.\n\n\(error.localizedDescription)"
        }
    }

    func start(rules: MatchRules, firstServer: Player) -> UUID? {
        var id: UUID?
        guard perform({ id = try $0.start(rules: rules, firstServer: firstServer) }) else { return nil }
        return id
    }

    func awardPoint(to player: Player) -> Bool {
        perform { try $0.awardPoint(to: player) }
    }

    func undoCurrentPoint() -> Bool {
        perform { try $0.undoCurrentPoint() }
    }

    func undoCompletedMatch(id: UUID) -> Bool {
        perform { try $0.undoCompletedMatch(id: id) }
    }

    func interruptCurrentMatch() -> Bool {
        perform { try $0.interruptCurrentMatch() }
    }

    func deleteHistory(id: UUID) -> Bool {
        perform { try $0.deleteHistory(id: id) }
    }

    private func perform(_ operation: (MatchRepository) throws -> Void) -> Bool {
        guard let repository else { return false }
        do {
            try operation(repository)
            library = repository.library
            return true
        } catch {
            actionError = "La modification n’a pas été enregistrée. Réessayez.\n\n\(error.localizedDescription)"
            return false
        }
    }
}
