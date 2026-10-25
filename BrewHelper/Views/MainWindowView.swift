import SwiftUI

// La fenêtre : quatre espaces (Accueil, Bibliothèque, Découvrir, Sécurité), l'Activité en bas
// de la barre latérale, et dans la barre d'outils la palette ⌘K, l'apparence et l'état de la file.

public struct MainWindowView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var security: CVESecurityService = .shared

    public init() {}

    public var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.background)
        }
        .toolbar { toolbarContent }
        .onAppear { appState.onAppearInitialLoad() }
        .sheet(isPresented: $appState.isPalettePresented) {
            CommandPaletteView()
        }
    }

    // MARK: Barre latérale

    private var sidebar: some View {
        List(selection: Binding(get: { appState.selectedTab }, set: { if let tab = $0 { appState.selectedTab = tab } })) {
            Section {
                ForEach(NavigationTab.primary) { tab in
                    sidebarRow(tab).tag(tab)
                }
            } header: {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Palette.accent)
                            .frame(width: 26, height: 26)
                        Image(systemName: "mug.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                    }
                    Text("BrewHelper")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Palette.text)
                }
                .padding(.bottom, 10)
                .textCase(nil)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Divider()
                Button {
                    appState.selectedTab = .activity
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: NavigationTab.activity.icon)
                            .frame(width: 18)
                        Text(NavigationTab.activity.rawValue)
                        Spacer()
                        if appState.pendingTaskCount > 0 {
                            CountBadge(appState.pendingTaskCount, color: Palette.accent)
                        }
                    }
                    .font(.system(size: 13, weight: appState.selectedTab == .activity ? .semibold : .regular))
                    .foregroundColor(Palette.text)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(appState.selectedTab == .activity ? Palette.surface : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)

                Text(syncLine)
                    .font(.system(size: 11))
                    .foregroundColor(Palette.textSecondary)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
            }
        }
    }

    private func sidebarRow(_ tab: NavigationTab) -> some View {
        HStack(spacing: 8) {
            Label(tab.rawValue, systemImage: tab.icon)
            Spacer()
            switch tab {
            case .library:
                if appState.outdatedCount > 0 {
                    CountBadge(appState.outdatedCount, color: Palette.accent)
                        .help("Mises à jour disponibles")
                } else {
                    Text("\(appState.packages.count)").font(.system(size: 11)).foregroundColor(Palette.textSecondary)
                }
            case .security:
                if security.vulnerableCount > 0 {
                    CountBadge(security.vulnerableCount, color: Palette.dangerBadge)
                        .help("Paquets touchés par une faille ou un avis à trancher")
                }
            default:
                EmptyView()
            }
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private var syncLine: String {
        if appState.isSyncingCatalog { return "Actualisation de Homebrew..." }
        if let date = appState.lastCatalogSync { return "Homebrew actualisé à \(Self.timeFormatter.string(from: date))" }
        return "Homebrew pas encore actualisé"
    }

    // MARK: Contenu

    @ViewBuilder
    private var detail: some View {
        switch appState.selectedTab {
        case .home: HomeView()
        case .library: LibraryView()
        case .discover: DiscoverCatalogView()
        case .security: SecurityAuditView()
        case .activity: ActivityView()
        }
    }

    // MARK: Barre d'outils

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Button {
                appState.isPalettePresented = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                    Text("Rechercher un paquet ou une action")
                    Spacer(minLength: 16)
                    Text("⌘K")
                        .font(.system(size: 11))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Palette.lineStrong, lineWidth: 1))
                }
                .font(.system(size: 13))
                .foregroundColor(Palette.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .frame(minWidth: 320)
                .background(Palette.field)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("Palette de commandes (⌘K)")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                appState.selectedTab = .activity
            } label: {
                if let running = appState.runningTask {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(running.title).lineLimit(1)
                    }
                } else {
                    Label("Rien en cours", systemImage: "checkmark.circle")
                }
            }
            .help(appState.pendingTaskCount > 0 ? "\(appState.pendingTaskCount) tâche(s) en cours ou en attente" : "Aucune commande en cours")

            Picker("Apparence", selection: $appState.appearance) {
                ForEach(AppAppearance.allCases) { appearance in
                    Label(appearance.label, systemImage: appearance.icon).tag(appearance)
                }
            }
            .pickerStyle(.segmented)
            .help("Apparence : Auto suit le réglage de macOS")
        }
    }
}
