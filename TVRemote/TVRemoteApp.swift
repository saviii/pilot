import SwiftUI

@main
struct TVRemoteApp: App {
    @StateObject private var tv = TVConnection()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appearance") private var appearance: Appearance = .system

    var body: some Scene {
        WindowGroup {
            Group {
                if !tv.adding && (tv.state == .connected || (tv.isPaired && tv.state != .waitingForApproval)) {
                    RemoteView()
                } else {
                    ConnectView()
                }
            }
            .environmentObject(tv)
            .preferredColorScheme(appearance.scheme)
            .onChange(of: scenePhase) { _, phase in
                #if DEBUG
                if CommandLine.arguments.contains("-demo") { return tv.demo() }
                #endif
                if phase == .active { tv.reconnect() }
                if phase == .background { tv.suspend() }
            }
        }
    }
}
