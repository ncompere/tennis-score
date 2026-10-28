import SwiftUI
import TennisCore

struct MatchSetupView: View {
    @Environment(MatchStore.self) private var store
    @State private var setsToWin: SetsToWin = .two
    @State private var usesAdvantages = true
    @State private var decidingSet: DecidingSet = .standard
    @State private var firstServer: Player = .me
    let onStarted: (UUID) -> Void

    var body: some View {
        Form {
            Section("Format") {
                Picker("Sets gagnants", selection: $setsToWin) {
                    ForEach(SetsToWin.allCases, id: \.self) { count in
                        Text("\(count.rawValue)").tag(count)
                    }
                }
                Toggle("Avantages", isOn: $usesAdvantages)
                Text(usesAdvantages ? "Deux points d’écart après 40–40." : "À 40–40, le prochain point gagne le jeu.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if setsToWin != .one {
                    Picker("Set décisif", selection: $decidingSet) {
                        Text("Normal").tag(DecidingSet.standard)
                        Text("Super tie-break").tag(DecidingSet.superTieBreak)
                    }
                    if decidingSet == .superTieBreak {
                        Text("Le dernier set est remplacé par un tie-break en 10 points, avec deux points d’écart.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Premier service") {
                Picker("Serveur", selection: $firstServer) {
                    ForEach(Player.allCases, id: \.self) { player in
                        Text(player.displayName).tag(player)
                    }
                }
            }

            Button {
                let rules = MatchRules(
                    setsToWin: setsToWin, usesAdvantages: usesAdvantages,
                    decidingSet: decidingSet
                )
                if let id = store.start(rules: rules, firstServer: firstServer) { onStarted(id) }
            } label: {
                Label("Jouer", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.library.currentMatch != nil)
        }
        .navigationTitle("Nouveau match")
        .onChange(of: setsToWin) { _, value in
            if value == .one { decidingSet = .standard }
        }
    }
}
