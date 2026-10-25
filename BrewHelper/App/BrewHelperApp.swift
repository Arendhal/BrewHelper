import SwiftUI

@main
struct BrewHelperApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .environmentObject(appState)
                .frame(minWidth: 1080, minHeight: 700)
        }
        .windowToolbarStyle(.unified)
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
            CommandGroup(after: .textEditing) {
                Button("Palette de commandes") {
                    appState.isPalettePresented = true
                }
                .keyboardShortcut("k", modifiers: [.command])
            }
            CommandMenu("Aller") {
                ForEach(Array(NavigationTab.allCases.enumerated()), id: \.element) { index, tab in
                    Button(tab.rawValue) { appState.selectedTab = tab }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [.command])
                }
            }
        }
    }
}
