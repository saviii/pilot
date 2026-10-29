import SwiftUI

@main
struct TVRemoteApp: App {
    @StateObject private var tv = TVConnection()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if tv.state == .connected {
                    RemoteView()
                } else {
                    ConnectView()
                }
            }
            .environmentObject(tv)
            .preferredColorScheme(.dark)
            .onChange(of: scenePhase) { _, phase in
                #if DEBUG
                if CommandLine.arguments.contains("-demo") { return tv.demo() }
                #endif
                if phase == .active { tv.reconnect() }
            }
        }
    }
}
