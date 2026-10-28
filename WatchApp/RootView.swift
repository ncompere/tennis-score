import SwiftUI
import TennisCore

private enum Route: Hashable {
    case setup, match(UUID), history, detail(UUID)
}

struct RootView: View {
    @Environment(MatchStore.self) private var store
    @State private var path: [Route] = []
    @State private var restored = false

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if store.isReady {
                    home
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.title)
                                .foregroundStyle(.orange)
                            Text("Sauvegarde indisponible").font(.headline)
                            Text(store.loadingError ?? "Impossible de charger les matchs.")
                                .font(.footnote)
                            Button("Réessayer") { store.reload() }
                        }
                        .padding(.horizontal, 4)
                    }
                }
            }
            .navigationTitle("Tennis Score")
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .setup:
                    MatchSetupView { path = [.match($0)] }
                case .match(let id):
                    MatchView(id: id) { path = [] }
                case .history:
                    HistoryView { path.append(.detail($0)) }
                case .detail(let id):
                    HistoryDetailView(id: id) { path.removeLast() }
                }
            }
        }
        .onAppear { restoreMatchIfNeeded() }
        .onChange(of: store.isReady) { _, _ in restoreMatchIfNeeded() }
        .alert("Enregistrement impossible", isPresented: Binding(
            get: { store.actionError != nil },
            set: { if !$0 { store.actionError = nil } }
        )) {
            Button("Compris", role: .cancel) { store.actionError = nil }
        } message: {
            Text(store.actionError ?? "")
        }
    }

    private var home: some View {
        ScrollView {
            VStack(spacing: 10) {
                Image(systemName: "tennisball.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.mint)
                    .accessibilityHidden(true)
                    .padding(.vertical, 4)

                if let match = store.library.currentMatch {
                    Button { path.append(.match(match.id)) } label: {
                        Label("Reprendre", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }

                Button { path.append(.setup) } label: {
                    Label("Nouveau match", systemImage: "plus")
                }
                .disabled(store.library.currentMatch != nil)

                Button { path.append(.history) } label: {
                    Label("Historique", systemImage: "clock.arrow.circlepath")
                }

                if store.library.currentMatch != nil {
                    Text("Un match est en cours.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func restoreMatchIfNeeded() {
        guard store.isReady, !restored else { return }
        restored = true
        if let match = store.library.currentMatch { path = [.match(match.id)] }
    }
}
