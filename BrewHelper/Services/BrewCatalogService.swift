import Foundation

public struct CatalogItem: Identifiable, Hashable {
    public var id: String { name }
    public let name: String
    public let desc: String
    public let homepage: String
    public let version: String
    public let category: String
    public let isCask: Bool
    
    public init(name: String, desc: String, homepage: String, version: String, category: String, isCask: Bool = false) {
        self.name = name
        self.desc = desc
        self.homepage = homepage
        self.version = version
        self.category = category
        self.isCask = isCask
    }
    
    public func toBrewPackage() -> BrewPackage {
        return BrewPackage(
            id: isCask ? "cask-\(name)" : "formula-\(name)",
            name: name,
            fullName: name,
            type: isCask ? .cask : .formula,
            description: desc,
            homepage: homepage,
            license: "Open Source / Divers",
            installedVersion: "Non installé",
            latestVersion: version,
            isOutdated: false,
            dependencies: [],
            bottleArchitectures: [isCask ? "macOS Universal Cask" : "Apple Silicon / Intel Bottler"],
            caveats: nil
        )
    }
}

public class BrewCatalogService: @unchecked Sendable {
    public static let shared = BrewCatalogService()
    
    private var cachedFeatured: [CatalogItem] = [
        // Outils Développeurs
        CatalogItem(name: "bat", desc: "Clone de cat(1) avec coloration syntaxique et intégration Git.", homepage: "https://github.com/sharkdp/bat", version: "0.24.0", category: "CLI Utility"),
        CatalogItem(name: "fd", desc: "Alternative ultra-rapide et conviviale à find.", homepage: "https://github.com/sharkdp/fd", version: "9.0.0", category: "File System"),
        CatalogItem(name: "fzf", desc: "Filtre flou de recherche interactif en ligne de commande.", homepage: "https://github.com/junegunn/fzf", version: "0.54.0", category: "Productivity"),
        CatalogItem(name: "jq", desc: "Processeur de flux JSON en ligne de commande ultra-légendaire.", homepage: "https://jqlang.github.io/jq/", version: "1.7.1", category: "Data Parsing"),
        CatalogItem(name: "lazygit", desc: "Interface utilisateur simple au terminal pour les commandes git.", homepage: "https://github.com/jesseduffield/lazygit", version: "0.43.1", category: "Git & Dev"),
        CatalogItem(name: "btop", desc: "Moniteur de ressources système en terminal avec graphiques somptueux.", homepage: "https://github.com/aristocratos/btop", version: "1.3.2", category: "System Monitor"),
        CatalogItem(name: "gh", desc: "L'outil officiel d'interface en ligne de commande GitHub.", homepage: "https://cli.github.com", version: "2.54.0", category: "GitHub"),
        CatalogItem(name: "starship", desc: "Prompt shell minimaliste, fulgurant et extrêmement personnalisable.", homepage: "https://starship.rs", version: "1.20.1", category: "Shell Customization"),
        // Applications macOS (Casks)
        CatalogItem(name: "raycast", desc: "Lanceur ultra-puissant et remplaçant d'Spotlight avec des extensions infinis.", homepage: "https://raycast.com", version: "Latest", category: "macOS Apps (Cask)", isCask: true),
        CatalogItem(name: "iterm2", desc: "Le terminal de référence avancé pour macOS avec fenêtres partagées et onglets.", homepage: "https://iterm2.com", version: "Latest", category: "macOS Apps (Cask)", isCask: true),
        CatalogItem(name: "visual-studio-code", desc: "L'éditeur de code multi-plateforme ultra-rapide de Microsoft.", homepage: "https://code.visualstudio.com", version: "Latest", category: "macOS Apps (Cask)", isCask: true),
        CatalogItem(name: "orbstack", desc: "Alternative rapide et légère à Docker Desktop pour Linux et Conteneurs.", homepage: "https://orbstack.dev", version: "Latest", category: "macOS Apps (Cask)", isCask: true)
    ]
    
    public init() {}
    
    public func fetchFeaturedItems() async -> [CatalogItem] {
        return cachedFeatured
    }
    
    // MARK: - Live Global Homebrew Search
    public func searchGlobalPackages(query: String) async throws -> [BrewPackage] {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return [] }
        
        // 1. Search names via 'brew search'
        let result = try await BrewCommandService.shared.runSynchronous(arguments: ["search", trimmed])
        guard let output = String(data: result.data, encoding: .utf8), !output.isEmpty else {
            return []
        }
        
        let lines = output.components(separatedBy: .newlines).filter { line in
            !line.isEmpty && !line.hasPrefix("==>") && !line.hasPrefix("Warning:") && !line.hasPrefix("If you meant")
        }
        
        // Limit to top 15 matches to ensure snappy performance
        let topNames = Array(lines.prefix(15))
        guard !topNames.isEmpty else { return [] }
        
        // 2. Fetch full metadata in one batch command via 'brew info --json=v2'
        var infoArgs = ["info", "--json=v2"]
        infoArgs.append(contentsOf: topNames)
        
        let infoResult = try await BrewCommandService.shared.runSynchronous(arguments: infoArgs)
        let cleanJSON = BrewCommandService.shared.extractCleanJSONData(from: infoResult.data)
        
        guard let decoded = try? JSONDecoder().decode(BrewJSONResponseV2.self, from: cleanJSON) else {
            return []
        }
        
        var results: [BrewPackage] = []
        
        for f in decoded.formulae {
            let pkg = f.toBrewPackage(outdatedList: [])
            results.append(pkg)
        }
        
        for c in decoded.casks {
            let pkg = c.toBrewPackage(outdatedList: [], installedVersion: nil)
            results.append(pkg)
        }
        
        return results.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
