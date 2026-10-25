import Foundation
import SwiftUI

/// Les espaces de l'application. Les anciens onglets Formulae, Casks et Mises à jour sont
/// devenus des filtres de la Bibliothèque : une seule liste, plusieurs angles.
public enum NavigationTab: String, CaseIterable, Identifiable {
    case home = "Accueil"
    case library = "Bibliothèque"
    case discover = "Découvrir"
    case security = "Sécurité"
    case activity = "Activité"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .home: return "house"
        case .library: return "shippingbox"
        case .discover: return "safari"
        case .security: return "shield.lefthalf.filled"
        case .activity: return "waveform.path.ecg"
        }
    }

    /// Les espaces principaux ; Activité vit en bas de la barre latérale.
    public static let primary: [NavigationTab] = [.home, .library, .discover, .security]
}

@MainActor
public class AppState: ObservableObject {
    @Published public var packages: [BrewPackage] = []
    private var isRefreshing: Bool = false
    @Published public var selectedTab: NavigationTab = .home
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil

    /// Filtre et sélection de la Bibliothèque, pilotables depuis l'Accueil ou la palette
    /// (« Voir les 23 non suivis » ouvre la Bibliothèque déjà filtrée).
    @Published public var libraryFilter: LibraryFilter = .all
    @Published public var librarySelection: BrewPackage.ID? = nil

    /// Rubriques de « Découvrir », calculées d'après les statistiques d'installation de Homebrew.
    @Published public var discoverFeed: DiscoverFeed? = nil
    @Published public var isLoadingDiscover: Bool = false
    private var discoverSeed: Int? = nil

    // File d'activité (voir ActivityCenter.swift).
    @Published public var tasks: [BrewTask] = []
    var isQueueRunning: Bool = false

    @Published public var isPalettePresented: Bool = false
    /// Recherche transmise à Découvrir depuis la palette ; Découvrir la consomme en s'affichant.
    @Published public var pendingDiscoverQuery: String? = nil

    @Published public var appearance: AppAppearance {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: AppAppearance.storageKey)
            appearance.apply()
        }
    }

    /// Fin de la dernière actualisation de Homebrew réussie.
    @Published public private(set) var lastCatalogSync: Date? = nil

    private var hasLoadedOnce: Bool = false

    public init() {
        let saved = UserDefaults.standard.string(forKey: AppAppearance.storageKey).flatMap(AppAppearance.init(rawValue:))
        self.appearance = saved ?? .system
        Task {
            self.appearance.apply()
            self.onAppearInitialLoad()
        }
    }

    public func onAppearInitialLoad() {
        guard !hasLoadedOnce else { return }
        hasLoadedOnce = true
        Task {
            await refreshAll()
            // Les recommandations excluent ce qui est installé : elles attendent la liste des paquets,
            // mais pas l'actualisation de Homebrew.
            Task { await self.loadCatalog() }
            synchronizeCatalog()
        }
    }

    /// Ce que fait le lancement : actualiser les index Homebrew. C'est cette étape qui
    /// rend fiable l'état « mises à jour disponibles ». L'audit de vulnérabilités, lui,
    /// interroge une base distante paquet par paquet : il se déclenche à la demande.
    public func synchronizeCatalog() {
        guard !isSyncingCatalog else { return }
        enqueue("Actualiser Homebrew", commands: [["update"]])
    }

    public var isSyncingCatalog: Bool {
        tasks.contains { !$0.status.isFinished && $0.steps.first?.arguments == ["update"] && $0.steps.count == 1 }
    }

    /// Une commande Homebrew est en cours ou en attente.
    public var isCommandRunning: Bool { pendingTaskCount > 0 }

    /// Lance l'audit de vulnérabilités sur les paquets installés. Toujours déclenché par
    /// une action explicite.
    public func runSecurityAudit(force: Bool = false) {
        CVESecurityService.shared.startAudit(for: packages, force: force) { [weak self] pkgId, newStatus in
            guard let self = self else { return }
            if let index = self.packages.firstIndex(where: { $0.id == pkgId }) {
                var modified = self.packages[index]
                modified.cveStatus = newStatus
                self.packages[index] = modified
            }
        }
    }

    public func isPackageInstalled(name: String) -> Bool {
        let lower = name.lowercased()
        return packages.contains { $0.name.lowercased() == lower || $0.fullName.lowercased() == lower }
    }

    /// Paquets installés qui dépendent de celui-ci : « pourquoi il est là » pour une dépendance,
    /// et ce qu'une désinstallation casserait.
    public func dependents(of package: BrewPackage) -> [String] {
        let names: Set<String> = [package.name, package.fullName]
        return packages.filter { candidate in candidate.dependencies.contains { names.contains($0) } }
            .map { $0.name }
            .sorted()
    }

    /// Ouvre la Bibliothèque sur un filtre (et éventuellement un paquet).
    public func showLibrary(_ filter: LibraryFilter, selecting packageID: BrewPackage.ID? = nil) {
        libraryFilter = filter
        librarySelection = packageID
        selectedTab = .library
    }

    // MARK: - Données

    public func refreshAll() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        self.isLoading = true
        self.errorMessage = nil
        do {
            let fetched = try await BrewCommandService.shared.fetchInstalledPackagesOnly()
            self.packages = fetched
            self.isLoading = false

            // Statuts issus du dernier audit mémorisé : rien n'est interrogé ici.
            for index in self.packages.indices {
                self.packages[index].cveStatus = CVESecurityService.shared.status(for: self.packages[index])
            }

            if let outdatedSet = try? await BrewCommandService.shared.fetchOutdatedSet() {
                for i in 0..<self.packages.count {
                    let pkg = self.packages[i]
                    // `brew outdated` reports casks by their token (fullName), not their display name —
                    // check both so casks actually match.
                    let matchesOutdatedSet = outdatedSet.contains(pkg.name) || outdatedSet.contains(pkg.fullName)
                    if matchesOutdatedSet && pkg.installedVersion != pkg.latestVersion {
                        self.packages[i].isOutdated = true
                    } else if pkg.isOutdated && !matchesOutdatedSet && pkg.installedVersion == pkg.latestVersion {
                        self.packages[i].isOutdated = false
                    }
                }
            }
            if tasks.last(where: { $0.steps.first?.arguments == ["update"] })?.status == .succeeded {
                lastCatalogSync = tasks.last(where: { $0.steps.first?.arguments == ["update"] })?.finishedAt
            }
        } catch {
            self.errorMessage = error.localizedDescription
            self.isLoading = false
        }
    }

    public func loadCatalog() async {
        guard !isLoadingDiscover else { return }
        isLoadingDiscover = true
        let installed = Set(packages.flatMap { [$0.name, $0.fullName] })
        discoverFeed = await BrewCatalogService.shared.fetchDiscoverFeed(excluding: installed, seed: discoverSeed)
        isLoadingDiscover = false
    }

    /// Nouveau tirage pour « À découvrir aujourd'hui » ; les classements, eux, ne changent qu'avec les statistiques.
    public func reshuffleDiscover() {
        discoverSeed = Int.random(in: 0..<Int(Int32.max))
        Task { await loadCatalog() }
    }

    // MARK: - Compteurs

    public var formulaeCount: Int { packages.filter { $0.type == .formula }.count }
    public var casksCount: Int { packages.filter { $0.type == .cask }.count }
    public var outdatedCount: Int { packages.filter { $0.isOutdated }.count }
    public var vulnerableCount: Int {
        packages.filter {
            if case .vulnerable = $0.cveStatus { return true }
            return false
        }.count
    }

    // MARK: - Commandes
    //
    // Toutes passent par la file d'activité : une à la fois, chacune avec son journal.

    public func runMaintenance(command: BrewCommandType) {
        switch command {
        case .update: enqueue("Tout mettre à jour", commands: [["update"], ["upgrade"]])
        case .updateOnly: synchronizeCatalog()
        case .upgradeAll: enqueue("Mettre à jour tous les paquets", commands: [["upgrade"]])
        case .cleanup: enqueue("Nettoyer les anciennes versions", commands: [["cleanup"]])
        case .doctor: enqueue("Diagnostic Homebrew", commands: [["doctor"]])
        }
    }

    /// Exécute une étape d'un plan de remédiation.
    public func runRemediationStep(_ step: RemediationStep) {
        guard let arguments = step.command else { return }
        runBrewArguments(arguments, title: step.title)
    }

    public func runBrewArguments(_ arguments: [String], title: String) {
        enqueue(title, commands: [arguments])
    }

    public func executePackageAction(package: BrewPackage, action: PackageAction) {
        var arguments = [action.rawValue]
        if package.type == .cask && (action == .install || action == .reinstall) {
            arguments.append("--cask")
        }
        arguments.append(package.fullName.trimmingCharacters(in: .whitespacesAndNewlines))

        let verb: String
        switch action {
        case .install: verb = "Installer"
        case .upgrade: verb = "Mettre à jour"
        case .reinstall: verb = "Réinstaller"
        case .uninstall: verb = "Désinstaller"
        }
        enqueue("\(verb) \(package.name)", commands: [arguments], packageID: package.id)
    }
}
