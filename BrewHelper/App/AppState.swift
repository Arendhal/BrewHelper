import Foundation
import SwiftUI

public enum NavigationTab: String, CaseIterable, Identifiable {
    case dashboard = "Vue d'ensemble"
    case discover = "Découvrir & Installer"
    case allPackages = "Tous les Paquets"
    case formulae = "Formulae (CLI)"
    case casks = "Casks (Apps macOS)"
    case outdated = "Mises à jour disponibles"
    case securityAudit = "Audit de Sécurité CVE"
    
    public var id: String { rawValue }
    
    public var icon: String {
        switch self {
        case .dashboard: return "rectangle.grid.2x2.fill"
        case .discover: return "bag.fill"
        case .allPackages: return "shippingbox.fill"
        case .formulae: return "terminal.fill"
        case .casks: return "macwindow"
        case .outdated: return "arrow.triangle.2.circlepath"
        case .securityAudit: return "lock.shield.fill"
        }
    }
}

@MainActor
public class AppState: ObservableObject {
    @Published public var packages: [BrewPackage] = []
    private var isRefreshing: Bool = false
    @Published public var selectedTab: NavigationTab = .dashboard
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil
    
    // Featured catalog items
    @Published public var featuredCatalog: [CatalogItem] = []
    
    // Terminal overlay state
    @Published public var isTerminalPresented: Bool = false
    @Published public var terminalTitle: String = ""
    @Published public var terminalLogs: [String] = []
    @Published public var isCommandRunning: Bool = false
    
    // Background Silent Operation State (Progress Banner)
    @Published public var activeOperationMessage: String? = nil
    @Published public var activeOperationDetail: String? = nil
    
    private var hasLoadedOnce: Bool = false
    
    public init() {
        Task {
            await self.onAppearInitialLoad()
        }
    }
    
    public func onAppearInitialLoad() {
        guard !hasLoadedOnce else { return }
        hasLoadedOnce = true
        
        Task {
            await loadCatalog()
            await refreshAll()
        }
    }
    
    public func isPackageInstalled(name: String) -> Bool {
        let lower = name.lowercased()
        return packages.contains { $0.name.lowercased() == lower || $0.fullName.lowercased() == lower }
    }
    
    // MARK: - Data Refresh & Actions (Instant Local Load + Background Network Sync)
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
            
            CVESecurityService.shared.startBackgroundScan(for: fetched) { [weak self] pkgId, newStatus in
                guard let self = self else { return }
                if let index = self.packages.firstIndex(where: { $0.id == pkgId }) {
                    var modified = self.packages[index]
                    modified.cveStatus = newStatus
                    self.packages[index] = modified
                }
            }
            
            Task {
                if let outdatedSet = try? await BrewCommandService.shared.fetchOutdatedSet() {
                    for i in 0..<self.packages.count {
                        let pkg = self.packages[i]
                        if outdatedSet.contains(pkg.name) && pkg.installedVersion != pkg.latestVersion {
                            var modified = pkg
                            modified.isOutdated = true
                            self.packages[i] = modified
                        } else if pkg.isOutdated && (!outdatedSet.contains(pkg.name) || pkg.installedVersion == pkg.latestVersion) {
                            var modified = pkg
                            modified.isOutdated = false
                            self.packages[i] = modified
                        }
                    }
                }
            }
        } catch {
            self.errorMessage = error.localizedDescription
            self.isLoading = false
        }
    }
    
    public func loadCatalog() async {
        self.featuredCatalog = await BrewCatalogService.shared.fetchFeaturedItems()
    }
    
    // MARK: - Computed Properties for Filters & Stats
    public var formulaeCount: Int { packages.filter { $0.type == .formula }.count }
    public var casksCount: Int { packages.filter { $0.type == .cask }.count }
    public var outdatedCount: Int { packages.filter { $0.isOutdated }.count }
    public var vulnerableCount: Int {
        packages.filter {
            if case .vulnerable = $0.cveStatus { return true }
            return false
        }.count
    }
    
    public func filteredPackages(for tab: NavigationTab, search: String) -> [BrewPackage] {
        var base: [BrewPackage] = []
        switch tab {
        case .dashboard, .discover: base = packages
        case .allPackages: base = packages
        case .formulae: base = packages.filter { $0.type == .formula }
        case .casks: base = packages.filter { $0.type == .cask }
        case .outdated: base = packages.filter { $0.isOutdated }
        case .securityAudit:
            base = packages.sorted { p1, p2 in
                let w1: Int = {
                    if case .vulnerable = p1.cveStatus { return 3 }
                    if case .scanning = p1.cveStatus { return 2 }
                    return 1
                }()
                let w2: Int = {
                    if case .vulnerable = p2.cveStatus { return 3 }
                    if case .scanning = p2.cveStatus { return 2 }
                    return 1
                }()
                return w1 > w2
            }
        }
        
        if search.trimmingCharacters(in: .whitespaces).isEmpty {
            return base
        }
        let lower = search.lowercased()
        return base.filter { $0.name.lowercased().contains(lower) || $0.description.lowercased().contains(lower) }
    }
    
    // MARK: - System Maintenance & Terminal Executions (Silent Background & Banner Progress)
    public func runMaintenance(command: BrewCommandType) {
        terminalTitle = command.rawValue.uppercased()
        terminalLogs = ["🚀 Initialisation de \(command.rawValue)...", "--------------------------------------------------"]
        
        // SILENT MODE: No disruptive terminal popup! Use sleek progress banner instead.
        isCommandRunning = true
        activeOperationMessage = "⚙️ Entretien : \(command.rawValue.uppercased()) en cours..."
        activeOperationDetail = "Lancement des processus de fond..."
        
        Task {
            do {
                if command == .update {
                    activeOperationDetail = "[1/2] Actualisation des catalogues et index (brew update)..."
                    terminalLogs.append("📡 [1/2] Mise à jour des index et catalogues (brew update)...")
                    let code1 = try await BrewCommandService.shared.runCommandWithStreaming(arguments: ["update"]) { [weak self] line in
                        self?.terminalLogs.append(line)
                        self?.activeOperationDetail = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    if code1 == 0 {
                        activeOperationDetail = "[2/2] Installation des nouvelles versions (brew upgrade)..."
                        terminalLogs.append("--------------------------------------------------")
                        terminalLogs.append("📦 [2/2] Installation des nouvelles versions (brew upgrade)...")
                        let code2 = try await BrewCommandService.shared.runCommandWithStreaming(arguments: ["upgrade"]) { [weak self] line in
                            self?.terminalLogs.append(line)
                            self?.activeOperationDetail = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                        terminalLogs.append("--------------------------------------------------")
                        let ok = (code2 == 0)
                        terminalLogs.append(ok ? "✅ Tout le système a été mis à jour avec succès (Code 0)." : "⚠️ Mise à jour achevée (code \(code2)).")
                        activeOperationMessage = ok ? "✅ Mises à jour terminées avec succès !" : "⚠️ Mises à jour terminées (Code \(code2))"
                    } else {
                        terminalLogs.append("❌ Échec lors de l'actualisation du catalogue (brew update code \(code1)).")
                        activeOperationMessage = "❌ Échec lors de la vérification (Code \(code1))"
                    }
                } else {
                    var args: [String] = []
                    switch command {
                    case .doctor: args = ["doctor"]
                    case .cleanup: args = ["cleanup"]
                    case .updateOnly: args = ["update"]
                    case .upgradeAll: args = ["upgrade"]
                    default: break
                    }
                    
                    let code = try await BrewCommandService.shared.runCommandWithStreaming(arguments: args) { [weak self] line in
                        self?.terminalLogs.append(line)
                        self?.activeOperationDetail = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    terminalLogs.append("--------------------------------------------------")
                    let ok = (code == 0)
                    terminalLogs.append(ok ? "✅ Opération terminée avec succès (Code 0)." : "⚠️ Opération achevée avec le code de sortie \(code).")
                    activeOperationMessage = ok ? "✅ Opération terminée avec succès !" : "⚠️ Opération terminée avec le code \(code)"
                }
            } catch {
                terminalLogs.append("❌ Erreur critique lors de l'exécution : \(error.localizedDescription)")
                activeOperationMessage = "❌ Erreur : \(error.localizedDescription)"
            }
            activeOperationDetail = nil
            isCommandRunning = false
            await refreshAll()
            
            // Auto-hide success banner after 3.5 seconds
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            if !self.isCommandRunning {
                self.activeOperationMessage = nil
            }
        }
    }
    
    public func executePackageAction(package: BrewPackage, action: PackageAction) {
        terminalTitle = "\(action.rawValue.uppercased()) : \(package.name)"
        terminalLogs = ["🚀 Lancement de : brew \(action.rawValue) \(package.fullName)...", "--------------------------------------------------"]
        
        // SILENT MODE: No disruptive popup!
        isCommandRunning = true
        activeOperationMessage = action == .install ? "📥 Installation de \(package.name)..." : "⚡️ \(action.rawValue.capitalized) de \(package.name)..."
        activeOperationDetail = "Préparation des paquets..."
        
        Task {
            do {
                try await BrewCommandService.shared.executePackageAction(package: package, action: action) { [weak self] line in
                    self?.terminalLogs.append(line)
                    self?.activeOperationDetail = line.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                terminalLogs.append("--------------------------------------------------")
                terminalLogs.append("✅ \(action.rawValue.capitalized) sur \(package.name) terminé avec succès.")
                activeOperationMessage = "✅ \(action == .install ? "Installation" : action.rawValue.capitalized) de \(package.name) réussie !"
            } catch {
                terminalLogs.append("❌ Échec : \(error.localizedDescription)")
                activeOperationMessage = "❌ Échec de \(action.rawValue) sur \(package.name)"
            }
            activeOperationDetail = nil
            isCommandRunning = false
            await refreshAll()
            
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            if !self.isCommandRunning {
                self.activeOperationMessage = nil
            }
        }
    }
}
