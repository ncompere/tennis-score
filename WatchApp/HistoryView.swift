import SwiftUI
import TennisCore

struct HistoryView: View {
    @Environment(MatchStore.self) private var store
    let onSelected: (UUID) -> Void

    var body: some View {
        Group {
            if store.library.history.isEmpty {
                ContentUnavailableView(
                    "Aucun match", systemImage: "tennisball",
                    description: Text("Vos résultats apparaîtront ici.")
                )
            } else {
                List(store.library.sortedHistory) { record in
                    Button { onSelected(record.id) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.startedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            if let state = try? record.state() {
                                Text(record.interruptedAt != nil ? "Interrompu" : state.winner == .me ? "Victoire" : "Défaite")
                                    .font(.headline)
                                if !state.completedSets.isEmpty {
                                    Text(state.setsSummary)
                                        .font(.caption)
                                }
                                if record.interruptedAt != nil {
                                    Text("\(state.games.me)–\(state.games.opponent) jeux · \(state.pointLabel(for: .me))–\(state.pointLabel(for: .opponent))")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Historique")
    }
}

struct HistoryDetailView: View {
    @Environment(MatchStore.self) private var store
    @State private var confirmsDeletion = false
    let id: UUID
    let onDeleted: () -> Void

    var body: some View {
        ScrollView {
            if let record = store.library.history.first(where: { $0.id == id }),
               let state = try? record.state() {
                VStack(spacing: 14) {
                    MatchResultView(record: record, state: state)
                    Button("Supprimer", role: .destructive) { confirmsDeletion = true }
                }
            }
        }
        .navigationTitle("Résultat")
        .confirmationDialog("Supprimer ce résultat ?", isPresented: $confirmsDeletion, titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) {
                if store.deleteHistory(id: id) { onDeleted() }
            }
            Button("Conserver", role: .cancel) {}
        }
    }
}

struct MatchResultView: View {
    let record: MatchRecord
    let state: MatchState

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: record.interruptedAt != nil ? "pause.circle" : "flag.checkered")
                .font(.title)
                .foregroundStyle(record.interruptedAt != nil ? .orange : .mint)
                .accessibilityHidden(true)
            Text(record.interruptedAt != nil ? "Interrompu" : state.winner == .me ? "Victoire !" : "Défaite")
                .font(.title3.bold())
            if let winner = state.winner {
                Text("Vainqueur : \(winner.displayName)")
                    .font(.caption)
            }
            Text(record.startedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2)
                .foregroundStyle(.secondary)
            SetScoresView(state: state, includesCurrentSet: record.interruptedAt != nil)
            Text(record.rules.summary)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
