import SwiftUI

@main
struct SILViewerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            TextEditingCommands()
        }
    }
}
