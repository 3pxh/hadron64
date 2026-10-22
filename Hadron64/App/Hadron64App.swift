import SwiftUI

@main
struct Hadron64App: App {
    @State private var stats: StatsStore = {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "debugSeedStats") { return .demo() }
        #endif
        return StatsStore()
    }()
    @State private var supporter = Supporter()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(stats)
                .environment(supporter)
                .adaptiveScale()
                .preferredColorScheme(.light)
                .tint(Palette.ink)
                // GameCenter: authenticate as early as possible so the access point and
                // score submission are ready by the first finished game. No-op until enabled.
                .task { GameCenterService.shared.authenticate(stats: stats) }
        }
    }
}

/// Every full-screen experience the app can launch.
enum Session: Identifiable, Hashable {
    case game(GameMode)
    case remainder
    case remainderMatch
    case setSize
    case multiplayer
    case tutorial

    var id: Self { self }
}

extension View {
    func sessionCover(_ session: Binding<Session?>) -> some View {
        fullScreenCover(item: session) { session in
            Group {
                switch session {
                case .game(let mode): GameScreen(mode: mode)
                case .remainder: RemainderDrillScreen()
                case .remainderMatch: RemainderMatchScreen()
                case .setSize: SetSizeDrillScreen()
                case .multiplayer: MultiplayerScreen()
                case .tutorial: TutorialScreen()
                }
            }
            .adaptiveScale()
        }
    }
}
