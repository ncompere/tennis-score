import SwiftUI
import TennisCore

extension Player {
    var displayName: String { self == .me ? "Moi" : "Adversaire" }
    var accent: Color { self == .me ? .mint : .orange }
}

extension MatchRules {
    var summary: String {
        let sets = setsToWin.rawValue == 1 ? "1 set gagnant" : "\(setsToWin.rawValue) sets gagnants"
        let advantages = usesAdvantages ? "Avantages" : "Point décisif"
        let final = decidingSet == .superTieBreak ? "Super tie-break décisif" : "Sets classiques"
        return "\(sets) · \(advantages) · \(final)"
    }
}

extension SetResult {
    var summary: String {
        if isSuperTieBreak { return "[\(score.me)–\(score.opponent)]" }
        return "\(score.me)–\(score.opponent)"
    }
}

extension MatchState {
    var setsSummary: String {
        completedSets.map(\.summary).joined(separator: " · ")
    }

    var phaseLabel: String {
        if isSuperTieBreak { return "Super tie-break · 10 points" }
        if isTieBreak { return "Tie-break · 7 points" }
        if !rules.usesAdvantages && points.me == 3 && points.opponent == 3 { return "Point décisif" }
        return "Set \(completedSets.count + 1) · \(sets.me)–\(sets.opponent)"
    }
}

struct SetScoresView: View {
    let state: MatchState
    let includesCurrentSet: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Moi")
                Spacer()
                Text("Adversaire")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            ForEach(Array(state.completedSets.enumerated()), id: \.offset) { index, result in
                VStack(spacing: 3) {
                    HStack {
                        Text("\(result.score.me)")
                        Spacer()
                        Text(result.isSuperTieBreak ? "Super TB" : "Set \(index + 1)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(result.score.opponent)")
                    }
                    .font(.headline.monospacedDigit())
                    if let tieBreak = result.tieBreakPoints, !result.isSuperTieBreak {
                        Text("Tie-break : \(tieBreak.me)–\(tieBreak.opponent)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    "\(result.isSuperTieBreak ? "Super tie-break" : "Set \(index + 1)"), Moi \(result.score.me), Adversaire \(result.score.opponent)" +
                    (result.tieBreakPoints.map { ", tie-break \($0.me) à \($0.opponent)" } ?? "")
                )
            }

            if includesCurrentSet {
                Divider()
                if state.isSuperTieBreak {
                    Text("Super tie-break en cours")
                } else {
                    Text("Jeux : \(state.games.me)–\(state.games.opponent)")
                }
                Text("Points : \(state.pointLabel(for: .me))–\(state.pointLabel(for: .opponent))")
                    .font(.caption)
            }
        }
    }
}
