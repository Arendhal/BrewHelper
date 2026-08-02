import SwiftUI

@main
struct BrewHelperApp: App {
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .environmentObject(appState)
                .frame(minWidth: 1000, minHeight: 680)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            SidebarCommands()
            CommandGroup(after: .appInfo) {
                Button("Rafraîchir la base Homebrew") {
                    Task {
                        await appState.refreshAll()
                    }
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
        }
    }
}
