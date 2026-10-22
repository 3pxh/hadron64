import GameKit
import SwiftUI

/// Statistics screen: how the player stacks up against Game Center friends on one mode's boards,
/// today or all time. Only shown when signed in to Game Center and the mode has leaderboards.
struct FriendsCard: View {
    let mode: GameMode
    @State private var daily = true
    @State private var entries: [GKLeaderboard.Entry] = []
    @State private var hasAccess = true
    @State private var loading = true
    @Environment(\.uiScale) private var s

    private var service: GameCenterService { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Friends").font(.rounded(17 * s, .bold)).foregroundStyle(Palette.ink)
            Picker("Range", selection: $daily) {
                Text("Today").tag(true)
                Text("All Time").tag(false)
            }
            .pickerStyle(.segmented)

            if loading && entries.isEmpty {
                ProgressView().frame(maxWidth: .infinity, minHeight: 60 * s)
            } else if entries.isEmpty {
                Text(hasAccess ? (daily ? "No scores yet today." : "No scores yet.")
                               : "Allow friends access in Game Center settings to compare times.")
                    .font(.rounded(13 * s, .medium)).foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity, minHeight: 44 * s)
            } else {
                VStack(spacing: 6 * s) {
                    ForEach(entries, id: \.player.gamePlayerID) { row($0) }
                }
            }

            HStack(spacing: 10 * s) {
                action("Add Friends", icon: "person.badge.plus") { service.presentAddFriends() }
                if service.supportsChallenges {
                    action("Challenge", icon: "flag.2.crossed.fill") { service.presentChallenge(for: mode) }
                }
                action("All Players", icon: "globe") { service.presentLeaderboard(for: mode, daily: daily) }
            }
        }
        .padding(16 * s)
        .background(RoundedRectangle(cornerRadius: 20 * s, style: .continuous).fill(Palette.card))
        .task(id: "\(mode.rawValue)-\(daily)") { await load() }
    }

    private func load() async {
        loading = true
        hasAccess = await service.friendsAccess(prompt: true)
        entries = await service.friendEntries(mode: mode, daily: daily)
        loading = false
    }

    private func row(_ entry: GKLeaderboard.Entry) -> some View {
        let isMe = entry.player.gamePlayerID == GKLocalPlayer.local.gamePlayerID
        return HStack(spacing: 10 * s) {
            Text("\(entry.rank)")
                .font(.rounded(15 * s, .bold).monospacedDigit())
                .foregroundStyle(Palette.muted)
                .frame(minWidth: 24 * s, alignment: .trailing)
            PlayerPhoto(player: entry.player, size: 30 * s)
            Text(isMe ? String(localized: "You") : entry.player.displayName)
                .font(.rounded(15 * s, isMe ? .bold : .medium))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
            Spacer()
            // Formatted by Game Center from the board's App Store Connect score format.
            Text(entry.formattedScore)
                .font(.rounded(15 * s, .bold).monospacedDigit())
                .foregroundStyle(Palette.ink)
        }
        .padding(.horizontal, 10 * s).padding(.vertical, 6 * s)
        .background(RoundedRectangle(cornerRadius: 10 * s, style: .continuous)
            .fill(isMe ? Palette.yellow.opacity(0.3) : Palette.paper))
    }

    private func action(_ title: LocalizedStringKey, icon: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Label(title, systemImage: icon)
                .font(.rounded(13 * s, .semibold))
                .frame(maxWidth: .infinity, minHeight: 36 * s)
        }
        .buttonStyle(.bordered)
        .tint(Palette.ink)
    }
}

/// A Game Center player's avatar, falling back to a person glyph while loading or when there's none.
private struct PlayerPhoto: View {
    let player: GKPlayer
    let size: CGFloat
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(Palette.faint)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: player.gamePlayerID) { image = try? await player.loadPhoto(for: .small) }
    }
}
