import SwiftUI
import WatchKit
import TennisCore

struct MatchView: View {
    @Environment(MatchStore.self) private var store
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showsActions = false
    let id: UUID
    let onHome: () -> Void

    private var record: MatchRecord? {
        if let current = store.library.currentMatch, current.id == id { return current }
        return store.library.history.first { $0.id == id }
    }

    var body: some View {
        Group {
            if let record, let state = try? record.state() {
                if state.winner != nil {
                    ScrollView {
                        VStack(spacing: 12) {
                            MatchResultView(record: record, state: state)
                            Button("Corriger le dernier point", systemImage: "arrow.uturn.backward") {
                                if store.undoCompletedMatch(id: id) { WKInterfaceDevice.current().play(.directionDown) }
                            }
                            .disabled(store.library.currentMatch != nil)
                            Button("Accueil", action: onHome)
                        }
                        .padding(.horizontal, 4)
                    }
                } else if record.interruptedAt == nil {
                    scoreboard(record: record, state: state)
                } else {
                    ScrollView {
                        MatchResultView(record: record, state: state)
                        Button("Accueil", action: onHome)
                    }
                }
            } else {
                VStack {
                    Text("Match indisponible")
                    Button("Accueil", action: onHome)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showsActions) {
            if let record {
                MatchActionsView(record: record, onHome: onHome)
            }
        }
    }

    @ViewBuilder
    private func scoreboard(record: MatchRecord, state: MatchState) -> some View {
        let board = GeometryReader { geometry in
            VStack(spacing: 5) {
                HStack(spacing: 2) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(state.phaseLabel)
                            .font(.caption2.weight(.medium))
                        if !state.completedSets.isEmpty {
                            Text(state.setsSummary)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button { showsActions = true } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: 30, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Options du match")
                }

                ForEach(Player.allCases, id: \.self) { player in
                    Button {
                        if store.awardPoint(to: player) {
                            WKInterfaceDevice.current().play(.click)
                        }
                    } label: {
                        HStack(alignment: .center, spacing: 8) {
                            VStack(alignment: .leading, spacing: 0) {
                                HStack(spacing: 4) {
                                    Text(player.displayName)
                                        .font(.caption.weight(.semibold))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.65)
                                    if state.server == player {
                                        Image(systemName: "tennisball.fill")
                                            .font(.system(size: 10))
                                            .accessibilityHidden(true)
                                    }
                                }
                                Text(state.pointLabel(for: player))
                                    .font(.system(size: min(46, max(32, geometry.size.height * 0.23)), weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                    .minimumScaleFactor(0.65)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            VStack(spacing: 0) {
                                Text("\(state.isSuperTieBreak ? state.sets[player] : state.games[player])")
                                    .font(.title3.weight(.semibold).monospacedDigit())
                                Text(state.isSuperTieBreak ? "sets" : "jeux")
                                    .font(.caption2)
                            }
                            .foregroundStyle(.white.opacity(0.8))
                        }
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .foregroundStyle(isLuminanceReduced ? .white : player.accent)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(isLuminanceReduced ? Color.white.opacity(0.08) : player.accent.opacity(0.15))
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(scoreAccessibilityLabel(for: player, state: state))
                    .accessibilityHint("Ajouter un point")
                    .accessibilityIdentifier(player == .me ? "score.me" : "score.opponent")
                }

                Button {
                    if store.undoCurrentPoint() { WKInterfaceDevice.current().play(.directionDown) }
                } label: {
                    Label("Annuler", systemImage: "arrow.uturn.backward")
                        .font(.caption)
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(record.points.isEmpty)
                .accessibilityLabel("Annuler le dernier point")
                .accessibilityIdentifier("score.undo")
            }
        }
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                ScrollView { board.frame(height: 400) }
            } else {
                board
            }
        }
        // Use the navigation-title space for the scoreboard while reserving
        // the clock row, which is taller on displays larger than 40 mm.
        .padding(.top, WKInterfaceDevice.current().screenBounds.height <= 200 ? 24 : 44)
        .padding(.bottom, 12)
        .ignoresSafeArea(.container, edges: .vertical)
    }

    private func scoreAccessibilityLabel(for player: Player, state: MatchState) -> String {
        let label = state.pointLabel(for: player)
        let points = label == "AV" ? "avantage" : "\(label) points"
        let tally = state.isSuperTieBreak ? "\(state.sets[player]) sets" : "\(state.games[player]) jeux"
        return "\(player.displayName), \(points), \(tally)" +
            (state.server == player ? ", au service" : "")
    }
}

private struct MatchActionsView: View {
    @Environment(MatchStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsInterruption = false
    @State private var interruptionError: String?
    let record: MatchRecord
    let onHome: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Règles du match") {
                    Text(record.rules.summary).font(.footnote)
                }
                Button("Accueil", systemImage: "house") {
                    dismiss()
                    onHome()
                }
                Section {
                    Button("Interrompre le match", role: .destructive) {
                        confirmsInterruption = true
                    }
                } footer: {
                    Text("Le score sera conservé dans l’historique.")
                }
            }
            .navigationTitle("Options")
            .confirmationDialog("Interrompre ce match ?", isPresented: $confirmsInterruption, titleVisibility: .visible) {
                Button("Interrompre", role: .destructive) {
                    if store.interruptCurrentMatch() {
                        dismiss()
                        onHome()
                    } else {
                        // The sheet owns this alert; its presenting view cannot
                        // reliably present another alert over an active sheet.
                        interruptionError = store.actionError
                        store.actionError = nil
                    }
                }
                Button("Continuer à jouer", role: .cancel) {}
            }
            .alert("Enregistrement impossible", isPresented: Binding(
                get: { interruptionError != nil },
                set: { if !$0 { interruptionError = nil } }
            )) {
                Button("Compris", role: .cancel) { interruptionError = nil }
            } message: {
                Text(interruptionError ?? "")
            }
        }
    }
}
